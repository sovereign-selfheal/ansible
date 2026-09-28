# team_access

Personal logins for the team on the demo cluster. Each user gets a Keycloak account and is a
member of an OpenShift Group bound to `cluster-admin`. The Argo CD UI rights for the same Group are
added by [`roles/argocd_seed`](../argocd_seed/README.md) (`argocd_seed_admin_groups`).

The users come from the vault only (`team_users`, a list of `{username, password}`); see the
"Team access" section of the main [README](../../README.md). An empty list turns the role off.

## What it does

1. **Detect** (read-only, also run by the preflight with `tasks_from: preflight`): it looks for an
   OpenID identity provider in `OAuth/cluster` with the name `team_access_idp_name` **or** with the
   issuer of the realm. On RHDP it finds `rhbk` and takes the Keycloak URL and the realm from its issuer.
2. **Install** (only when no IdP matches): with no `Keycloak` CR, it creates the database Secret
   (random password, generated once), PostgreSQL (one pod, one PVC), the `Keycloak` CR and an edge
   Route `https://sso.<apps domain>`, then waits for `Ready`. An existing CR is only waited for.
3. **Realm and client** (only when no IdP matches): creates the realm (self-registration off) and
   the OpenID client with the OAuth callback URL, if they are missing, and copies the client secret to
   `openshift-config/<idp>-client-secret`. Existing objects are never changed.
4. **Users**: creates the Keycloak group `team_access_keycloak_group`, then each missing user in it,
   with the vault password as a temporary password (`UPDATE_PASSWORD`). Existing users are not
   changed. A listed user who exists **outside** the group stops the play: someone else created that
   account (the RHDP realm allows self-registration), and it must not become cluster-admin.
5. **OAuth** (only when no IdP matches): adds one OpenID IdP to `OAuth/cluster` (claims
   `preferred_username`, `email`, `name`), keeps the other IdPs, and waits for the `authentication`
   cluster operator. With the self-signed router certificate it also adds the ingress CA as
   `openshift-config/<idp>-ca`.
6. **RBAC**: `Group/<team_access_group>` with the usernames (the role owns the full list) and
   `ClusterRoleBinding/<group>-<cluster role>`.

The Keycloak calls use the Admin REST API with a token of the master admin, read from the Secret
`<keycloak name>-initial-admin` (or from `keycloak_admin_username` / `keycloak_admin_password`).
Every call is from the Ansible host to the Keycloak Route.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `team_access_users` | `team_users` | List of `{username, password}` (vault) |
| `team_access_group` | `team_group` (`selfheal-team`) | OpenShift Group, also the Keycloak group |
| `team_access_cluster_role` | `cluster-admin` | ClusterRole bound to the Group |
| `team_access_keycloak_namespace` / `_name` | `keycloak` / `keycloak` | Keycloak CR (RHDP values) |
| `team_access_realm` | `sso` | Realm (RHDP value); with an existing IdP the realm of its issuer wins |
| `team_access_idp_name` | `rhbk` | OAuth IdP name (RHDP value) |
| `team_access_client_id` | `idp-4-ocp` | OpenID client (RHDP value) |
| `team_access_keycloak_url` | `""` | Keycloak base URL; empty: from the IdP issuer, else `https://<host prefix>.<apps domain>` |
| `team_access_keycloak_host_prefix` | `sso` | Host of the Route when the role installs Keycloak |
| `team_access_admin_username` / `_password` | `keycloak_admin_username` / `_password`, else the Secret | Master admin |
| `team_access_validate_certs` | `true` | TLS check of the Keycloak URL; the ingress CA is trusted when the router cert is self-signed |
| `team_access_db_image` / `_db_size` | `rhel9/postgresql-16` / `1Gi` | PostgreSQL, only when the role installs Keycloak |
| `team_access_timeout` / `_poll_delay` | `900` / `10` | Waits |

## Usage

```bash
scripts/run-playbook.sh playbooks/15-identity.yml
scripts/run-playbook.sh playbooks/15-identity.yml --check   # stops after the detection if Keycloak is not running
```

## Limits

- Router to Keycloak is plain HTTP inside the cluster (edge Route). Enough for a demo.
- PostgreSQL has one replica and no backup: the accounts live as long as the cluster.
- A new cluster means new accounts: users start again from the initial password.
