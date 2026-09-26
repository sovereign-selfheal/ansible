# console_links

Adds entries to the **application menu** of the OpenShift console (grid icon, top right). Each entry
opens *Observe → Traces* on the Tempo instance of the gitops repo, already filtered with a TraceQL
query, so the demo shows the routing decisions of the router without typing a query.

The role reads the console URL of the cluster (`consoles.config.openshift.io/cluster`,
`status.consoleURL`), so the links are right on every cluster.

| Entry | TraceQL |
|---|---|
| Traces: every routing decision | `{ name = "router.chain" }` |
| Traces: routed to the LOCAL model | `{ span.route.target = "local-fast" }` |
| Traces: routed to the SOTA model | `{ span.route.target = "sota-smart" }` |
| Traces: kept local by the privacy gate | `{ name = "gate.privacy" && span.gate.verdict = "local" }` |

The spans come from the router hook (router v0.5.0 or later). `ConsoleLink` is cluster-scoped, so it
lives in this repo and not in the gitops repo.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `console_links_section` | `Sovereign Self-Healing demo` | Section of the application menu |
| `console_links_tempo_namespace` / `_name` / `_tenant` | `observability` / `tempo` / `router` | Tempo instance and tenant (contract with gitops) |
| `console_links_limit` | `20` | Traces shown per page |
| `console_links_traces` | the four entries above | `name` (ConsoleLink name), `text`, `query` (TraceQL) |

The playbook runs the role when `observability_enabled` is `true`.

## Usage

```bash
scripts/run-playbook.sh playbooks/30-gitops-seed.yml --tags console_links
```
