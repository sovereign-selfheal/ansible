#!/usr/bin/env bash
# Copy the TriageAgent CRD from the triage-agent-operator repo into this role.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
src="${1:-$(cd "$root/.." && pwd)/triage-agent-operator/deploy/crd.yaml}"
dst="${root}/roles/triage_agent_operator/files/crd.yaml"
if [[ ! -f "$src" ]]; then
  echo "CRD not found: $src" >&2
  echo "Usage: $0 [path/to/triage-agent-operator/deploy/crd.yaml]" >&2
  exit 1
fi
cp "$src" "$dst"
# ansible-lint expects a YAML document start on cluster manifests checked into this repo.
if ! head -1 "$dst" | grep -q '^---'; then
  { echo '---'; cat "$dst"; } > "${dst}.tmp" && mv "${dst}.tmp" "$dst"
fi
echo "Updated $dst from $src"
