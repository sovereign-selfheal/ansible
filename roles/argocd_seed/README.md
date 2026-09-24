# argocd_seed

Hands the workloads over to Argo CD. It prepares the default `openshift-gitops` instance and
creates the root Application that points to the gitops repo (path `bootstrap`). See the contract
in `AGENTS.md` §7.

## What it does

1. Decides the routing mode: **hybrid** when `sota_api_base`, `sota_model` and `sota_api_key` are all set,
   **local-only** when none of them is set. Only some of them set stops the play.
2. Creates the namespaces `local-models` and `maas-routing` with the label
   `argocd.argoproj.io/managed-by: openshift-gitops`. The default instance cannot create namespaces;
   with this label the GitOps operator gives it admin rights there.
3. Sets custom health checks on the ArgoCD CR: `Application` (so that the sync waves of the app
   of apps wait for each component), `AuthPolicy` and `TokenRateLimitPolicy` (Healthy when
   `Enforced`). This replaces `spec.resourceHealthChecks` of the instance.
4. Creates the root Application with these values: `appsDomain` (from the cluster), `modelProfile`
   (`gpu` when `gpu_enabled`, else `cpu`), `sota.*` (with `sota.enabled` = hybrid mode),
   `secretStore.enabled`, `classifier.mode`, `repo.*`, plus `argocd_seed_extra_values`.
5. Waits until the root Application is `Synced` and `Healthy` (so every component is), then
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
| `argocd_seed_extra_values` | `{}` | Other values of `bootstrap/values.yaml` |
| `argocd_seed_namespaces` | `local-models`, `maas-routing` | Namespaces and labels |
| `argocd_seed_health_checks` | Application, AuthPolicy, TokenRateLimitPolicy | Lua files in `files/` |
| `argocd_seed_wait` / `_timeout` | `true` / `1800` | Wait for Synced and Healthy |

## Usage

```bash
ansible-playbook playbooks/30-gitops-seed.yml --ask-vault-pass   # hybrid routing
ansible-playbook playbooks/30-gitops-seed.yml                    # local-only mode
```
