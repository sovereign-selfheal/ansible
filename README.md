# ansible: Day 0/1 bootstrap

Bootstrap for the demo *The Sovereign, Self-Healing Platform*: installs the OpenShift operators,
prepares cluster prerequisites and seeds a single Argo CD `Application` pointing at the `gitops` repo.
Read [`AGENTS.md`](AGENTS.md) before changing anything.

| Stage | Playbook | Status |
|---|---|---|
| Preflight (reachability, OCP 4.22, default StorageClass, catalogs, resolved pins, GPU instance type or external GPU nodes (Blackwell, about 96 GB), team users) | `playbooks/00-preflight.yml` | done |
| Early nodes: GPU MachineSets without waiting ([`roles/gpu_node_prep`](roles/gpu_node_prep/README.md)), pre-pull of the model images ([`roles/model_prepull`](roles/model_prepull/README.md)) | `playbooks/05-early-nodes.yml` | done |
| Operators (OLM, pinned CSV, Manual approval) | `playbooks/10-operators.yml` | done |
| Team access, only with `team_users` in the vault: Keycloak users, OpenShift Group, cluster role ([`roles/team_access`](roles/team_access/README.md)) | `playbooks/15-identity.yml` | new, see [Team access](#team-access) |
| Cluster prerequisites: inference Gateway and Route ([`roles/ingress_gateway`](roles/ingress_gateway/README.md)), secret values for ESO ([`roles/secrets_bootstrap`](roles/secrets_bootstrap/README.md)), user workload monitoring ([`roles/user_workload_monitoring`](roles/user_workload_monitoring/README.md)), wait for the GPU nodes ([`roles/gpu_node_prep`](roles/gpu_node_prep/README.md)) | `playbooks/20-prereqs.yml` | done |
| GitOps seed: namespaces, Argo CD health checks, root Application ([`roles/argocd_seed`](roles/argocd_seed/README.md)), Kuadrant wasm module on every gateway pod ([`roles/ingress_gateway`](roles/ingress_gateway/README.md#after-the-seed-kuadrant-wasm-module)), console links to the traces ([`roles/console_links`](roles/console_links/README.md)) | `playbooks/30-gitops-seed.yml` | done |
| Teardown | `playbooks/99-destroy.yml` | todo |

## Operators

Declared in `group_vars/all/main.yml` (`operators`) and installed in this order by
[`roles/olm_operator`](roles/olm_operator/README.md):

| Key (tag) | Package | Catalog | Namespace | Channel | Pinned CSV | Enabled |
|---|---|---|---|---|---|---|
| `openshift_gitops` | openshift-gitops-operator | redhat-operators | openshift-gitops-operator | gitops-1.21 | openshift-gitops-operator.v1.21.4 | yes |
| `cert_manager` | openshift-cert-manager-operator | redhat-operators | cert-manager-operator | stable-v1.20 | cert-manager-operator.v1.20.0 | yes |
| `external_secrets` | openshift-external-secrets-operator | redhat-operators | external-secrets-operator | stable-v1.2 | openshift-external-secrets-operator.v1.2.1 | yes |
| `rhbk` | rhbk-operator (Red Hat build of Keycloak; adopted on RHDP) | redhat-operators | keycloak | stable-v26.6 | rhbk-operator.v26.6.7-opr.1 | `team_access_enabled` |
| `rhcl` | rhcl-operator (+ authorino, limitador, dns) | redhat-operators | openshift-operators | stable | rhcl-operator.v1.4.3 | yes |
| `authorino` | authorino-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | authorino-operator.v1.4.3 | yes |
| `limitador` | limitador-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | limitador-operator.v1.4.2 | yes |
| `dns_operator` | dns-operator (RHCL dependency, adopted) | redhat-operators | openshift-operators | stable | dns-operator.v1.4.2 | yes |
| `rhoai` | rhods-operator | redhat-operators | redhat-ods-operator | stable-3.5 | rhods-operator.3.5.1 | yes |
| `nfd` | nfd | redhat-operators | openshift-nfd | stable | nfd.4.22.0-202609151747 | `gpu_enabled` |
| `gpu_operator` | gpu-operator-certified | certified-operators | nvidia-gpu-operator | v26.7 | gpu-operator-certified.v26.7.0 | `gpu_enabled` |
| `opentelemetry` | opentelemetry-product (Red Hat build of OpenTelemetry) | redhat-operators | openshift-opentelemetry-operator | stable | opentelemetry-operator.v0.158.0-2 | `observability_enabled` |
| `tempo` | tempo-product (Tempo Operator) | redhat-operators | openshift-tempo-operator | stable | tempo-operator.v0.22.0-2 | `observability_enabled` |
| `cluster_observability` | cluster-observability-operator (+ UIPlugin `distributed-tracing`) | redhat-operators | openshift-cluster-observability-operator | stable | cluster-observability-operator.v1.5.2 | `observability_enabled` |

Pins were resolved on OCP 4.22.14 on 2026-09-23; the three observability operators on 2026-09-26; rhbk on 2026-09-28. To refresh them against a cluster:

```bash
scripts/resolve-operator-versions.sh                 # all packages used here
SHOW_ENTRIES=1 scripts/resolve-operator-versions.sh rhods-operator:redhat-operators
```

## Prerequisites

The Python tools are managed with [uv](https://docs.astral.sh/uv/). `pyproject.toml` lists the
dependencies and `uv.lock` pins their exact versions (ansible-core 2.20, the Kubernetes client,
ansible-lint, yamllint).

```bash
uv sync                                                        # creates .venv from uv.lock
uv run ansible-galaxy collection install -r requirements.yml   # Ansible collections
```

Run every tool through uv (`uv run ansible-playbook …`, `uv run ansible-lint`) or use
`scripts/run-playbook.sh`, which uses `uv run` by itself. To update a dependency, change
`pyproject.toml` and run `uv lock`.

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

## Team access

RHDP gives one login, `admin`. To give each team member a personal login with cluster-admin rights
(OpenShift console and Argo CD UI), list the users in the vault. The usernames are not in git on
purpose: they stay in `group_vars/all/vault.yml` (or come from AgnosticV as extra vars).

```bash
ansible-vault edit group_vars/all/vault.yml
```

```yaml
team_users:
  - username: alice          # lowercase: letters, digits, dot, dash, underscore
    password: Initial-Pass-1 # initial password, changed at the first login
  - username: bob
    password: Initial-Pass-2
```

Then run the full bootstrap, or only this stage on a running cluster:

```bash
scripts/run-playbook.sh playbooks/site.yml
scripts/run-playbook.sh playbooks/15-identity.yml   # needs the rhbk operator (stage 10)
```

What happens ([`roles/team_access`](roles/team_access/README.md)):

1. **Keycloak.** On RHDP, Keycloak and its OpenShift identity provider `rhbk` (realm `sso`) already
   exist: the role reuses them. On other clusters, stage 10 installs the Red Hat build of Keycloak
   operator, and stage 15 creates PostgreSQL, the Keycloak instance (`https://sso.<apps domain>`),
   the realm `sso` (no self-registration), the client and the identity provider `rhbk`.
2. **Users.** Each user is created once in the realm, with the vault password as a **temporary**
   password. A rerun does not touch an existing user and does not reset the password.
3. **Permissions.** The OpenShift Group `selfheal-team` lists the usernames and is bound to
   `cluster-admin`. Stage 30 adds `g, selfheal-team, role:admin` to the Argo CD RBAC policy.

At the first login, choose **rhbk** on the login page, enter the username and the initial password,
then set a new password. Keycloak may also ask for an email and a name. Each new cluster starts from
the initial password again: share it with the person once, in a private channel.

Notes:

- **Remove a user:** delete the entry from the vault and run stage 15. The user leaves the Group (no
  more rights); the Keycloak account stays until you delete it in the Keycloak console.
- **Existing account with the same name:** the RHDP realm allows self-registration. If a listed
  username already exists and the role did not create it, the play stops: otherwise that account
  would become cluster-admin. Check it in the Keycloak console first.
- **Keycloak admin:** the role reads the master admin from the Secret `keycloak/keycloak-initial-admin`.
  If that password was changed, set `keycloak_admin_username` and `keycloak_admin_password` in the vault.
- An empty `team_users` (the default in `group_vars/all/main.yml`) turns everything off: no operator,
  no Keycloak, no Group.

## Run

```bash
# dry run: shows diffs, skips approvals and waits
scripts/run-playbook.sh playbooks/site.yml --check --diff

# full bootstrap: preflight, operators, team access, prerequisites, GitOps seed
scripts/run-playbook.sh playbooks/site.yml   # hybrid routing with a vault, local-only mode without

# a single operator
scripts/run-playbook.sh playbooks/10-operators.yml --tags rhoai

# the GPU profile is the default: operators first, then the GPU MachineSets (one run, in this order)
# CPU profile for quick tests (small model on CPU, no GPU node):
scripts/run-playbook.sh playbooks/site.yml -e gpu_enabled=false

# end of the day: scale the GPU MachineSets to 0 (only stage 20, faster)
scripts/run-playbook.sh playbooks/20-prereqs.yml -e gpu_node_prep_replicas=0
```

A second run must report `changed=0`:

```
PLAY RECAP *********************************************************************
localhost                  : ok=...  changed=0    unreachable=0    failed=0    skipped=...
```

The last task prints the pinned CSV of each operator. It also lists any **unapproved** InstallPlan
that OLM created for a newer version. These plans are never approved automatically. To upgrade,
change `channel`/`starting_csv` in `group_vars/all/main.yml` and run the playbook again.

## Model image pre-pull and GPU disk

On a new cluster the model pod used to pull its images only at the end: after the operators, the
GPU driver and the Argo CD sync, and one image after the other. Measured on 2026-09-26 with the
previous local model: modelcar (Granite, 16 GB) 12m12s, then vLLM CUDA 5m08s. The changes below
aim to shorten this; the gain on a new cluster is not measured yet (see the limits below):

- **The GPU node starts in parallel with the operators.** `05-early-nodes.yml` creates the GPU
  MachineSets without waiting, so AWS builds the node while `10-operators.yml` runs.
  `20-prereqs.yml` then waits for the node (Running, Ready, `nvidia.com/gpu`, ClusterPolicy
  `ready`): this is the sync point of the two. Since the node exists during stage 10, the
  ClusterPolicy wait of the GPU operator now includes the driver build (about 6-11 minutes,
  within its 1800 s timeout).
- **The model images are pulled early and in parallel.** `05-early-nodes.yml` also creates one
  DaemonSet per image (`roles/model_prepull`, namespace `sovereign-selfheal-prepull`). The pull
  starts as soon as the GPU node joins. Before the seed, `30-gitops-seed.yml` reports the pull
  (it does not wait: the model pod joins a pull in progress); after the seed it warns if the
  model uses other images than the pre-pulled ones.
- **Bigger GPU disk.** The GPU root disk is 200 GiB (was 100 GiB, 57% full after the first pull
  of Granite). With Qwen3.8 and vLLM the disk uses 69 of 214 GB after the first pull.
  This applies only to new Machines: scale the GPU MachineSet to 0 and back to 1 on an existing
  cluster (see [`roles/gpu_node_prep`](roles/gpu_node_prep/README.md)).

| Variable | Default | Meaning |
|---|---|---|
| `model_prepull_enabled` | `true` | Pre-pull the model images |
| `model_prepull_images` | current digests | Must match `localModel.profiles` in `gitops/bootstrap/values.yaml` |
| `gpu_node_prep_volume_size` | `200` | GPU root disk (GiB) |
| `gpu_node_prep_volume_iops` / `_throughput` | `""` | Empty = gp3 baseline (3000 IOPS, 125 MB/s) |

Limits, measured on 2026-09-29 with Qwen3.8 27B on a new `g7e.2xlarge` node (full `site.yml`
run, 34m42s; node joined at 04:30, model Ready at 04:57):

- The download itself does not get faster: the Qwen3.8 modelcar has one gzip layer of 19.5 GB
  (24.2 GB in all). The vLLM CUDA image took 7m53s and the modelcar 8m55s (after the restart
  below), both in parallel. With Granite (2026-09-26) the 16 GB layer alone took 12m12s.
- **The NVIDIA container toolkit restarts CRI-O** (`systemctl restart crio`) when the driver is
  ready, 9-11 minutes after the node joins. The restart stops every pull in progress, and the
  pull starts again from zero (the model layer is not resumed). A pull that has not finished
  before the restart gains nothing; the pre-pull then restarts at once, still before the seed.
  On 2026-09-29 the vLLM image had finished before the restart and was kept; the modelcar pull
  started again.
- The model pod uses the finished vLLM image (`already present on machine`). For the modelcar it
  started its own pull while the pre-pull was running; it finished about 3 minutes after the
  pre-pull (2026-09-29).
- After the pull, vLLM needs about 4 minutes to be Ready: weights 40 s, `torch.compile` 56 s,
  engine start (KV cache, CUDA graphs) 128 s.

To measure the effect, compare the `Pulling` -> `Pulled` events of the pre-pull pods and of the
model pod on a new cluster:

```bash
oc get events -n sovereign-selfheal-prepull --sort-by=.lastTimestamp | grep -E 'Pulling|Pulled'
oc get events -n local-models --sort-by=.lastTimestamp | grep -E 'Pulling|Pulled'
# with the pre-pull the model pod shows: Container image "..." already present on machine
```

## Observability (traces and metrics of the router)

The demo shows each routing decision as a trace (console: *Observe → Traces*) and as metrics
(*Observe → Metrics*). This repo prepares the cluster side; the gitops repo deploys the rest.

| Item | Where | Variable |
|---|---|---|
| Operators: Red Hat build of OpenTelemetry, Tempo Operator, Cluster Observability Operator | `group_vars/all/main.yml` (`operators`) | `observability_enabled` (default `true`) |
| Console plugin `UIPlugin/distributed-tracing` (cluster-scoped) | post-install of `cluster_observability` | `observability_enabled` |
| Perses dashboards in the console, `UIPlugin/monitoring` (cluster-scoped; the dashboard itself is in the gitops repo) | post-install of `cluster_observability` | `observability_enabled` |
| Tempo tenant write permission for the collector (ClusterRole + binding `tempo-traces-write-router`) | post-install of `tempo` | `observability_tempo_tenant`, `observability_collector_service_account` |
| Namespace `observability` (label `argocd.argoproj.io/managed-by`) | `roles/argocd_seed` | always created |
| Argo CD health check for `TempoMonolithic` | `roles/argocd_seed/files/health-tempo.lua` | always |
| User workload monitoring (`enableUserWorkload: true`) | `roles/user_workload_monitoring` | `user_workload_monitoring_enabled` (default `true`) |
| Metrics of Limitador and Authorino (PodMonitor `limitador`, ServiceMonitor `authorino` in `kuadrant-system`) | post-install of `rhcl` (`templates/kuadrant-monitors.yaml.j2`) | `kuadrant_metrics_enabled` (default `true`) |
| Label `tier` on the Limitador counters (`TelemetryPolicy` `openshift-ai-inference-labels` on the Gateway): tokens counted per API-key tier | `roles/ingress_gateway` | `ingress_gateway_metric_labels` (empty = no policy) |
| Console menu links to the router traces, already filtered (`ConsoleLink`, section *Sovereign Self-Healing demo*) | [`roles/console_links`](roles/console_links/README.md), stage 30 | `observability_enabled` |

The seed passes `observability.enabled` (from `observability_enabled`) and `namespaces.observability`
to the root Application. The gitops repo then deploys the Tempo instance `tempo` (TempoMonolithic) and
the OpenTelemetry collector `otel` (OTLP on `otel-collector.observability.svc:4318`) in the namespace
`observability`. Tempo runs with multi-tenancy in `openshift` mode (the supported setup on OpenShift):
the collector writes the tenant `router` with its service account token, and a user needs the read
permission on the tenant to see the traces (cluster-admin has it). Traces and metrics stay in the
cluster: nothing is sent outside.

**Workaround: the Kuadrant CR keeps `spec.observability` off.** On RHCL 1.4.3 (the latest version in the
`stable` channel on 2026-09-29) `observability.enable: true` also creates the PodMonitor
`openshift-ingress/istio-pod-monitor`. Its address regex is double-escaped, so Prometheus scrapes every
port of the gateway pods, also the status port 15021, which answers 404 on `/stats/prometheus`; the
monitor also finds pods in every namespace. `TargetDown` fires after 15 minutes (seen on ocp.bvdk2 on
2026-09-29). Upstream fixes: [kuadrant-operator PR #2147](https://github.com/Kuadrant/kuadrant-operator/pull/2147)
(regex, in v1.4.7 and v1.6.0) and [issue #1920](https://github.com/Kuadrant/kuadrant-operator/issues/1920)
(namespace scope, in v1.5). This repo creates only the two monitors it needs (table above). The metrics
of the gateway pods are already scraped by the RHOAI PodMonitor `openshift-ai-inference-metrics`. Check
again when RHCL ships kuadrant-operator 1.4.7 or later.

With `observability_enabled: false` the three operators are not installed and the gitops repo deploys
no Tempo instance and no collector; the router still works and still exposes its metrics.

> **Support status:** the OpenTelemetry collector image comes from the Red Hat build of OpenTelemetry.
> LiteLLM, which sends the traces of the router, is community software, not supported by Red Hat.

## Lint (also run by CI on every PR)

```bash
uv run yamllint .
uv run ansible-lint
uv run ansible-playbook playbooks/site.yml --syntax-check
shellcheck scripts/*.sh
```

## Layout notes

- `inventory/group_vars` is a symlink to the repo-root `group_vars/`, so the variables are loaded
  for `inventory/localhost.yml` while keeping the layout described in AGENTS.md.
- RHDP clusters already have OpenShift GitOps, cert-manager and the Red Hat build of Keycloak installed,
  with Automatic approval. The role keeps their OperatorGroups and updates their Subscriptions to the
  numbered channel, Manual approval and the pinned CSV. The operators are not reinstalled. Keycloak is
  managed only when `team_users` is set.

## License

Apache License 2.0, see [LICENSE](LICENSE).
