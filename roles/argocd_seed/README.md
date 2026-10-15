# argocd_seed

Hands the workloads over to Argo CD. It prepares the default `openshift-gitops` instance and
creates the root Application that points to the gitops repo (path `bootstrap`). See the contract
in `AGENTS.md` §7.

## What it does

1. Decides the routing mode: **hybrid** when `sota_api_base`, `sota_model` and `sota_api_key` are all set,
   **local-only** when none of them is set. Only some of them set stops the play.
2. Creates the namespaces `local-models`, `maas-routing`, `agentic-triage`, one per entry of
   `argocd_seed_app_namespaces` (default: `payments`, `rh-reserve`, `reverse-proxy-app`) and
   `observability`, with the label `argocd.argoproj.io/managed-by: openshift-gitops`. The default
   instance cannot create namespaces; with this label the GitOps operator gives it admin rights
   there. `agentic-triage` (shared services: ticketing, the MCP servers, the Alertmanager bridge)
   gets `sovereign-selfheal.io/data-class: public`; each monitored-application namespace gets its
   own `data_class` (default: `payments` restricted, `rh-reserve` and `reverse-proxy-app` public) —
   namespace policy of the router; a new seed run sets the labels back.
3. Creates cluster-level RBAC prerequisites for gitops components: the ClusterRoles of
   `argocd_seed_cluster_roles` (`sovereign-selfheal-namespace-reader`,
   `sovereign-selfheal-demo-namespace-labeler`) and the ClusterRoleBindings of
   `argocd_seed_cluster_role_bindings` (`prometheus-mcp-server-sa-cluster-monitoring-view`,
   `ocp-mcp-server-sa-view`, and the namespace reader and labeler bindings of the `litellm` and
   `routing-live-view` ServiceAccounts).
4. Sets custom health checks on the ArgoCD CR: `Application` (so that the sync waves of the app
   of apps wait for each component), `AuthPolicy` and `TokenRateLimitPolicy` (Healthy when
   `Enforced`), `TempoMonolithic` (Healthy when `Ready`), `MCPServer` (Healthy when `Ready`) and
   `TriageAgent` (Healthy when `status.phase` is `Running`, Progressing while `Pending`).
   Argo CD 3.4 already knows
   `OpenTelemetryCollector`. This replaces `spec.resourceHealthChecks` of the instance.
   It also sets the resources of the application controller (`argocd_seed_controller_resources`,
   limit 4Gi instead of the operator default 2Gi), waits until the controller pod runs with them,
   and deletes the pod first when it crashes with the old limit (a StatefulSet does not replace a
   pod that is not Ready).
5. Creates the root Application with these values: `appsDomain` (from the cluster), `modelProfile`
   (`gpu` when `gpu_enabled`, else `cpu`), `sota.*` (with `sota.enabled` = hybrid mode),
   `secretStore.enabled`, `classifier.mode`, `observability.enabled`, `decisionModel.enabled`,
   `namespacePolicy.scan`, `namespacePolicy.hint`, `sotaBudget.enabled`, `triageAgentOperator.enabled`,
   `namespaces.observability`, one `namespaces.<key>` per entry of `argocd_seed_app_namespaces`
   (default: `namespaces.payments`, `namespaces.rhReserve`, `namespaces.reverseProxyApp`), `repo.*`,
   plus `argocd_seed_extra_values`. With the decision model
   and nodes from `roles/gpu_node_prep` it also sets
   `localModel.profiles.gpu.nodeSelector` to `node-role.kubernetes.io/gpu`, so that Qwen does not
   start on the decision node.
6. Asks Argo CD to refresh the root Application and its component Applications (annotation
   `argocd.argoproj.io/refresh: normal`, so a new commit on the same branch is seen at once). Then
   waits until the root Application has compared its current spec (branch and values), and every
   component Application it manages has compared its own spec, is at the same commit as the root
   one, and is `Synced` and `Healthy`. Synced/Healthy on the root Application alone is not enough:
   right after a new seed it still shows the result of the previous revision. Then it prints the
   state of every Application; when the wait times out, the error lists each Application that is
   not ready and why.

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
| `argocd_seed_triage_agent_operator_enabled` | `triage_agent_operator_enabled` (`true`) | Value `triageAgentOperator.enabled`: the TriageAgent CRD and the operator are installed ([`roles/triage_agent_operator`](../triage_agent_operator/README.md)), so gitops may render `TriageAgent` CRs |
| `argocd_seed_app_namespaces` | `payments` (restricted), `rh-reserve` (public), `reverse-proxy-app` (public) | Monitored-application namespaces: one quarkus-buggy-app and one agent each (gitops `components/quarkus-buggy-app` and `components/triage-agent-operator-cr`). Each entry is `{key, name, data_class}`; `key` becomes `namespaces.<key>` of the root Application, `name` is the namespace, `data_class` its `sovereign-selfheal.io/data-class` label |
| `argocd_seed_app_namespace_values` | computed from `argocd_seed_app_namespaces` | `{key: name}` map merged into the root Application's `namespaces` value |
| `argocd_seed_extra_values` | `{}` | Other values of `bootstrap/values.yaml` |
| `argocd_seed_namespaces` | `local-models`, `maas-routing`, `agentic-triage`, the entries of `argocd_seed_app_namespaces`, `observability` | Namespaces and labels (managed-by, data-class) |
| `argocd_seed_cluster_roles` | `sovereign-selfheal-namespace-reader`, `sovereign-selfheal-demo-namespace-labeler` (patches the namespaces of `argocd_seed_app_namespaces` only) | ClusterRoles for gitops components (the gitops AppProject allows no cluster-scoped objects) |
| `argocd_seed_cluster_role_bindings` | `prometheus-mcp-server-sa-cluster-monitoring-view`, `ocp-mcp-server-sa-view`, the namespace reader and labeler bindings | ClusterRoleBindings required by gitops components |
| `argocd_seed_mcpserver_api_group` | `mcp.x-k8s.io` | API group used by the MCPServer Argo CD health check (MCP Lifecycle Operator CRDs) |
| `argocd_seed_health_checks` | Application, AuthPolicy, TokenRateLimitPolicy, TempoMonolithic, MCPServer, TriageAgent | Lua files in `files/` |
| `argocd_seed_controller_resources` | requests 250m / 1Gi, limits 2 / 4Gi | `spec.controller.resources` of the ArgoCD CR. Each client-side apply needs about 300-430 MiB for a few seconds, on top of about 1-1.3 GiB; with the operator default (limit 2Gi) three applies at once OOMKilled the controller. `{}` keeps the operator default |
| `argocd_seed_admin_groups` | `[selfheal-team]` when `team_users` is set, else `[]` | OpenShift Groups made admin in the Argo CD UI: one `g, <group>, role:admin` line each, appended to `spec.rbac.policy` (existing lines are kept) |
| `argocd_seed_wait` / `_timeout` | `true` / `3600` (gpu), `1800` (cpu) | Wait for every Application Synced and Healthy at the new revision (step 6). The first start of the local model (Qwen3.8) on a new GPU node takes about 27 min |

## Usage

```bash
scripts/run-playbook.sh playbooks/30-gitops-seed.yml   # hybrid routing with a vault, local-only without
```
