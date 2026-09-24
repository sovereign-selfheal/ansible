# ansible: Day 0/1 bootstrap

Bootstrap for the demo *The Sovereign, Self-Healing Platform*: installs the OpenShift operators,
prepares cluster prerequisites and seeds a single Argo CD `Application` pointing at the `gitops` repo.
Read [`AGENTS.md`](AGENTS.md) before changing anything.

| Stage | Playbook | Status |
|---|---|---|
| Preflight (reachability, OCP 4.22, default StorageClass, catalogs, external GPU nodes) | `playbooks/00-preflight.yml` | done |
| Operators (OLM, pinned CSV, Manual approval) | `playbooks/10-operators.yml` | done |
| Cluster prerequisites: inference Gateway and Route ([`roles/ingress_gateway`](roles/ingress_gateway/README.md)), GPU MachineSets ([`roles/gpu_node_prep`](roles/gpu_node_prep/README.md)) | `playbooks/20-prereqs.yml` | done |
| GitOps seed: namespaces, Argo CD health checks, root Application ([`roles/argocd_seed`](roles/argocd_seed/README.md)) | `playbooks/30-gitops-seed.yml` | done |
| Teardown | `playbooks/99-destroy.yml` | todo |

## Operators

Declared in `group_vars/all/main.yml` (`operators`) and installed in this order by
[`roles/olm_operator`](roles/olm_operator/README.md):

| Key (tag) | Package | Catalog | Namespace | Channel | Pinned CSV | Enabled |
|---|---|---|---|---|---|---|
| `openshift_gitops` | openshift-gitops-operator | redhat-operators | openshift-gitops-operator | gitops-1.21 | openshift-gitops-operator.v1.21.4 | yes |
| `cert_manager` | openshift-cert-manager-operator | redhat-operators | cert-manager-operator | stable-v1.20 | cert-manager-operator.v1.20.0 | yes |
| `external_secrets` | openshift-external-secrets-operator | redhat-operators | external-secrets-operator | stable-v1.2 | openshift-external-secrets-operator.v1.2.1 | yes |
| `rhcl` | rhcl-operator (+ authorino, limitador, dns) | redhat-operators | openshift-operators | stable | rhcl-operator.v1.4.3 | yes |
| `authorino` | authorino-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | authorino-operator.v1.4.3 | yes |
| `limitador` | limitador-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | limitador-operator.v1.4.2 | yes |
| `dns_operator` | dns-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | dns-operator.v1.4.2 | yes |
| `rhoai` | rhods-operator | redhat-operators | redhat-ods-operator | stable-3.5 | rhods-operator.3.5.1 | yes |
| `nfd` | nfd | redhat-operators | openshift-nfd | stable | nfd.4.22.0-202609151747 | `gpu_enabled` |
| `gpu_operator` | gpu-operator-certified | certified-operators | nvidia-gpu-operator | v26.7 | gpu-operator-certified.v26.7.0 | `gpu_enabled` |
| `servicemesh` | servicemeshoperator3 | redhat-operators | openshift-operators | stable-3.4 | servicemeshoperator3.v3.4.2 | no |
| `serverless` | serverless-operator | redhat-operators | openshift-serverless | stable-1.37 | serverless-operator.v1.37.1 | no |

Pins were resolved on OCP 4.22.14 on 2026-09-23. To refresh them against a cluster:

```bash
scripts/resolve-operator-versions.sh                 # all packages used here
SHOW_ENTRIES=1 scripts/resolve-operator-versions.sh rhods-operator:redhat-operators
```

## Prerequisites

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

The kubernetes.core modules read the cluster credentials from `$KUBECONFIG`, or from `K8S_AUTH_*`
environment variables. The user needs `cluster-admin`.

```bash
export KUBECONFIG=~/.kube/demo.kubeconfig
# or: oc login --token=<token> --server=https://api.<cluster>:6443
```

## Run

```bash
# dry run: shows diffs, skips approvals and waits
ansible-playbook playbooks/site.yml --check --diff

# full bootstrap: preflight, operators, prerequisites, GitOps seed.
# The SOTA endpoint is not secret but stays out of tracked files: -e, or group_vars/all/vault.yml
ansible-playbook playbooks/site.yml -e sota_api_base=https://<provider>/v1 -e sota_model=openai/<model>

# a single operator
ansible-playbook playbooks/10-operators.yml --tags rhoai

# with GPU: operators first, then the GPU MachineSets (one run, in this order; SOTA values as above)
ansible-playbook playbooks/site.yml -e gpu_enabled=true

# end of the day: scale the GPU MachineSets to 0 (only stage 20, faster)
ansible-playbook playbooks/20-prereqs.yml -e gpu_enabled=true -e gpu_node_prep_replicas=0
```

A second run must report `changed=0`:

```
PLAY RECAP *********************************************************************
localhost                  : ok=...  changed=0    unreachable=0    failed=0    skipped=...
```

The last task prints the pinned CSV of each operator. It also lists any **unapproved** InstallPlan
that OLM created for a newer version. These plans are never approved automatically. To upgrade,
change `channel`/`starting_csv` in `group_vars/all/main.yml` and run the playbook again.

## Lint (also run by CI on every PR)

```bash
yamllint .
ansible-lint
ansible-playbook playbooks/site.yml --syntax-check
shellcheck scripts/*.sh
```

## Layout notes

- `inventory/group_vars` is a symlink to the repo-root `group_vars/`, so the variables are loaded
  for `inventory/localhost.yml` while keeping the layout described in AGENTS.md.
- RHDP clusters already have OpenShift GitOps and cert-manager installed, with Automatic approval.
  The role keeps their OperatorGroups and updates their Subscriptions to the numbered channel,
  Manual approval and the pinned CSV. The operators are not reinstalled.

## License

Apache License 2.0, see [LICENSE](LICENSE).
