# user_workload_monitoring

Turns on OpenShift **user workload monitoring**, so that Prometheus scrapes the `ServiceMonitor` and
`PodMonitor` objects of the demo namespaces (router metrics, vLLM metrics, Kuadrant metrics), and keeps
the metrics on a volume for `user_workload_monitoring_retention`. The monitors of the demo workloads are
in the gitops repo.

## What it does

1. Reads the ConfigMap `cluster-monitoring-config` in `openshift-monitoring`. RHDP may ship one, or
   none (none on OCP 4.22.14, RHDP, 2026-09-26).
2. Sets `enableUserWorkload: true` in its `config.yaml` and keeps every other setting. It writes the
   ConfigMap only when the key is missing or false, so the second run reports no change.
3. Sets the retention and a volume of the user workload Prometheus in the ConfigMap
   `user-workload-monitoring-config` (namespace `openshift-user-workload-monitoring`), key
   `prometheus`: `retention`, `retentionSize` and a `volumeClaimTemplate` (one PVC per replica). Other
   settings are kept, and the ConfigMap is written only when a value differs. Without this the metrics
   are kept 24 hours and are lost when a Prometheus pod restarts (emptyDir). When the volume is added,
   the monitoring operator recreates the Prometheus pods: the metrics collected before are lost once.
4. Waits until the Prometheus operator and the Prometheus pods of user workloads are ready in
   `openshift-user-workload-monitoring`, with the retention and the volume applied.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `user_workload_monitoring_config_namespace` / `_config_name` | `openshift-monitoring` / `cluster-monitoring-config` | Platform monitoring ConfigMap |
| `user_workload_monitoring_namespace` | `openshift-user-workload-monitoring` | Where the user workload Prometheus runs |
| `user_workload_monitoring_uwm_config_name` | `user-workload-monitoring-config` | ConfigMap of the user workload monitoring stack |
| `user_workload_monitoring_retention` | `15d` | How long the metrics are kept; empty = OpenShift default (24h) |
| `user_workload_monitoring_retention_size` | `18GB` | Oldest data deleted above this size; keep it below the volume size |
| `user_workload_monitoring_storage_size` | `20Gi` | PVC per Prometheus replica (2); empty = no volume |
| `user_workload_monitoring_storage_class` | `""` | Empty = the default StorageClass (gp3-csi on AWS) |
| `user_workload_monitoring_timeout` | `600` | Seconds to wait for Prometheus |
| `user_workload_monitoring_poll_delay` | `10` | Poll interval |

The playbook runs the role when `user_workload_monitoring_enabled` is `true` (default in
`group_vars/all/main.yml`).

## Usage

```bash
scripts/run-playbook.sh playbooks/20-prereqs.yml --tags user_workload_monitoring
```
