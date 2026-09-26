# olm_operator

Installs one OLM operator, pinned to an exact CSV, with `installPlanApproval: Manual`.
The role is generic: operators are data (`operators` in `group_vars/all/main.yml`), and
`playbooks/10-operators.yml` includes the role once per enabled entry.

## What it does, per entry

1. Asserts the pinning policy (Manual approval, resolved `starting_csv`).
2. Checks that the catalog (`source`) offers `starting_csv` in `channel`, selecting the
   PackageManifest by catalog label (some packages exist in more than one catalog).
3. Creates the `Namespace` (optional `openshift.io/cluster-monitoring` label). It never manages
   `openshift-operators`.
4. OperatorGroup: an existing one in the namespace is **reused** (e.g. created by RHDP); a
   new one is created only when none exists. More than one fails the play.
5. Applies the `pre_install` items. These are resources that the operator needs when it starts
   and that do not use its own CRDs. Example: the GatewayClass, because the Kuadrant operator
   looks for its Istio provider only at start-up.
6. Creates the `Subscription` named `subscription_name` (default: package name), with
   `startingCSV` and `Manual`. If a Subscription with this name already exists, the role updates
   its channel, approval and startingCSV. If the same package has a Subscription with a different
   name, the play fails.
7. If the pinned CSV is already `Succeeded`, the role skips this step. Otherwise it waits for the
   InstallPlan and checks `spec.clusterServiceVersionNames`: it must contain `starting_csv`, and
   the only other CSVs allowed are the ones in `expected_dependency_csvs`. If the check passes, the
   role approves the plan and waits until the CSV is `Succeeded`. If it fails, the play **stops**
   and the plan is never approved.
8. Applies the `post_install` items and waits for their readiness.
9. Reports unapproved InstallPlans (newer versions offered by the channel) in the summary.
   They are never approved; to upgrade, change the pin and re-run.

## Operator entry

| Field | Required | Default | Meaning |
|---|---|---|---|
| `key` | yes | `name` | Short id, also the tag (`--tags rhoai`) |
| `name` | yes | | Package name (`spec.name` of the Subscription) |
| `namespace` | yes | | Operator namespace |
| `channel` | yes | | Channel; prefer a numbered one |
| `starting_csv` | yes | | Pinned CSV, resolved with `scripts/resolve-operator-versions.sh` |
| `expected_dependency_csvs` | no | `[]` | CSVs OLM may add to the same InstallPlan (e.g. RHCL → authorino, limitador, dns) |
| `source` / `source_namespace` | no | `redhat-operators` / `openshift-marketplace` | CatalogSource |
| `install_plan_approval` | no | `Manual` | Anything else fails the policy check |
| `subscription_name` | no | `name` | Name of the Subscription to create or adopt |
| `subscription_config` | no | | Passed as `spec.config` (env, resources, ...) |
| `manage_namespace` | no | `true` | Create the namespace (always false for `openshift-operators`) |
| `namespace_cluster_monitoring` | no | `false` | Add `openshift.io/cluster-monitoring: "true"` |
| `create_operator_group` | no | `true` | Create an OperatorGroup if the namespace has none; `false` requires one to exist |
| `operator_group_all_namespaces` | no | `true` | `true`: empty spec (AllNamespaces); `false`: `targetNamespaces: [namespace]` |
| `operator_group_name` | no | `name` | Name for a newly created OperatorGroup |
| `csv_wait_timeout` | no | `olm_operator_csv_wait_timeout` | Seconds to wait for `Succeeded` |
| `allow_newer_installed` | no | `false` | Keep a pre-installed CSV newer than the pin (only Manual approval is set). For operators pre-installed by the platform, e.g. RHDP |
| `enabled` | yes | | `true` to install; the playbook converts it with `bool` |
| `pre_install` | no | `[]` | Items applied before the Subscription, same format as `post_install` |
| `post_install` | no | `[]` | List of items, see below |

### `pre_install` / `post_install` items

```yaml
post_install:
  - template: rhoai-dsc.yaml.j2        # file in roles/olm_operator/templates (multi-document allowed)
    vars: {name: default-dsc, components: "{{ rhoai_dsc_components }}"}   # template variables
    state: present                     # present (default) | patched (object must already exist)
    enabled: true                      # optional toggle
    wait_exists:                       # optional: wait until an object exists before applying
      {api_version: v1, kind: Service, name: my-svc, namespace: ns, timeout: 600}
    wait:                              # optional readiness wait, either a condition...
      api_version: datasciencecluster.opendatahub.io/v2
      kind: DataScienceCluster
      name: default-dsc
      condition: {type: Ready, status: "True"}
      # ...or a top-level status field:  status_field: phase / value: Ready
      timeout: 1200
```

