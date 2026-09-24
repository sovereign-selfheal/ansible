# AGENTS.md — `ansible` repository

Guidance for AI coding agents (Claude Code, Codex, Cursor, etc.) and humans working in this repo.
Read this file fully before making changes.

## 1. Purpose

This repository contains the **Day 0 / Day 1 bootstrap** for the demo
*"The Sovereign, Self-Healing Platform — Smart LLM Routing & Autonomous AI-Driven Triage on OpenShift AI"*.

It does exactly three things, in order:

1. Installs and configures the required **OpenShift operators** via OLM.
2. Prepares **cluster prerequisites** that GitOps cannot handle (GPU node setup, secrets bootstrap, external SOTA API keys, storage checks).
3. Applies a **single Argo CD `Application`** that points to the `gitops` repository. From that point on, Argo CD owns every workload.

**Rule of thumb agreed with the team:**
if it is a Kubernetes manifest for a workload → it lives in `gitops`;
if it is an imperative action or a cluster prerequisite → it lives here.
Never deploy the same object from both places.

Target platform: **demo.redhat.com** (RHDP). The code must be structured so that it can be wrapped as an
[AgnosticD](https://github.com/redhat-cop/agnosticd) workload role with minimal changes (see §6).

## 2. Repository layout

```
.
├── AGENTS.md
├── README.md
├── ansible.cfg
├── requirements.yml            # collections (kubernetes.core, community.general)
├── inventory/
│   └── localhost.yml           # runs from a bastion/laptop against the cluster API, no SSH
├── group_vars/
│   └── all/
│       ├── main.yml            # non-secret defaults
│       └── vault.yml           # ansible-vault, never in clear text
├── playbooks/
│   ├── site.yml                # full bootstrap, calls the others in order
│   ├── 00-preflight.yml        # cluster reachability, version, node/GPU checks
│   ├── 10-operators.yml        # OLM subscriptions
│   ├── 20-prereqs.yml          # GPU MachineSets (after the operators), secrets, namespaces owned by Ansible
│   ├── 30-gitops-seed.yml      # Argo CD Application → gitops repo
│   └── 99-destroy.yml          # optional teardown, symmetric to site.yml
├── roles/
│   ├── ocp_preflight/
│   ├── olm_operator/           # generic, reusable: one role, N operators via vars
│   ├── gpu_node_prep/
│   ├── secrets_bootstrap/
│   └── argocd_seed/
├── scripts/
│   └── resolve-operator-versions.sh   # prints package/channel/currentCSV on the target cluster
└── tests/
    └── ...                     # ansible-lint config, molecule (optional)
```

Do **not** add per-operator roles (`rhoai/`, `rhcl/`…). Use the generic `olm_operator` role and describe operators as data in `group_vars/all/main.yml` (see §3).

## 3. Operators to install

Operators are declared as a list and installed by `roles/olm_operator` in a loop.

**Version pinning policy (mandatory):**

- Every operator is pinned to an explicit `startingCSV` in `group_vars/all/main.yml`.
- Every `Subscription` uses `installPlanApproval: Manual`. The role approves **only** the `InstallPlan` that contains the pinned CSV; nothing else is ever approved. Once installed, the operator must not change version unless a human updates the pin in `group_vars` and re-runs the playbook.
- The pinned CSVs must be **discovered on the target OCP version (4.22)**, never guessed. Use `scripts/resolve-operator-versions.sh` (or the equivalent `oc` commands below) against a real 4.22 cluster and record the result, with the date, next to the pin:

```bash
oc get packagemanifests -n openshift-marketplace <package> \
  -o jsonpath='{range .status.channels[*]}{.name}{"\t"}{.currentCSV}{"\n"}{end}'
```

| Key | Operator | Package | Namespace | Channel | Notes |
|-----|----------|---------|-----------|---------|-------|
| `openshift_gitops` | Red Hat OpenShift GitOps | `openshift-gitops-operator` | `openshift-gitops-operator` | `gitops-1.21` | Installed **first**; Argo CD is used by everything downstream. Pre-installed by RHDP (`latest`, Automatic): the role adopts it (`allow_newer_installed: true`) |
| `cert_manager` | cert-manager Operator for Red Hat OpenShift | `openshift-cert-manager-operator` | `cert-manager-operator` | `stable-v1.20` | Prerequisite of RHOAI 3.x KServe. Pre-installed by RHDP: adopted (`allow_newer_installed: true`) |
| `rhcl` | Red Hat Connectivity Link (Kuadrant) | `rhcl-operator` | `openshift-operators` | `stable` (only channel) | Before RHOAI. Brings `authorino-operator`, `limitador-operator`, `dns-operator` as OLM dependencies (pinned in `expected_dependency_csvs`). Post-install: GatewayClass, `Kuadrant` in `kuadrant-system`, Authorino TLS. The LLM gateway and its policies are deployed by GitOps |
| `authorino` / `limitador` / `dns_operator` | RHCL dependencies | `authorino-operator` / `limitador-operator` / `dns-operator` | `openshift-operators` | `stable` | OLM creates their Subscriptions while it installs `rhcl` (Automatic). These entries adopt them by name (`subscription_name`) and set Manual approval + pinned startingCSV |
| `rhoai` | Red Hat OpenShift AI | `rhods-operator` | `redhat-ods-operator` | `stable-3.5` | Creates `DataScienceCluster` (v2) with KServe; model serving (vLLM) itself is deployed by GitOps |
| `nfd` | Node Feature Discovery | `nfd` | `openshift-nfd` | `stable` (only channel, tracks the OCP minor) | Only when `gpu_enabled: true`; required by the GPU operator. OwnNamespace OperatorGroup. Installed before the GPU nodes exist (see §3 "GPU nodes") |
| `gpu_operator` | NVIDIA GPU Operator | `gpu-operator-certified` (catalog `certified-operators`) | `nvidia-gpu-operator` | `v26.7` | Only when `gpu_enabled: true`; needed by in-cluster vLLM. OwnNamespace OperatorGroup |
| `servicemesh` / `serverless` | OSSM / OpenShift Serverless | `servicemeshoperator3` / `serverless-operator` | `openshift-operators` / `openshift-serverless` | `stable-3.4` / `stable-1.37` | Disabled: RHOAI 3.5 KServe is RawDeployment-only and needs neither |

Verified on OCP 4.22.14 on 2026-09-23; pinned CSVs are in `group_vars/all/main.yml`.

Package names and channels above are the expected ones; **verify each one on the 4.22 cluster** and correct the table and `group_vars` if they differ. Prefer numbered channels wherever the catalog offers them: combined with Manual approval and `startingCSV` this freezes the version completely.

Each entry has the shape below (full field reference: `roles/olm_operator/README.md`):

```yaml
operators:
  - key: rhcl                          # tag: --tags rhcl
    name: rhcl-operator                # package name
    namespace: openshift-operators
    manage_namespace: false            # never manage openshift-operators
    channel: stable                    # numbered channel when the catalog has one
    starting_csv: rhcl-operator.v1.4.3 # resolved on OCP 4.22.14 on 2026-09-23
    expected_dependency_csvs:          # other CSVs allowed in the same InstallPlan, also pinned
      - authorino-operator.v1.4.3      # resolved on OCP 4.22.14 on 2026-09-23
    source: redhat-operators
    source_namespace: openshift-marketplace
    install_plan_approval: Manual      # always Manual, see pinning policy
    create_operator_group: false       # true: create one if the namespace has none
    operator_group_all_namespaces: true
    enabled: true
    pre_install:                       # optional: applied before the Subscription
      - template: gatewayclass.yaml.j2
        vars: {name: "{{ gateway_class_name }}", controller_name: "{{ gateway_class_controller }}"}
        wait:
          api_version: gateway.networking.k8s.io/v1
          kind: GatewayClass
          name: "{{ gateway_class_name }}"
          condition: {type: Accepted, status: "True"}
    post_install:                      # optional: applied after the CSV is Succeeded
      - template: kuadrant.yaml.j2     # file in roles/olm_operator/templates
        vars: {namespace: "{{ kuadrant_namespace }}"}
        wait:                          # condition, or status_field + value
          api_version: kuadrant.io/v1beta1
          kind: Kuadrant
          name: kuadrant
          namespace: "{{ kuadrant_namespace }}"
          condition: {type: Ready, status: "True"}
```

The `olm_operator` role must, for every entry:

1. Create the `Namespace` (with `openshift.io/cluster-monitoring: "true"` where appropriate).
2. Create the `OperatorGroup` if requested, or reuse the one already in the namespace (never create a second one). Then apply the `pre_install` items, if any.
3. Create the `Subscription` with `startingCSV: {{ starting_csv }}` and `installPlanApproval: Manual`.
4. **Wait** for the `InstallPlan` referenced by `subscription.status.installplan` to appear, verify that `spec.clusterServiceVersionNames` contains the pinned CSV and nothing else except the CSVs listed in the entry's `expected_dependency_csvs` (OLM dependencies resolved into the same plan, themselves pinned), then patch `spec.approved: true`. If the InstallPlan proposes any other CSV, **fail** the play with a clear message — never approve it.
5. **Wait** until the `ClusterServiceVersion` `{{ starting_csv }}` phase is `Succeeded` (retry/until, sensible timeout ≥ 15 min for RHOAI and GPU operator).
6. Apply `post_install` CRs and wait for their readiness condition.

On re-runs the role must detect that the pinned CSV is already `Succeeded` and skip steps 4–5 without changes (idempotent); step 3 is re-applied but is a no-op unless the Subscription drifted (this is also how pre-existing RHDP Subscriptions are adopted). Pending InstallPlans for newer versions, if OLM creates them, are left unapproved and reported in a final `debug` summary.

**GPU nodes (`gpu_nodes_managed`).** The operators are installed first (stage 10), then the GPU
MachineSets (stage 20, `roles/gpu_node_prep`). This order works because the NVIDIA `ClusterPolicy`
is `ready` also when the cluster has no GPU nodes (verified on OCP 4.22.14 with GPU operator v26.7.0).
Stage 20 then waits until each GPU node exposes `nvidia.com/gpu`. With `gpu_nodes_managed: false`
the GPU nodes come from outside (for example an RHDP catalog item with GPUs): stage 20 does not
create them and the preflight fails if there are none.

**Operators pre-installed by the platform (`allow_newer_installed`).** RHDP clusters already have some
operators (today: OpenShift GitOps and cert-manager) installed from the default channel, often `latest`,
with Automatic approval. The version found on a new RHDP cluster cannot be known in advance and OLM cannot
downgrade. For these entries only, `allow_newer_installed: true` tells the role:

- if the installed CSV is **newer** than the pin, keep it: set only `installPlanApproval: Manual` on the
  existing Subscription (channel and startingCSV are not changed), so the version is frozen from that
  moment, and report it in the summary;
- if the installed CSV is **older** than the pin, or the operator is missing, apply the normal pinning flow.

Without the flag, a newer installed CSV stops the play **before** the Subscription is changed. Do not set
the flag on operators that this repo installs itself (RHCL, RHOAI, NFD, GPU operator).

## 4. Conventions

- **Idempotency is mandatory.** Every playbook must be re-runnable with zero changes on the second run. Use `kubernetes.core.k8s` with `state: present` and `kubernetes.core.k8s_info` + `until` for waits. No `oc apply` via `shell` unless there is no module equivalent; if you must, add `changed_when`.
- **No cluster-specific values in tasks.** Everything tunable goes to `group_vars/all/main.yml` or is passed with `-e`. Roles expose their variables in `defaults/main.yml`, documented in `README.md` of the role.
- **Secrets**: only in `group_vars/all/vault.yml` (ansible-vault) or injected at runtime with `-e`/env vars. Never commit clear-text tokens, kubeconfigs, API keys. `.gitignore` already excludes `*.kubeconfig`, `.vault-password`, `*.pem`.
- **Naming**: roles and variables in `snake_case`; playbooks prefixed with two digits for ordering; tags equal to the role name (`--tags rhoai`).
- **Fully qualified collection names** (`kubernetes.core.k8s`, not `k8s`).
- **Waits, not sleeps.** `pause` is forbidden; poll a condition.
- **Logging**: every role starts with a `debug` line stating what it is about to do and the key variables (except secrets).
- **OpenShift version target**: **4.22** (`ocp_min_version: "4.22"` in preflight; the preflight fails on anything else, since operator pins are validated only for 4.22).
- Comments and commit messages in **English**.

## 5. How to run

```bash
# prerequisites
pip install -r requirements.txt          # ansible-core, kubernetes, openshift, ansible-lint
ansible-galaxy collection install -r requirements.yml

# authenticate against the target cluster (one of)
export KUBECONFIG=~/.kube/demo.kubeconfig
# or
oc login --token=... --server=https://api.<cluster>:6443

# full bootstrap
ansible-playbook playbooks/site.yml -e @group_vars/all/vault.yml --ask-vault-pass

# single stage / operator
ansible-playbook playbooks/10-operators.yml --tags rhoai

# dry run
ansible-playbook playbooks/site.yml --check --diff
```

Before opening a PR:

```bash
ansible-lint
yamllint .
ansible-playbook playbooks/site.yml --syntax-check
```

CI (GitHub Actions) runs `ansible-lint` + `yamllint` on every PR; a failing lint blocks the merge.

## 6. AgnosticD compatibility

The playbooks must stay portable to an AgnosticD workload role:

- Keep the entry point role-based; `playbooks/*.yml` are thin wrappers that only `include_role`.
- All variables must be overridable from the outside (AgnosticV passes them as extra vars).
- Do not rely on local files outside the repo, interactive prompts, or the operator's laptop state.
- Provide a `remove` path (`99-destroy.yml`) that mirrors the install order in reverse.

## 7. Out of scope for this repo

Do **not** add here:

- vLLM `InferenceService`/`ServingRuntime`, Presidio, Kuadrant `AuthPolicy`/`RateLimitPolicy`, the LLM router, the SRE agents, the sample app, dashboards → `gitops` repo.
- Application source code and container builds → `router`, `agents`, `sample-app` repos.
- Demo narrative/lab guide → `showroom` repo.

If a task seems to require adding a workload manifest here, stop and explain why it cannot live in `gitops` instead of adding it.

## 8. When in doubt

- Prefer the smallest change that keeps the second run idempotent.
- Do not invent operator channels, package names or CSV versions: resolve them on a real OCP 4.22 cluster (`scripts/resolve-operator-versions.sh`) and put the verified value in `group_vars` with the resolution date in a comment.
- Ask before changing a pinned CSV, switching any subscription away from Manual, changing install order, setting `allow_newer_installed` on a new entry, or touching anything under `vault.yml`.
