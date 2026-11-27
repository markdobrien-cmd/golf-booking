#!/usr/bin/env bash
# Run the whole lab in local containers: ./run.sh   (clean up with: ./run.sh down)
set -euo pipefail
cd "$(dirname "$0")"
ANSIBLE_DIR=../ansible
mkdir -p "$ANSIBLE_DIR/.secrets"
[ -s "$ANSIBLE_DIR/.secrets/cmkadmin" ] || python3 -c "import secrets,string;print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(20)))" > "$ANSIBLE_DIR/.secrets/cmkadmin"
export CMK_PASSWORD="$(cat "$ANSIBLE_DIR/.secrets/cmkadmin")"

if [ "${1:-}" = down ]; then docker compose down -v; exit 0; fi

docker compose up -d
export ANSIBLE_CONFIG="$ANSIBLE_DIR/ansible.cfg"
play() { ansible-playbook -i inventory.yml -e @vars.yml -e "lab_secrets_dir=$PWD/$ANSIBLE_DIR/.secrets" "$@"; }
play prepare.yml
play "$ANSIBLE_DIR/02-targets.yml"
play "$ANSIBLE_DIR/03-seed-checkmk.yml"
play "$ANSIBLE_DIR/04-export.yml"
play "$ANSIBLE_DIR/05-nagios.yml"
echo "Waiting two minutes so both systems have checked everything at least once..."
sleep 120
play "$ANSIBLE_DIR/06-compare.yml"