`template` is optional: an item with only `wait_exists` is a pure wait (used after the GatewayClass
to wait for the Istio `wasmplugins.extensions.istio.io` CRD).

### Adopting a Subscription created by someone else

Set `subscription_name` to the existing name. Example: OLM creates the Subscriptions of the RHCL
dependencies with the name `<package>-<channel>-<source>-<source namespace>`:

```yaml
- key: authorino
  name: authorino-operator
  subscription_name: authorino-operator-stable-redhat-operators-openshift-marketplace
  namespace: openshift-operators
  manage_namespace: false
  create_operator_group: false
  channel: stable
  starting_csv: authorino-operator.v1.4.3
  enabled: true
```

The role finds the CSV already `Succeeded` and only sets Manual approval and startingCSV.

Templates only see the item's `vars`, so they contain no cluster-specific values.

| Template | Resource | Readiness |
|---|---|---|
| `namespace.yaml.j2` | Namespace | none |
| `gatewayclass.yaml.j2` | GatewayClass (OCP Gateway API provider) | `Accepted=True` |
| `kuadrant.yaml.j2` | Kuadrant | `Ready=True` |
| `authorino-service-cert.yaml.j2` | Service patch: serving-cert annotation | Service exists (before the patch) |
| `authorino.yaml.j2` | Authorino with TLS listener | `Ready=True` |
| `rhoai-dsc.yaml.j2` | DataScienceCluster v2 | `status.phase == Ready` |
| `nfd-instance.yaml.j2` | NodeFeatureDiscovery | `Available=True` |
| `gpu-cluster-policy.yaml.j2` | NVIDIA ClusterPolicy | `status.state == ready` |
| `external-secrets-config.yaml.j2` | ExternalSecretsConfig `cluster` (ESO) | `Ready=True`, then Deployment `external-secrets-webhook` `Available` |
| `uiplugin-distributed-tracing.yaml.j2` | UIPlugin `distributed-tracing` (COO console plugin) | `Available=True` |
| `uiplugin-monitoring-perses.yaml.j2` | UIPlugin `monitoring` with Perses (COO dashboards in the console) | `Available=True` |
| `tempo-tenant-rbac.yaml.j2` | ClusterRole + ClusterRoleBinding: the collector may write a Tempo tenant | none |

## Role variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `olm_operator_source` | `redhat-operators` | Default CatalogSource |
| `olm_operator_source_namespace` | `openshift-marketplace` | Default CatalogSource namespace |
| `olm_operator_install_plan_approval` | `Manual` | Default approval (policy: Manual only) |
| `olm_operator_installplan_timeout` | `300` | Seconds to wait for an InstallPlan |
| `olm_operator_csv_wait_timeout` | `900` | Seconds to wait for CSV `Succeeded` |
| `olm_operator_post_install_timeout` | `600` | Default seconds for post_install waits |
| `olm_operator_poll_delay` | `10` | Poll interval for all waits |
| `olm_operator_global_namespace` | `openshift-operators` | Namespace never created or managed |

## Behaviour notes

- **Check mode** (`--check --diff`): changes to the Namespace, OperatorGroup and Subscription are
  shown as diffs. For operators that are not installed yet, the role skips the approval, the waits
  and the post_install items, and prints a message: their CRDs do not exist yet. If the namespace
  does not exist yet, the objects inside it are reported but not sent to the API server.
- **Manual approval in `openshift-operators`**: OLM handles all Subscriptions in a namespace
  together. Because RHCL uses Manual approval there, upgrades of every other operator in
  `openshift-operators` also wait for manual approval.
- **Upgrades**: change `channel`/`starting_csv` in group_vars and run the playbook again. The role
  approves the pending InstallPlan only if it proposes exactly the new pin. If OLM proposes an
  intermediate version, the play fails and shows the proposed CSVs.
- **Downgrades** are not possible with OLM. If the installed CSV is newer than the pin, the play
  stops before it changes the Subscription.
- **Pre-installed operators** (`allow_newer_installed: true`): if the installed CSV is newer than
  the pin, the role keeps it. It sets only `installPlanApproval: Manual`, so the version is frozen,
  and it leaves the channel and startingCSV as they are. The summary shows the installed CSV.
  RHDP installs GitOps and cert-manager from `latest`, so a new cluster can have any version.
