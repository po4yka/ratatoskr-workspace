#!/usr/bin/env bash
# Execute the production role on a private config file. The handler records a reload only.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/ratatoskr-sites-ingress.XXXXXX")
trap 'status=$?; if ((status != 0)); then cat "$scratch"/*.log 2>/dev/null || true; fi; rm -rf -- "$scratch"' EXIT
command -v cloudflared >/dev/null
cat > "$scratch/config.yml" <<'YAML'
tunnel: 00000000-0000-4000-8000-000000000001
ingress:
  - hostname: api.example.test
    service: http://127.0.0.1:8080
  - service: http_status:404
YAML
cat > "$scratch/test.yml" <<'YAML'
- hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - ansible.builtin.include_role:
        name: host
        tasks_from: sites-ingress
    - ansible.builtin.meta: flush_handlers
  handlers:
    - name: Reload cloudflared
      ansible.builtin.debug:
        msg: 'Reload observed in isolated test'
YAML
# A role's own handler takes precedence: override only this test handler through a private copy.
mkdir -p "$scratch/roles/host"
cp -R "$root/deploy/ansible/roles/host/tasks" "$root/deploy/ansible/roles/host/templates" "$scratch/roles/host/"
mkdir -p "$scratch/roles/host/handlers"
cat > "$scratch/roles/host/handlers/main.yml" <<'YAML'
- name: Reload cloudflared
  ansible.builtin.debug:
    msg: 'Reload observed in isolated test'
YAML
printf '{"ratatoskr_cloudflared_config":"%s","ratatoskr_sites_hostnames":["garden.example.test"]}\n' "$scratch/config.yml" > "$scratch/vars.json"
ANSIBLE_ROLES_PATH="$scratch/roles" ansible-playbook -i localhost, "$scratch/test.yml" -e "@$scratch/vars.json" > "$scratch/first.log"
rg -q 'Reload observed' "$scratch/first.log"
cloudflared tunnel --config "$scratch/config.yml" ingress validate
ANSIBLE_ROLES_PATH="$scratch/roles" ansible-playbook -i localhost, "$scratch/test.yml" -e "@$scratch/vars.json" > "$scratch/second.log"
rg -q 'changed=0 .*failed=0' "$scratch/second.log"
! rg -q 'Reload observed' "$scratch/second.log"
printf '  # unmanaged http://127.0.0.1:8183\n' >> "$scratch/config.yml"
if ANSIBLE_ROLES_PATH="$scratch/roles" ansible-playbook -i localhost, "$scratch/test.yml" -e "@$scratch/vars.json" > "$scratch/refused.log" 2>&1; then
  printf 'FAIL: unmanaged gateway route was accepted\n' >&2; exit 1
fi
rg -q 'no gateway route outside' "$scratch/refused.log"
printf 'site ingress converge, validation, idempotence, reload and refusal: PASS\n'
