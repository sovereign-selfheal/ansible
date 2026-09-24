#!/usr/bin/env bash
# Run ansible-playbook with the vault password file, if there is one.
#
# Usage: scripts/run-playbook.sh <playbook> [ansible-playbook options]
#   scripts/run-playbook.sh playbooks/site.yml
#   scripts/run-playbook.sh playbooks/site.yml -e gpu_enabled=true
#
# The vault (group_vars/all/vault.yml) holds the SOTA settings. The password file is
# looked up in this order:
#   1. $ANSIBLE_VAULT_PASSWORD_FILE (if set)
#   2. ~/.config/sovereign-selfheal/vault-pass
#   3. <repo>/.vault-pass   (ignored by git)
# - vault and password file found: the password file is used;
# - vault found, no password file: ansible-playbook asks for the password;
# - no vault: the playbook runs in local-only mode (no SOTA model).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <playbook> [ansible-playbook options]" >&2
  exit 2
fi

repo="$(cd "$(dirname "$0")/.." && pwd)"
vault="${repo}/group_vars/all/vault.yml"
candidates=(
  "${ANSIBLE_VAULT_PASSWORD_FILE:-}"
  "${HOME}/.config/sovereign-selfheal/vault-pass"
  "${repo}/.vault-pass"
)

args=()
if [[ -f "${vault}" ]]; then
  password_file=""
  for candidate in "${candidates[@]}"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      password_file="${candidate}"
      break
    fi
  done
  if [[ -n "${password_file}" ]]; then
    # The password file must be readable only by its owner.
    if [[ -n "$(find "${password_file}" -perm /077 2>/dev/null)" ]]; then
      echo "WARNING: ${password_file} is readable by other users; run: chmod 600 ${password_file}" >&2
    fi
    echo "Vault found: using the password file ${password_file}" >&2
    args+=(--vault-password-file "${password_file}")
  else
    echo "Vault found but no password file: ansible-playbook will ask for the password" >&2
    args+=(--ask-vault-pass)
  fi
else
  echo "No vault (${vault}): local-only mode, no SOTA model" >&2
fi

# ANSIBLE_VAULT_PASSWORD_FILE is already handled above; unset it so that ansible-playbook
# does not fail when it points to a missing file.
unset ANSIBLE_VAULT_PASSWORD_FILE
cd "${repo}"
exec ansible-playbook "${args[@]}" "$@"
