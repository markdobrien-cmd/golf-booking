#!/usr/bin/env python3
"""Export a Checkmk site's monitoring into Ansible variables that generate the Nagios equivalent.

What it does, in order:
  1. Reads hosts, their folders and their monitored services from the Checkmk REST API.
  2. Works out the thresholds each service really gets, by resolving Checkmk's layered rules
     (subfolder rules before parent folders, first rule to set a key wins).
  3. Maps each service to a Nagios check run through NRPE, or puts it on a triage list when
     there's no obvious equivalent. Deciding those is the judgement-heavy "long tail".
  4. Writes group_vars (checks every host in a folder shares) and host_vars (the exceptions),
     plus migration/report.md explaining every decision.

Usage (04-export.yml runs it with the right values):
  export_checkmk.py --url http://1.2.3.4/ --site lab --user cmkadmin --secret-file .secrets/cmkadmin \
                    --out ansible/

Only the standard library and PyYAML (which comes with Ansible) are needed.
"""

from __future__ import annotations

import argparse
import ast
import datetime as dt
import json
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import yaml

PLUGIN_DIR = "/usr/lib/nagios/plugins"
LOCAL_PLUGIN_DIR = "/usr/local/lib/nagios/plugins"

# Checkmk ruleset that holds each mapped plugin's parameters, and Checkmk's built-in defaults
# (what a service gets when no rule matches). Check these against your Checkmk version.
RULESETS = {
    "df": ("checkgroup_parameters:filesystem", {"levels": (80.0, 90.0)}),
    "cpu_loads": ("checkgroup_parameters:cpu_load", {"levels15": (5.0, 10.0)}),
    "mem_linux": ("checkgroup_parameters:memory_linux", {"levels_ram": ("perc_used", (80.0, 90.0))}),
    "mem_used": ("checkgroup_parameters:memory", {"levels": (150.0, 200.0)}),
}

# What to suggest for services with no direct equivalent. Anything not listed is "triage".
TRIAGE_HINTS = {
    "check-mk-inventory": "retire: Checkmk's own service discovery; Nagios config comes from Git",
    "check-mk": "retire: the Nagios host check and 'NRPE agent' service cover reachability",
    "check-mk-ping": "replace: the Nagios host check (lab_host_alive); use check_ping if ICMP is allowed",
    "uptime": "retire: informational, no threshold; graph it instead",
    "diskstat": "metrics: send to the time-series database and graph in Grafana, alert there if needed",
    "lnx_if": "decide: check_ifoperstatus needs SNMP; write a small plugin or rely on the host check",
    "tcp_conn_stats": "metrics: graph it; no alert today",
    "cpu_utilization_os": "decide: no standard plugin; write one if anyone alerts on it, else graph it",
    "kernel_performance": "metrics: graph it",
    "cpu_threads": "replace: check_procs -w/-c on the thread count",
    "mounts": "write a plugin: compare findmnt options with the expected list",
    "systemd_units_services_summary": "replace: a systemd plugin, or check_procs per critical service",
    "chrony": "replace: check_ntp_time against the NTP server",
    "timesyncd": "replace: check_ntp_time against the NTP server",
    "lnx_thermal": "retire: virtual machines have no useful thermal sensors",
}


# --- Talking to Checkmk ---


