#!/usr/bin/env python3
"""Parallel-run check: do Checkmk and Nagios agree about every migrated service?

Reads the list of migrated checks from the exported Ansible variables (so it knows that Nagios
"NRPE agent" replaces Checkmk "Check_MK Agent", for example), asks both systems for the current
state of each, and prints one line per service. Exits 1 if any service is missing from Nagios or
the two states differ, so it can gate a cut-over in CI or cron.

Checkmk is read through its REST API; Nagios through its statusjson.cgi.
Only the standard library and PyYAML are needed.
"""

from __future__ import annotations

import argparse
import base64
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

import yaml

STATE_NAMES = {0: "OK", 1: "WARN", 2: "CRIT", 3: "UNKNOWN", None: "PENDING"}
# statusjson.cgi reports service status as a bit value.
NAGIOS_STATUS = {1: None, 2: 0, 4: 1, 8: 3, 16: 2}


def http_json(url: str, auth_header: str) -> dict:
    request = urllib.request.Request(url, headers={"Authorization": auth_header, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def checkmk_states(url: str, site: str, user: str, secret: str) -> dict[tuple[str, str], int | None]:
    columns = ["host_name", "description", "state", "has_been_checked"]
    query = urllib.parse.urlencode([("columns", c) for c in columns])
    data = http_json(
        f"{url.rstrip('/')}/{site}/check_mk/api/1.0/domain-types/service/collections/all?{query}",
        f"Bearer {user} {secret}",
    )
    states = {}
    for item in data["value"]:
        s = item["extensions"]
        states[(s["host_name"], s["description"])] = s["state"] if s.get("has_been_checked", 1) else None
    return states


def nagios_states(url: str, password: str) -> dict[tuple[str, str], int | None]:
    token = base64.b64encode(f"nagiosadmin:{password}".encode()).decode()
    data = http_json(
        f"{url.rstrip('/')}/cgi-bin/nagios4/statusjson.cgi?query=servicelist&details=true", f"Basic {token}"
    )
    states = {}
    for host, services in data["data"]["servicelist"].items():
        for description, detail in services.items():
            states[(host, description)] = NAGIOS_STATUS.get(detail["status"])
    return states


def expected_pairs(vars_dir: Path, hosts_by_group: dict[str, list[str]]) -> list[tuple[str, str, str]]:
    """(host, Checkmk service name, Nagios service name) for every exported check."""
    pairs = []
    for group_file in sorted(vars_dir.glob("group_vars/folder_*/nagios.yml")):
        group = group_file.parent.name
        for check in yaml.safe_load(group_file.read_text()).get("nagios_group_checks", []):
            for host in hosts_by_group.get(group, []):
                pairs.append((host, check.get("replaces", check["name"]), check["name"]))
    for host_file in sorted(vars_dir.glob("host_vars/*/nagios.yml")):
        host = host_file.parent.name
        for check in yaml.safe_load(host_file.read_text()).get("nagios_host_checks", []):
            pairs.append((host, check.get("replaces", check["name"]), check["name"]))
    return sorted(pairs)


def compare(pairs, cmk: dict, nagios: dict) -> tuple[list[tuple], int]:
    rows, problems = [], 0
    for host, cmk_name, nagios_name in pairs:
        a, b = cmk.get((host, cmk_name), "missing"), nagios.get((host, nagios_name), "missing")
        if a == "missing" or b == "missing":
            verdict = "MISSING"
        elif a is None or b is None:
            verdict = "pending"  # not checked yet on one side: wait a minute and run again
        elif a == b:
            verdict = "match"
        else:
            verdict = "DIFFERS"
        if verdict in ("MISSING", "DIFFERS"):
            problems += 1
        name = cmk_name if cmk_name == nagios_name else f"{cmk_name} -> {nagios_name}"
        rows.append((host, name, label(a), label(b), verdict))
    return rows, problems


def label(state) -> str:
    return state if state == "missing" else STATE_NAMES.get(state, str(state))


def hosts_by_group_from_checkmk(url, site, user, secret) -> dict[str, list[str]]:
    data = http_json(
        f"{url.rstrip('/')}/{site}/check_mk/api/1.0/domain-types/host_config/collections/all",
        f"Bearer {user} {secret}",
    )
    groups: dict[str, list[str]] = {}
    for h in data["value"]:
        groups.setdefault("folder_" + h["extensions"]["folder"].rstrip("/").split("/")[-1], []).append(h["id"])
    return groups


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--checkmk-url", required=True)
    parser.add_argument("--site", required=True)
    parser.add_argument("--checkmk-user", required=True)
    parser.add_argument("--checkmk-secret-file", required=True, type=Path)
    parser.add_argument("--nagios-url", required=True)
    parser.add_argument("--nagios-password-file", required=True, type=Path)
    parser.add_argument("--vars-dir", required=True, type=Path, help="the ansible/ directory")
    args = parser.parse_args()

    secret = args.checkmk_secret_file.read_text().strip()
    groups = hosts_by_group_from_checkmk(args.checkmk_url, args.site, args.checkmk_user, secret)
    pairs = expected_pairs(args.vars_dir, groups)
    cmk = checkmk_states(args.checkmk_url, args.site, args.checkmk_user, secret)
    nagios = nagios_states(args.nagios_url, args.nagios_password_file.read_text().strip())
    rows, problems = compare(pairs, cmk, nagios)
    if not rows:
        print("Nothing to compare: no exported checks found. Run 04-export.yml and 05-nagios.yml first.")
        return 1

    widths = [
        max(len(str(r[i])) for r in rows + [("Host", "Service", "Checkmk", "Nagios", "Result")]) for i in range(5)
    ]
    for row in [("Host", "Service", "Checkmk", "Nagios", "Result")] + rows:
        print("  ".join(str(v).ljust(w) for v, w in zip(row, widths, strict=True)))
    not_migrated = len([k for k in cmk if k[0] in {p[0] for p in pairs}]) - len({(p[0], p[1]) for p in pairs})
    print(
        f"\n{len(rows)} migrated services compared, {problems} problems. "
        f"{max(not_migrated, 0)} Checkmk services not migrated (see migration/triage.yml)."
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
