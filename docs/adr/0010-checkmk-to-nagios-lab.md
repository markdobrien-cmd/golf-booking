# 0010: A Checkmk-to-Nagios migration lab on EC2

**Status:** accepted, 2026-11-26

## Context
A team running a large, hand-built Checkmk estate plans to move to Nagios. The hard parts are not
installing Nagios: they are knowing what Checkmk actually monitors (services it discovered, thresholds
spread across layered rules), deciding what to do with checks that have no Nagios equivalent, and
proving the new system agrees with the old one before anyone relies on it. We want a small, realistic
version of that problem to practise on, built the way it would be built for real: in code.

## Decision
- **A separate, destroyable environment** (`infra/envs/monlab`): one VPC with a single public subnet,
  five EC2 instances (Checkmk server, Nagios server, three monitored hosts). Own state key, so it comes
  and goes without touching dev. Included in the nightly teardown.
- **Ansible does all configuration** (`monitoring-lab/ansible`), with a dynamic inventory built from EC2
  tags. Checkmk and its agent are installed with the official `checkmk.general` roles.
- **The "existing" Checkmk config is seeded by a playbook** that stands in for years of GUI clicks: a
  default rule in a parent folder, an override in a subfolder, and a one-off rule on a single host.
- **An exporter reads Checkmk through its REST API** and writes Ansible variables: checks shared by every
  host in a folder go to `group_vars`, exceptions to `host_vars`. It resolves Checkmk's rule precedence
  itself (subfolder first, first rule to set a key wins) and refuses to guess rules it can't evaluate.
  Services with no clear equivalent go to a triage list with a suggestion, for a human (or an AI-assisted
  review) to decide. After cut-over, those variables in Git are the source of truth.
- **Nagios is generated, never edited**: hosts, hostgroups and services from the variables; NRPE
  commands on each host from the same variables. `nagios4 -v` runs before every restart.
- **Both agents run side by side** during the parallel run, sharing plugins where possible: a check
  defined once (`lab_shared_plugins`) runs under Checkmk via MRPE and under Nagios via NRPE.
- **A comparison script is the cut-over gate**: it pairs each migrated service across the two systems and
  fails on any missing service or state difference. Nagios notifications stay off until a wave passes.
- **The same playbooks run in containers** (`monitoring-lab/test`), locally and in CI, so changes are
  tested without an AWS bill.

### Alternatives considered
- **Docker only, no EC2:** cheaper and faster, but containers have no systemd, so the official Checkmk
  agent role and real service management can't be exercised. Kept as the test harness instead.
- **Private subnets with SSM Session Manager:** no public IPs at all, the production-grade choice. Needs
  a NAT gateway or VPC endpoints (a daily cost floor) and the SSM connection plugin for Ansible.
- **Agentless Nagios checks over SSH (`check_by_ssh`):** avoids a second agent during the overlap and
  suits a pilot. NRPE is kept because it is what most Nagios estates run.
- **Converting Checkmk's `.mk` config files directly:** they are Python and could be parsed, but the
  REST API is supported, versioned and reflects what the GUI shows.

## Consequences
- The lab costs about $0.11 an hour while up; nothing persists overnight.
- Admin access is SSH and plain HTTP from one IP. Acceptable for a lab; production would use TLS and
  private access.
- The REST API is called as `cmkadmin`; production would use a dedicated automation user.
- Memory thresholds don't map one to one: Checkmk's default counts RAM plus swap, the Nagios plugin
  counts RAM. The exporter maps it and notes the difference in the report.