class Checkmk:
    def __init__(self, url: str, site: str, user: str, secret: str):
        self.base = f"{url.rstrip('/')}/{site}/check_mk/api/1.0"
        self.auth = f"Bearer {user} {secret}"

    def get(self, path: str, params: list[tuple[str, str]] | None = None) -> dict:
        query = f"?{urllib.parse.urlencode(params)}" if params else ""
        request = urllib.request.Request(
            self.base + path + query,
            headers={"Authorization": self.auth, "Accept": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)

    def hosts(self) -> list[Host]:
        data = self.get("/domain-types/host_config/collections/all")
        return [
            Host(name=h["id"], folder=h["extensions"]["folder"], attributes=h["extensions"]["attributes"])
            for h in data["value"]
        ]

    def services(self) -> list[dict]:
        columns = ["host_name", "description", "check_command", "state"]
        data = self.get("/domain-types/service/collections/all", [("columns", c) for c in columns])
        return [s["extensions"] for s in data["value"]]

    def rules(self, ruleset: str) -> list[dict]:
        data = self.get("/domain-types/rule/collections/all", [("ruleset_name", ruleset)])
        return [r["extensions"] | {"id": r["id"]} for r in data["value"]]


# --- Working out which rules apply ---


@dataclass
class Host:
    name: str
    folder: str
    attributes: dict = field(default_factory=dict)

    @property
    def group(self) -> str:
        """Ansible group for the host's folder: /linux/app -> folder_app."""
        return "folder_" + self.folder.rstrip("/").split("/")[-1]


class UnsupportedRule(Exception):
    """A rule condition this exporter can't evaluate. It goes on the triage list, not guessed."""


def folder_contains(rule_folder: str, host_folder: str) -> bool:
    rule_folder = rule_folder.rstrip("/") or "/"
    return rule_folder == "/" or host_folder == rule_folder or host_folder.startswith(rule_folder + "/")


def rule_applies(rule: dict, host: Host) -> bool:
    if rule.get("properties", {}).get("disabled"):
        return False
    if not folder_contains(rule["folder"], host.folder):
        return False
    conditions = rule.get("conditions", {})
    if conditions.get("host_tags") or conditions.get("host_label_groups") or conditions.get("host_labels"):
        raise UnsupportedRule(f"rule {rule['id']} matches on tags or labels")
    host_name = conditions.get("host_name")
    if host_name:
        listed = host.name in host_name.get("match_on", [])
        return listed if host_name.get("operator", "one_of") == "one_of" else not listed
    return True


def precedence(rule: dict) -> tuple[int, int]:
    """Deeper folders first; within a folder, the order shown in the GUI."""
    depth = len([p for p in rule["folder"].split("/") if p])
    return (-depth, rule.get("folder_index", 0))


def effective_params(rules: list[dict], host: Host, defaults: dict) -> tuple[dict, list[str]]:
    """Merge dictionary rules the way Checkmk does: the first matching rule to set a key wins."""
    params: dict = {}
    sources: list[str] = []
    for rule in sorted((r for r in rules if rule_applies(r, host)), key=precedence):
        value = ast.literal_eval(rule["value_raw"])
        new_keys = {k: v for k, v in value.items() if k not in params}
        if new_keys:
            params |= new_keys
            sources.append(f"{rule['properties'].get('description') or rule['id']} ({rule['folder']})")
    for key, value in defaults.items():
        if key not in params:
            params[key] = value
            sources.append(f"Checkmk default for {key}")
    return params, sources


# --- Mapping Checkmk services to Nagios checks ---


def nrpe_name(text: str) -> str:
    """'/boot/efi' -> 'boot_efi', '/' -> 'root': safe for an NRPE command name."""
    cleaned = re.sub(r"[^A-Za-z0-9]+", "_", text).strip("_").lower()
    return cleaned or "root"


def map_service(plugin: str, description: str, params: dict) -> dict | None:
    """Return a Nagios check for this Checkmk service, or None if it needs a human decision."""
    if plugin == "df":
        mount = description.removeprefix("Filesystem ")
        warn, crit = params["levels"]  # Checkmk: % used.  check_disk: % free.
        return {
            "name": description,
            "nrpe": f"check_disk_{nrpe_name(mount)}",
            "command": f"{PLUGIN_DIR}/check_disk -w {100 - warn:g}% -c {100 - crit:g}% -p {mount}",
        }
    if plugin == "cpu_loads":
        warn, crit = params["levels15"]  # per core, 15-minute average only
        return {
            "name": description,
            "nrpe": "check_load",
            # -r divides by the number of cores, as Checkmk does. 1- and 5-minute levels are set
            # out of reach because Checkmk only alerts on the 15-minute average by default.
            "command": f"{PLUGIN_DIR}/check_load -r -w 999,999,{warn:g} -c 999,999,{crit:g}",
        }
    if plugin == "mem_linux":
        kind, (warn, crit) = params["levels_ram"]
        if kind != "perc_used":
            return None
        return {
            "name": description,
            "nrpe": "check_mem",
            "command": f"{LOCAL_PLUGIN_DIR}/check_mem -w {warn:g} -c {crit:g}",
        }
    if plugin == "mem_used":
        warn, crit = params["levels"]
        if warn > 100:  # Checkmk default: RAM + swap above 150% of RAM. No sensible plugin flag for that.
            warn, crit = 80.0, 90.0
        return {
            "name": description,
            "nrpe": "check_mem",
            "command": f"{LOCAL_PLUGIN_DIR}/check_mem -w {warn:g} -c {crit:g}",
            "note": "Checkmk's default levels count RAM plus swap; mapped to 80/90% of RAM. Agree with the owner.",
        }
    if plugin == "mrpe":
        # MRPE already runs a Nagios plugin on the host, so NRPE can run the same one.
        return {"name": description, "nrpe": f"mrpe_{nrpe_name(description)}", "shared_plugin": description}
    if plugin == "checkmk_agent":
        return {"name": "NRPE agent", "nrpe": None, "replaces": description}
    return None


def plugin_of(check_command: str) -> str:
    """'check_mk-df' -> 'df'; 'check-mk-ping!-w ...' -> 'check-mk-ping' (arguments dropped)."""
    return check_command.split("!", 1)[0].removeprefix("check_mk-")


# --- Putting it together ---


def build(hosts: list[Host], services: list[dict], rules: dict[str, list[dict]]) -> dict:
    by_host: dict[str, list[dict]] = {h.name: [] for h in hosts}
    triage: dict[str, dict] = {}
    report: list[dict] = []
    host_index = {h.name: h for h in hosts}

    for svc in sorted(services, key=lambda s: (s["host_name"], s["description"])):
        host = host_index.get(svc["host_name"])
        if host is None:
            continue
        plugin = plugin_of(svc["check_command"])
        check, sources, reason = None, [], ""
        try:
            if plugin in RULESETS:
                ruleset, defaults = RULESETS[plugin]
                params, sources = effective_params(rules.get(ruleset, []), host, defaults)
            else:
                params = {}
            check = map_service(plugin, svc["description"], params)
        except UnsupportedRule as exc:
            reason = f"decide by hand: {exc}"
        if check:
            by_host[host.name].append(check)
            report.append({"host": host.name, "service": svc["description"], "check": check, "sources": sources})
        else:
            entry = triage.setdefault(
                plugin, {"plugin": plugin, "suggestion": reason or TRIAGE_HINTS.get(plugin, "triage"), "services": []}
            )
            entry["services"].append(f"{host.name}: {svc['description']}")

    group_checks, host_checks = split_by_group(hosts, by_host)
    return {"group_checks": group_checks, "host_checks": host_checks, "triage": triage, "report": report}


def split_by_group(hosts: list[Host], by_host: dict[str, list[dict]]):
    """Checks that every host in a folder shares go to group_vars; the rest are host exceptions."""
    group_members: dict[str, list[str]] = {}
    for host in hosts:
        group_members.setdefault(host.group, []).append(host.name)

    group_checks: dict[str, list[dict]] = {}
    host_checks: dict[str, list[dict]] = {}
    for group, members in sorted(group_members.items()):
        shared = [c for c in by_host[members[0]] if all(c in by_host[m] for m in members[1:])]
        group_checks[group] = shared
        for member in members:
            extra = [c for c in by_host[member] if c not in shared]
            if extra:
                host_checks[member] = extra
    return group_checks, host_checks


def write_outputs(result: dict, out: Path, site: str) -> list[Path]:
    stamp = dt.datetime.now(dt.UTC).strftime("%Y-%m-%d %H:%M UTC")
    header = (
        f"# Generated by scripts/export_checkmk.py from Checkmk site '{site}' on {stamp}.\n"
        "# Review it like any other change. After cut-over this file, not Checkmk, is the source of truth.\n"
    )
    written = []

    # Remove what the last export wrote, so a host or folder that has gone doesn't leave stale checks.
    for old in [*out.glob("group_vars/folder_*/nagios.yml"), *out.glob("host_vars/*/nagios.yml")]:
        if old.read_text().startswith("# Generated by scripts/export_checkmk.py"):
            old.unlink()
            if not any(old.parent.iterdir()):
                old.parent.rmdir()

    def dump(path: Path, data) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(header + yaml.safe_dump(data, sort_keys=False, width=120))
        written.append(path)

    for group, checks in result["group_checks"].items():
        dump(out / "group_vars" / group / "nagios.yml", {"nagios_group_checks": checks})
    for host, checks in result["host_checks"].items():
        dump(out / "host_vars" / host / "nagios.yml", {"nagios_host_checks": checks})
    dump(out / "migration" / "triage.yml", {"needs_a_decision": list(result["triage"].values())})

    lines = [
        "# Migration report",
        "",
        f"Generated from Checkmk site `{site}` on {stamp}.",
        "",
        "## Mapped to Nagios",
        "",
        "| Host | Checkmk service | Nagios command | Thresholds came from |",
        "| --- | --- | --- | --- |",
    ]
    for row in result["report"]:
        check = row["check"]
        command = check.get("command") or (
            f"shared plugin {check['shared_plugin']}" if "shared_plugin" in check else "check_nrpe (agent version)"
        )
        lines.append(f"| {row['host']} | {row['service']} | `{command}` | {'; '.join(row['sources']) or 'n/a'} |")
    lines += ["", "## Needs a decision", "", "| Checkmk plugin | Suggestion | Services |", "| --- | --- | --- |"]
    for entry in result["triage"].values():
        lines.append(f"| {entry['plugin']} | {entry['suggestion']} | {len(entry['services'])} |")
    report = out / "migration" / "report.md"
    report.write_text("\n".join(lines) + "\n")
    written.append(report)
    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--url", required=True, help="Checkmk server, for example http://1.2.3.4/")
    parser.add_argument("--site", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--secret-file", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path, help="the ansible/ directory")
    args = parser.parse_args()

    cmk = Checkmk(args.url, args.site, args.user, args.secret_file.read_text().strip())
    hosts = cmk.hosts()
    services = cmk.services()
    rules = {ruleset: cmk.rules(ruleset) for ruleset, _ in RULESETS.values()}
    result = build(hosts, services, rules)
    for path in write_outputs(result, args.out, args.site):
        print(f"wrote {path}")
    mapped = sum(len(c) for c in result["group_checks"].values()) + sum(len(c) for c in result["host_checks"].values())
    print(
        f"{len(hosts)} hosts, {len(services)} Checkmk services, {mapped} Nagios checks, "
        f"{len(result['triage'])} plugins to triage"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
