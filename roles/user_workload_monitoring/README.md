# user_workload_monitoring

Turns on OpenShift **user workload monitoring**, so that Prometheus scrapes the `ServiceMonitor` and
`PodMonitor` objects of the demo namespaces (router metrics, vLLM metrics). The monitors themselves
are in the gitops repo.

## What it does

1. Reads the ConfigMap `cluster-monitoring-config` in `openshift-monitoring`. RHDP may ship one, or
   none (none on OCP 4.22.14, RHDP, 2026-09-26).
2. Sets `enableUserWorkload: true` in its `config.yaml` and keeps every other setting. It writes the
   ConfigMap only when the key is missing or false, so the second run reports no change.
3. Waits until the Prometheus operator and the Prometheus pods of user workloads are ready in
   `openshift-user-workload-monitoring`.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `user_workload_monitoring_config_namespace` / `_config_name` | `openshift-monitoring` / `cluster-monitoring-config` | Platform monitoring ConfigMap |
| `user_workload_monitoring_namespace` | `openshift-user-workload-monitoring` | Where the user workload Prometheus runs |
| `user_workload_monitoring_timeout` | `600` | Seconds to wait for Prometheus |
| `user_workload_monitoring_poll_delay` | `10` | Poll interval |

The playbook runs the role when `user_workload_monitoring_enabled` is `true` (default in
`group_vars/all/main.yml`).

## Usage

```bash
scripts/run-playbook.sh playbooks/20-prereqs.yml --tags user_workload_monitoring
```
