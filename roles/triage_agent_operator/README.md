# triage_agent_operator

Installs the **triage-agent-operator** (kopf controller from the
[`triage-agent-operator`](https://github.com/sovereign-selfheal/triage-agent-operator) repo) on the
cluster: `TriageAgent` CRD, cluster RBAC, and a single-replica Deployment that watches every
namespace. GitOps then applies `TriageAgent` instances via `components/triage-agent-operator-cr`.

Runs in stage **20** (`playbooks/20-prereqs.yml`), before `30-gitops-seed.yml`, so the CRD and
controller exist when Argo CD syncs `TriageAgent` CRs.

## What it creates

| Object | Details |
|---|---|
| Namespace `triage-agent-operator` | Not managed by Argo CD |
| `CustomResourceDefinition` `triageagents.triage.sovereign-selfheal.io` | Copy of `triage-agent-operator/deploy/crd.yaml` in `files/crd.yaml` |
| `ClusterRole` / `ClusterRoleBinding` `triage-agent-operator` | Reconcile `TriageAgent` CRs and child resources in any namespace |
| `ServiceAccount` + `Deployment` `triage-agent-operator` | Image `quay.io/sovereign-selfheal/triage-agent-operator` (pinned in `defaults/main.yml`) |

Argo CD health for `TriageAgent` is configured by `roles/argocd_seed` (`health-triageagent.lua`).

## Variables

See `defaults/main.yml`. Main switches:

| Variable | Default | Meaning |
|---|---|---|
| `triage_agent_operator_enabled` | `true` | Set `false` to skip the role |
| `triage_agent_operator_image` | Quay digest pin | Bump after each push to [quay.io/sovereign-selfheal/triage-agent-operator](https://quay.io/repository/sovereign-selfheal/triage-agent-operator) (record tag and date in `defaults/main.yml`) |
| `triage_agent_operator_namespace` | `triage-agent-operator` | Where the controller runs |

## CRD sync

When the CRD changes in `triage-agent-operator`, refresh the copy in this role:

```bash
scripts/sync-triage-agent-operator-crd.sh
```

## Tag

```bash
scripts/run-playbook.sh playbooks/20-prereqs.yml --tags triage_agent_operator
```
