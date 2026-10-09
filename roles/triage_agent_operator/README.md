# triage_agent_operator

Installs the **triage-agent-operator** (kopf controller from the
[`triage-agent-operator`](https://github.com/sovereign-selfheal/triage-agent-operator) repo) on the
cluster: `TriageAgent` CRD, cluster RBAC, and a single-replica Deployment that watches every
namespace. GitOps then applies `TriageAgent` instances via `components/triage-agent-operator-cr`.

Runs in stage **20** (`playbooks/20-prereqs.yml`), before `30-gitops-seed.yml`, so the CRD and
controller exist when Argo CD syncs `TriageAgent` CRs. The playbook runs the role only with
`triage_agent_operator_enabled` (`group_vars/all/main.yml`, default `true`). `roles/argocd_seed` sends
the same switch to gitops as `triageAgentOperator.enabled`, so gitops renders `TriageAgent` CRs only
when the CRD and the operator are installed.

## What it creates

| Object | Details |
|---|---|
| Namespace `triage-agent-operator` | Not managed by Argo CD |
| `CustomResourceDefinition` `triageagents.triage.sovereign-selfheal.io` | Copy of `triage-agent-operator/deploy/crd.yaml` in `files/crd.yaml` |
| `ClusterRole` / `ClusterRoleBinding` `triage-agent-operator` | Reconcile `TriageAgent` CRs and their child objects in any namespace. No rights on Secrets (see below) |
| `ServiceAccount` + `Deployment` `triage-agent-operator` | Image `quay.io/sovereign-selfheal/triage-agent-operator` (pinned in `defaults/main.yml`) |

Argo CD health for `TriageAgent` is configured by `roles/argocd_seed` (`health-triageagent.lua`).

The Deployment runs **one** pod with strategy `Recreate`, and kopf runs with `--standalone` (no
peering). Two instances would reconcile the same CRs at the same time. The liveness and readiness
probes use the kopf liveness endpoint (`--liveness`, port `triage_agent_operator_health_port`). The
role waits until the Deployment is rolled out: the new spec is observed, and the one pod is updated
and ready.

**Secrets.** The ClusterRole has no rights on Secrets. The API key of each agent comes from the
External Secrets Operator: the gitops chart creates it and sets `spec.apiKey.existingSecret`. With
`existingSecret` set, the operator does not read or write any Secret. A `TriageAgent` without
`existingSecret` fails to reconcile on this platform (the operator would generate the key itself).

In check mode, on a cluster without the namespace, the ServiceAccount and the Deployment are
reported and skipped (the namespace is only dry-run created).

## Variables

See `defaults/main.yml`. Main switches:

| Variable | Default | Meaning |
|---|---|---|
| `triage_agent_operator_enabled` | `true` (`group_vars/all/main.yml`) | Set `false` to skip the role; also sent to gitops as `triageAgentOperator.enabled` |
| `triage_agent_operator_image` | Quay digest pin | Bump after each push to [quay.io/sovereign-selfheal/triage-agent-operator](https://quay.io/repository/sovereign-selfheal/triage-agent-operator) (record tag and date in `defaults/main.yml`) |
| `triage_agent_operator_namespace` | `triage-agent-operator` | Where the controller runs |
| `triage_agent_operator_log_level` | `INFO` | `INFO`, `DEBUG` (kopf `--verbose`) or `WARNING` (kopf `--quiet`) |
| `triage_agent_operator_health_port` | `8080` | Port of the kopf liveness endpoint (`/healthz`) |
| `triage_agent_operator_wait` / `_wait_retries` / `_wait_delay` | `true` / `30` / `10` | Wait for the rollout (5 minutes) |

## CRD sync

When the CRD changes in `triage-agent-operator`, refresh the copy in this role:

```bash
scripts/sync-triage-agent-operator-crd.sh [path/to/triage-agent-operator/deploy/crd.yaml]
```

The script drops the leading comment block of the upstream file and adds a short header. Do not
edit `files/crd.yaml` by hand: running the script again must give no diff.

## Tag

```bash
scripts/run-playbook.sh playbooks/20-prereqs.yml --tags triage_agent_operator
```
