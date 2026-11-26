# Checkmk to Nagios: migration lab

A small, working version of a real migration: an "inherited" Checkmk estate with hand-built rules, a
Nagios server generated entirely from Git, both monitoring the same hosts side by side, and a
comparison that proves they agree before anything is cut over. The reasoning is in
[ADR 0010](../docs/adr/0010-checkmk-to-nagios-lab.md).

```
 Terraform (infra/envs/monlab)        five EC2 instances, tagged with their role and Checkmk folder
        |
 01-checkmk-server.yml               Checkmk server and site "lab" (official checkmk.general.server role)
 02-targets.yml                      on each host: Checkmk agent + NRPE + shared plugins
 03-seed-checkmk.yml                 the "hand-built" config: folders, hosts, layered rules
        |
 04-export.yml  --> group_vars/ host_vars/ migration/      Checkmk REST API -> Ansible variables
        |
 05-nagios.yml                       NRPE commands on the hosts, Nagios objects on the server, validated
 06-compare.yml                      Checkmk vs Nagios, service by service; fails on any difference
```

## What each step shows

| Step | In a real migration this is... |
| --- | --- |
| Dynamic inventory from EC2 tags | The estate's own record (a CMDB, cloud tags) as the source of truth, not a host list someone maintains |
| 02: two agents per host | The cost of a safe parallel run. Kept short per wave; Ansible removes the old agent at sign-off |
| `lab_shared_plugins` | One plugin definition run by both systems (MRPE for Checkmk, NRPE for Nagios), so they can't drift |
| 03: layered rules | A default in `/linux`, an override in `/linux/db`, a one-off on `app02`: what years of GUI edits look like |
| 04: the exporter | Working out what each service *really* gets, then writing it as reviewable code |
| `migration/triage.yml` | The long tail: Checkmk services with no obvious Nagios equivalent. Decide each one: replace, write a plugin, graph it, or retire it |
| 05: `nagios4 -v` before restart | Nagios refuses to start on a bad config, so a broken merge can't take monitoring down |
| `nagios_notifications_enabled: false` | Nagios pages nobody until its wave is signed off; at any moment one system pages for a host |
| 06: the comparison | The cut-over gate. Run it daily; sign a wave off after an agreed run of clean days |

## Before you start

On your laptop (WSL is fine):

```bash
pip install ansible-core==2.19.4 boto3
cd monitoring-lab/ansible
ansible-galaxy collection install -r requirements.yml
```

Then build the servers: see [`infra/envs/monlab/README.md`](../infra/envs/monlab/README.md).

## Run it

From `monitoring-lab/ansible`, with `AWS_PROFILE=golf` set and logged in:

```bash
ansible-inventory --graph              # five hosts, grouped by role and folder, read from EC2 tags
ansible all -m ping                    # Ansible can log in everywhere

ansible-playbook 01-checkmk-server.yml # about 5 minutes: downloads and installs Checkmk
ansible-playbook 02-targets.yml
ansible-playbook 03-seed-checkmk.yml
ansible-playbook 04-export.yml
git diff                               # review what the exporter wrote, as you would a merge request
ansible-playbook 05-nagios.yml
# give both systems two minutes to run every check, then:
ansible-playbook 06-compare.yml
```

Step 4 writes `group_vars/folder_*/nagios.yml`, `host_vars/*/nagios.yml` and `migration/`. They aren't in
the repo yet: commit them once you've reviewed your first AWS run, because from then on they are the
Nagios config.

Passwords are created on first use in `ansible/.secrets/` (git-ignored). Log in to the web UIs with them:

| | URL | User |
| --- | --- | --- |
| Checkmk | `terraform output checkmk_url` | `cmkadmin`, password in `.secrets/cmkadmin` |
| Nagios | `terraform output nagios_url` | `nagiosadmin`, password in `.secrets/nagiosadmin` |

## Things to try

1. **Read the migration report.** `migration/report.md` lists every Nagios check and which rule each
   threshold came from. Find `db01`'s filesystem levels and `app02`'s CPU load: why are they different?
2. **Make the two systems disagree.** On db01: `sudo touch -d '-30 hours' /var/backups/lab/last_success`.
   Within a minute both show `Backup_age` as WARNING, because they run the same plugin. Now edit the
   threshold in `group_vars/all.yml` (`lab_shared_plugins`) to `-w 40`, run `05-nagios.yml` only, and
   compare again: Nagios is OK, Checkmk is still WARNING, and `06-compare.yml` fails. That's the gate
   doing its job.
3. **Change a rule in the Checkmk GUI** (say the default filesystem levels), activate, then run
   `04-export.yml` and `git diff`. The change shows up as a code diff to review.
4. **Work the triage list.** Pick an entry in `migration/triage.yml` and implement it: a new plugin in
   `roles/lab_target/files/`, a mapping in `scripts/export_checkmk.py` with a unit test, then 04, 05, 06.
   This is the part where an AI assistant helps most: drafting the plugin and the test, which you review.
5. **Cut over a wave.** Set `nagios_notifications_enabled: true` for `folder_app` only (a
   `group_vars/folder_app/cutover.yml` file) and think through what else has to happen: Checkmk
   notifications off for those hosts, the Checkmk agent removed, the hosts deleted from Checkmk.

## Without AWS

`test/run.sh` runs steps 2 to 6 against local containers (Checkmk's official image stands in for step 1).
CI runs it on every pull request that touches the lab. It needs Docker, Ansible and the collections above.

```bash
./test/run.sh        # about 10 minutes the first time
./test/run.sh down   # remove the containers
```

Containers don't run systemd, so a few things differ (`lab_containers: true`): the agent is served by
`socat` instead of systemd, and containers find fewer services than an EC2 instance (no real
filesystems or CPU load), so expect a shorter report.
