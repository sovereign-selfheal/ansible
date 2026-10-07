# argocd_seed

Hands the workloads over to Argo CD. It prepares the default `openshift-gitops` instance and
creates the root Application that points to the gitops repo (path `bootstrap`). See the contract
in `AGENTS.md` §7.

## What it does

1. Decides the routing mode: **hybrid** when `sota_api_base`, `sota_model` and `sota_api_key` are all set,
   **local-only** when none of them is set. Only some of them set stops the play.
2. Creates the namespaces `local-models`, `maas-routing`, `agentic-triage`, `payments`
   (`argocd_seed_restricted_namespace`) and `observability` with the label
   `argocd.argoproj.io/managed-by: openshift-gitops`. The default instance cannot create namespaces;
   with this label the GitOps operator gives it admin rights there. `agentic-triage` gets
   `sovereign-selfheal.io/data-class: public` and `payments` gets `restricted` (namespace policy of the
   router; a new seed run sets the labels back).
3. Creates cluster-level RBAC prerequisites for gitops components: the ClusterRoles of
   `argocd_seed_cluster_roles` (`sovereign-selfheal-namespace-reader`,
   `sovereign-selfheal-demo-namespace-labeler`) and the ClusterRoleBindings of
   `argocd_seed_cluster_role_bindings` (`prometheus-mcp-server-sa-cluster-monitoring-view`, and the
   namespace reader and labeler bindings of the `litellm` and `routing-live-view` ServiceAccounts).
4. Sets custom health checks on the ArgoCD CR: `Application` (so that the sync waves of the app
   of apps wait for each component), `AuthPolicy` and `TokenRateLimitPolicy` (Healthy when
   `Enforced`), `TempoMonolithic` (Healthy when `Ready`) and `MCPServer` (Healthy when `Ready`).
   Argo CD 3.4 already knows
   `OpenTelemetryCollector`. This replaces `spec.resourceHealthChecks` of the instance.
5. Creates the root Application with these values: `appsDomain` (from the cluster), `modelProfile`
   (`gpu` when `gpu_enabled`, else `cpu`), `sota.*` (with `sota.enabled` = hybrid mode),
   `secretStore.enabled`, `classifier.mode`, `observability.enabled`, `decisionModel.enabled`,
   `namespacePolicy.scan`, `namespacePolicy.hint`, `sotaBudget.enabled`, `namespaces.observability`,
   `namespaces.triageRestricted`, `repo.*`, plus `argocd_seed_extra_values`. With the decision model
   and nodes from `roles/gpu_node_prep` it also sets
   `localModel.profiles.gpu.nodeSelector` to `node-role.kubernetes.io/gpu`, so that Qwen does not
   start on the decision node.
6. Waits until the root Application is `Synced` and `Healthy` (so every component is), then
   prints the state of every Application.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `argocd_seed_repo_url` | `https://github.com/sovereign-selfheal/gitops.git` | gitops repo (public) |
| `argocd_seed_revision` | `main` | Branch, tag or commit |
| `argocd_seed_app_name` | `sovereign-selfheal` | Root Application name |
| `argocd_seed_model_profile` | from `gpu_enabled` | `gpu` or `cpu` |
| `argocd_seed_sota_api_base` / `_model` / `_served_match` | `sota_api_base`, `sota_model`, `sota_served_match` | External model of the router |
| `argocd_seed_sota_reasoning` | `sota_reasoning` (`false`) | `false`: the SOTA model answers without reasoning |
| `argocd_seed_secret_store_enabled` | `secret_store_enabled` (false) | True once the ClusterSecretStore exists |
| `argocd_seed_classifier_mode` | `classifier_mode` (`local`) | `local`, `external` (needs the vault) or `off` |
| `argocd_seed_observability_enabled` | `observability_enabled` (`true`) | Tempo and the collector in the gitops repo; needs the observability operators |
| `argocd_seed_observability_namespace` | `observability` | Namespace of Tempo and the collector |
| `argocd_seed_decision_model_enabled` | `decision_model_enabled` (default `gpu_enabled`) | Value `decisionModel.enabled`: the decision model of the gitops repo |
| `argocd_seed_local_model_node_selector` | `node-role.kubernetes.io/gpu` with the decision model and managed GPU nodes, else `{}` | Added to the nodeSelector of the local model; `{}` sends nothing |
| `argocd_seed_namespace_policy_scan` | `namespace_policy_scan` (`true`) | Value `namespacePolicy.scan`: the router finds namespace names in the request text |
| `argocd_seed_namespace_policy_hint` | `namespace_policy_hint` (`false`) | Value `namespacePolicy.hint`: the router reads the names that the agents send |
| `argocd_seed_sota_budget_enabled` | `sota_budget_enabled` (`true`) | Value `sotaBudget.enabled`: SOTA token budget per tier in the router (v0.12.0), with a Redis of the gitops repo |
| `argocd_seed_restricted_namespace` | `payments` | Namespace of the second quarkus-buggy-app, labelled `restricted`; value `namespaces.triageRestricted` |
| `argocd_seed_extra_values` | `{}` | Other values of `bootstrap/values.yaml` |
| `argocd_seed_namespaces` | `local-models`, `maas-routing`, `agentic-triage`, `payments`, `observability` | Namespaces and labels (managed-by, data-class) |
| `argocd_seed_cluster_roles` | `sovereign-selfheal-namespace-reader`, `sovereign-selfheal-demo-namespace-labeler` | ClusterRoles for gitops components (the gitops AppProject allows no cluster-scoped objects) |
| `argocd_seed_cluster_role_bindings` | `prometheus-mcp-server-sa-cluster-monitoring-view`, the namespace reader and labeler bindings | ClusterRoleBindings required by gitops components |
| `argocd_seed_mcpserver_api_group` | `mcp.x-k8s.io` | API group used by the MCPServer Argo CD health check (MCP Lifecycle Operator CRDs) |
| `argocd_seed_health_checks` | Application, AuthPolicy, TokenRateLimitPolicy, TempoMonolithic, MCPServer | Lua files in `files/` |
| `argocd_seed_admin_groups` | `[selfheal-team]` when `team_users` is set, else `[]` | OpenShift Groups made admin in the Argo CD UI: one `g, <group>, role:admin` line each, appended to `spec.rbac.policy` (existing lines are kept) |
| `argocd_seed_wait` / `_timeout` | `true` / `3600` (gpu), `1800` (cpu) | Wait for Synced and Healthy. The first start of the local model (Qwen3.8) on a new GPU node takes about 27 min |

## Usage

```bash
scripts/run-playbook.sh playbooks/30-gitops-seed.yml   # hybrid routing with a vault, local-only without
```
