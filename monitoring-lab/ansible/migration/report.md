# Migration report

Generated from Checkmk site `lab` on 2026-11-27 15:30 UTC.

## Mapped to Nagios

| Host | Checkmk service | Nagios command | Thresholds came from |
| --- | --- | --- | --- |
| app01 | CPU load | `/usr/lib/nagios/plugins/check_load -r -w 999,999,5 -c 999,999,10` | Checkmk default for levels15 |
| app01 | Check_MK Agent | `check_nrpe (agent version)` | n/a |
| app01 | Filesystem / | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /` | Default filesystem levels (/linux) |
| app01 | Filesystem /boot | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /boot` | Default filesystem levels (/linux) |
| app01 | Filesystem /boot/efi | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /boot/efi` | Default filesystem levels (/linux) |
| app01 | Filesystem /sys/firmware/efi/efivars | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /sys/firmware/efi/efivars` | Default filesystem levels (/linux) |
| app01 | Memory | `/usr/local/lib/nagios/plugins/check_mem -w 80 -c 90` | Checkmk default for levels_ram |
| app02 | CPU load | `/usr/lib/nagios/plugins/check_load -r -w 999,999,2 -c 999,999,4` | Tightened after an incident (nobody remembers which) (/linux) |
| app02 | Check_MK Agent | `check_nrpe (agent version)` | n/a |
| app02 | Filesystem / | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /` | Default filesystem levels (/linux) |
| app02 | Filesystem /boot | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /boot` | Default filesystem levels (/linux) |
| app02 | Filesystem /boot/efi | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /boot/efi` | Default filesystem levels (/linux) |
| app02 | Filesystem /sys/firmware/efi/efivars | `/usr/lib/nagios/plugins/check_disk -w 15% -c 5% -p /sys/firmware/efi/efivars` | Default filesystem levels (/linux) |
| app02 | Memory | `/usr/local/lib/nagios/plugins/check_mem -w 80 -c 90` | Checkmk default for levels_ram |
| db01 | Backup_age | `shared plugin Backup_age` | n/a |
| db01 | CPU load | `/usr/lib/nagios/plugins/check_load -r -w 999,999,5 -c 999,999,10` | Checkmk default for levels15 |
| db01 | Check_MK Agent | `check_nrpe (agent version)` | n/a |
| db01 | Filesystem / | `/usr/lib/nagios/plugins/check_disk -w 9% -c 4% -p /` | DB volumes run full by design (/linux/db) |
| db01 | Filesystem /boot | `/usr/lib/nagios/plugins/check_disk -w 9% -c 4% -p /boot` | DB volumes run full by design (/linux/db) |
| db01 | Filesystem /boot/efi | `/usr/lib/nagios/plugins/check_disk -w 9% -c 4% -p /boot/efi` | DB volumes run full by design (/linux/db) |
| db01 | Filesystem /sys/firmware/efi/efivars | `/usr/lib/nagios/plugins/check_disk -w 9% -c 4% -p /sys/firmware/efi/efivars` | DB volumes run full by design (/linux/db) |
| db01 | Memory | `/usr/local/lib/nagios/plugins/check_mem -w 80 -c 90` | Checkmk default for levels_ram |

## Needs a decision

| Checkmk plugin | Suggestion | Services |
| --- | --- | --- |
| kernel_util | triage | 3 |
| check-mk | retire: the Nagios host check and 'NRPE agent' service cover reachability | 3 |
| check-mk-inventory | retire: Checkmk's own service discovery; Nagios config comes from Git | 3 |
| diskstat | metrics: send to the time-series database and graph in Grafana, alert there if needed | 3 |
| lnx_if | decide: check_ifoperstatus needs SNMP; write a small plugin or rely on the host check | 3 |
| kernel_performance | metrics: graph it | 3 |
| mounts | write a plugin: compare findmnt options with the expected list | 9 |
| chrony | replace: check_ntp_time against the NTP server | 3 |
| cpu_threads | replace: check_procs -w/-c on the thread count | 3 |
| systemd_units_services_summary | replace: a systemd plugin, or check_procs per critical service | 3 |
| systemd_units_sockets_summary | triage | 3 |
| tcp_conn_stats | metrics: graph it; no alert today | 3 |
| uptime | retire: informational, no threshold; graph it instead | 3 |
