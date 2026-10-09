#!/usr/bin/env bash
# Copy the TriageAgent CRD from the triage-agent-operator repo into this role.
#
# Usage: scripts/sync-triage-agent-operator-crd.sh [path/to/triage-agent-operator/deploy/crd.yaml]
#   Default source: ../triage-agent-operator/deploy/crd.yaml (clone next to this repo).
#
# The copy is the upstream file without its leading comment block, with a YAML document start
# (ansible-lint) and a short header of this repo. Running the script twice gives the same file.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-$(cd "$root/.." && pwd)/triage-agent-operator/deploy/crd.yaml}"
dst="${root}/roles/triage_agent_operator/files/crd.yaml"
if [[ ! -f "$src" ]]; then
  echo "CRD not found: $src" >&2
  echo "Usage: $0 [path/to/triage-agent-operator/deploy/crd.yaml]" >&2
  exit 1
fi
{
  echo '---'
  echo '# Copy of triage-agent-operator/deploy/crd.yaml. Do not edit by hand: change the CRD in the'
  echo '# operator repo, then run scripts/sync-triage-agent-operator-crd.sh.'
  # Drop the leading comment lines and document start of the upstream file, keep the rest as is.
  awk 'body || !/^(#|---[[:space:]]*$)/ { body = 1; print }' "$src"
} > "${dst}.tmp"
mv "${dst}.tmp" "$dst"
echo "Updated $dst from $src"
