# secrets_bootstrap

Lands the secret values in the cluster for the External Secrets Operator (ESO). The workloads of
the gitops repo never read these values directly: their `ExternalSecret`s copy them through the
`ClusterSecretStore` created here.

```
group_vars/all/vault.yml (ansible-vault) ──> this role ──> Secrets in sovereign-selfheal-secrets
  or AgnosticV extra vars                                     │ ClusterSecretStore sovereign-selfheal
                                                              ▼ (ESO provider "kubernetes")
                                          ExternalSecrets of the gitops repo ──> maas-routing
```

## What it creates

Only when `sota_api_key` is set. Without it the role does nothing, and the router runs in
local-only mode (see the repo README).

| Object | Details |
|---|---|
| Namespace `sovereign-selfheal-secrets` | Holds the source Secrets. Not managed by Argo CD |
| Secret `sota` | Key `api_key` = `sota_api_key` |
| Secret `classifier` (only `classifier_mode: external`) | Keys `base_url`, `model`, `api_key` = `classifier_*` |
| ServiceAccount `eso-reader` + Role + RoleBinding | ESO reads Secrets only in this namespace |
| ClusterSecretStore `sovereign-selfheal` | Provider `kubernetes`, waits for `Ready` |

Values are never printed (`no_log`). A Secret with no values is not created.

## Variables

| Variable | Default | Meaning |
|---|---|---|
| `secrets_bootstrap_namespace` | `sovereign-selfheal-secrets` | Namespace of the source Secrets |
| `secrets_bootstrap_store_name` | `sovereign-selfheal` | Must match `secretStore.name` in the gitops repo |
| `secrets_bootstrap_service_account` | `eso-reader` | ServiceAccount used by ESO |
| `secrets_bootstrap_secrets` | `sota`, `classifier` | Secret name -> {key: value}; must match `secretStore.*` in the gitops repo |
| `secrets_bootstrap_timeout` | `300` | Seconds to wait for the store |

## Another backend

To use an external store later (for example HashiCorp Vault), replace the store in
`templates/store.yaml.j2` and keep the name `sovereign-selfheal`. The gitops repo does not change,
as long as the keys (`sota`, `classifier`) and properties stay the same.
