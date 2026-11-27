from compare import compare, expected_pairs


def test_verdicts():
    pairs = [
        ("app01", "Filesystem /", "Filesystem /"),
        ("app01", "Check_MK Agent", "NRPE agent"),
        ("db01", "Backup_age", "Backup_age"),
        ("db01", "CPU load", "CPU load"),
    ]
    cmk = {
        ("app01", "Filesystem /"): 0,
        ("app01", "Check_MK Agent"): 0,
        ("db01", "Backup_age"): 1,
        ("db01", "CPU load"): 0,
    }
    nagios = {("app01", "Filesystem /"): 0, ("app01", "NRPE agent"): 0, ("db01", "Backup_age"): 2}
    rows, problems = compare(pairs, cmk, nagios)
    verdicts = {(r[0], r[1]): r[4] for r in rows}
    assert verdicts[("app01", "Filesystem /")] == "match"
    assert verdicts[("app01", "Check_MK Agent -> NRPE agent")] == "match"
    assert verdicts[("db01", "Backup_age")] == "DIFFERS"
    assert verdicts[("db01", "CPU load")] == "MISSING"
    assert problems == 2


def test_pending_is_not_a_problem():
    rows, problems = compare([("app01", "Memory", "Memory")], {("app01", "Memory"): None}, {("app01", "Memory"): 0})
    assert rows[0][4] == "pending" and problems == 0


def test_expected_pairs_reads_exported_vars(tmp_path):
    (tmp_path / "group_vars/folder_app").mkdir(parents=True)
    (tmp_path / "group_vars/folder_app/nagios.yml").write_text(
        "nagios_group_checks:\n- {name: NRPE agent, nrpe: null, replaces: Check_MK Agent}\n"
    )
    (tmp_path / "host_vars/app02").mkdir(parents=True)
    (tmp_path / "host_vars/app02/nagios.yml").write_text("nagios_host_checks:\n- {name: CPU load, nrpe: check_load}\n")
    pairs = expected_pairs(tmp_path, {"folder_app": ["app01", "app02"]})
    assert pairs == [
        ("app01", "Check_MK Agent", "NRPE agent"),
        ("app02", "CPU load", "CPU load"),
        ("app02", "Check_MK Agent", "NRPE agent"),
    ]
