# ansible: Day 0/1 bootstrap

Bootstrap for the demo *The Sovereign, Self-Healing Platform*: installs the OpenShift operators,
prepares cluster prerequisites and seeds a single Argo CD `Application` pointing at the `gitops` repo.
Read [`AGENTS.md`](AGENTS.md) before changing anything.

| Stage | Playbook | Status |
|---|---|---|
| Preflight (reachability, OCP 4.22, default StorageClass, catalogs, external GPU nodes) | `playbooks/00-preflight.yml` | done |
| Operators (OLM, pinned CSV, Manual approval) | `playbooks/10-operators.yml` | done |
| Cluster prerequisites: inference Gateway and Route ([`roles/ingress_gateway`](roles/ingress_gateway/README.md)), secret values for ESO ([`roles/secrets_bootstrap`](roles/secrets_bootstrap/README.md)), GPU MachineSets ([`roles/gpu_node_prep`](roles/gpu_node_prep/README.md)) | `playbooks/20-prereqs.yml` | done |
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

## SOTA model and ansible-vault

The router sends each request to the **local model** or to an external **"SOTA" model**
(OpenAI compatible). The SOTA settings are not in git: they come from `group_vars/all/vault.yml`,
a file encrypted with ansible-vault that stays on your machine (on RHDP, AgnosticV passes the same
variables as extra vars).

| Variable | Meaning |
|---|---|
| `sota_api_base` | Endpoint, e.g. `https://<provider>/v1` |
| `sota_model` | LiteLLM model string, e.g. `openai/<model-id>` |
| `sota_served_match` | Part of the served model id, used by the cost gate |
| `sota_api_key` | API key (secret) |
| `sota_reasoning` | `false` (default in `main.yml`): the SOTA model answers without reasoning; `true`: the model decides |

- **Hybrid routing**: set all of `sota_api_base`, `sota_model`, `sota_api_key`. The key lands in the
  cluster through the External Secrets Operator ([`roles/secrets_bootstrap`](roles/secrets_bootstrap/README.md)).
- **Local-only mode**: set none of them (no vault file). Every request goes to the local model; the
  router logs still show `routed_to: sota-smart` when a gate chooses "SOTA", but the local model serves it.
- Only some of them set: the play stops with an error.
- **Privacy classifier**: `classifier_mode` (`group_vars/all/main.yml`) is `local` by default: the local
  model classifies the gray-zone prompts, so they never leave the cluster. `external` uses a classifier
  set in the vault (`classifier_base_url`, `classifier_model`, `classifier_api_key`); `off` turns it off.

Create the vault once:

```bash
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
ansible-vault encrypt group_vars/all/vault.yml
ansible-vault edit group_vars/all/vault.yml
```

Then run the playbooks with `scripts/run-playbook.sh` (from the repo root). It adds the vault password
file when it finds one, in this order:

1. `$ANSIBLE_VAULT_PASSWORD_FILE`, if set;
2. `~/.config/sovereign-selfheal/vault-pass` (recommended: outside the repo, `chmod 600`);
3. `.vault-pass` in the repo root (ignored by git).

With a vault but no password file, it asks for the password. Without a vault, it runs in local-only
mode. Keep the password file out of the repo when you can: `.gitignore` is only a safety net.

```bash
mkdir -p ~/.config/sovereign-selfheal
( umask 077; read -rs -p 'Vault password: ' p && printf '%s\n' "$p" > ~/.config/sovereign-selfheal/vault-pass )
scripts/run-playbook.sh playbooks/site.yml
```

## Run

```bash
# dry run: shows diffs, skips approvals and waits
ansible-playbook playbooks/site.yml --check --diff

# full bootstrap: preflight, operators, prerequisites, GitOps seed
scripts/run-playbook.sh playbooks/site.yml   # hybrid routing with a vault, local-only mode without

# a single operator
ansible-playbook playbooks/10-operators.yml --tags rhoai

# with GPU: operators first, then the GPU MachineSets (one run, in this order)
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
