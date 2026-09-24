#!/usr/bin/env bash
# Print, for every operator package used by this repo, the channels offered by the
# target cluster's catalog and the currentCSV of each channel. Use the output to
# fill `channel` / `starting_csv` in group_vars/all/main.yml (see AGENTS.md §3).
#
# Usage:
#   KUBECONFIG=~/.kube/demo.kubeconfig scripts/resolve-operator-versions.sh
#   scripts/resolve-operator-versions.sh rhods-operator:redhat-operators nfd:redhat-operators
#
# Each argument is <package>:<catalog source>. The catalog is mandatory because
# some packages (authorino-operator, dns-operator) exist in more than one catalog
# and `oc get packagemanifest <name>` would return an arbitrary one.
#
# Set SHOW_ENTRIES=1 to also list every CSV available in each channel.
set -euo pipefail

MARKETPLACE_NS="${MARKETPLACE_NS:-openshift-marketplace}"
SHOW_ENTRIES="${SHOW_ENTRIES:-0}"

DEFAULT_PACKAGES=(
  openshift-gitops-operator:redhat-operators
  openshift-cert-manager-operator:redhat-operators
  openshift-external-secrets-operator:redhat-operators
  rhcl-operator:redhat-operators
  authorino-operator:redhat-operators
  limitador-operator:redhat-operators
  dns-operator:redhat-operators
  rhods-operator:redhat-operators
  nfd:redhat-operators
  gpu-operator-certified:certified-operators
  servicemeshoperator3:redhat-operators
  serverless-operator:redhat-operators
)

command -v oc >/dev/null 2>&1 || { echo "ERROR: oc not found in PATH" >&2; exit 2; }
oc whoami >/dev/null 2>&1 || { echo "ERROR: not logged in (set KUBECONFIG or run oc login)" >&2; exit 2; }

if [[ $# -gt 0 ]]; then
  packages=("$@")
else
  packages=("${DEFAULT_PACKAGES[@]}")
fi

ocp_version="$(oc get clusterversion version -o jsonpath='{.status.desired.version}')"
echo "# cluster: $(oc whoami --show-server)"
echo "# OCP version: ${ocp_version}"
echo "# resolved on: $(date -u +%Y-%m-%d)"
echo

missing=0
for spec in "${packages[@]}"; do
  pkg="${spec%%:*}"
  catalog="${spec#*:}"
  if [[ "${pkg}" == "${spec}" || -z "${catalog}" ]]; then
    echo "ERROR: '${spec}' must be <package>:<catalog>" >&2
    exit 2
  fi

  # Select by catalog label, then by name: guarantees the package from the right catalog.
  sel="{range .items[?(@.metadata.name==\"${pkg}\")]}"
  default_channel="$(oc get packagemanifests -n "${MARKETPLACE_NS}" -l "catalog=${catalog}" \
    -o jsonpath="${sel}{.status.defaultChannel}{end}")"
  if [[ -z "${default_channel}" ]]; then
    echo "## ${pkg} (${catalog}): NOT FOUND"
    echo
    missing=1
    continue
  fi

  echo "## ${pkg} (catalog: ${catalog}, default channel: ${default_channel})"
  printf '%-32s %s\n' "CHANNEL" "CURRENT_CSV"
  oc get packagemanifests -n "${MARKETPLACE_NS}" -l "catalog=${catalog}" \
    -o jsonpath="${sel}{range .status.channels[*]}{.name}{\"\t\"}{.currentCSV}{\"\n\"}{end}{end}" \
    | sort -V | while IFS=$'\t' read -r channel csv; do
        printf '%-32s %s\n' "${channel}" "${csv}"
      done

  if [[ "${SHOW_ENTRIES}" == "1" ]]; then
    oc get packagemanifests -n "${MARKETPLACE_NS}" -l "catalog=${catalog}" \
      -o jsonpath="${sel}{range .status.channels[*]}{\"  entries[\"}{.name}{\"]: \"}{.entries[*].name}{\"\n\"}{end}{end}"
  fi
  echo
done

exit "${missing}"
