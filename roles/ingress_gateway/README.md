# ingress_gateway

Creates the RHOAI inference Gateway and the public Route in front of it. The HTTPRoute,
AuthPolicy and TokenRateLimitPolicy that attach to this Gateway are in the gitops repo.

## What it creates (namespace `openshift-ingress`)

| Object | Details |
|---|---|
| ConfigMap `openshift-ai-inference-config` | Makes the generated Gateway Service `ClusterIP` (no extra load balancer), fixes the gateway pods at 2 (no HPA scale-down) and lets a stopping pod finish the requests in flight (drain 600 s) |
| Gateway `openshift-ai-inference` | Class `openshift-default` (created by the `rhcl` entry of `olm_operator`), HTTPS listener `*.<apps domain>` with the ingress certificate |
| Route `maas-router` | Host `router.<apps domain>`, TLS passthrough to the Gateway Service, timeout 10m |
| IngressController `default` (AWS Classic LB only) | Load balancer idle timeout 10m instead of the AWS default 60s; the load balancer is updated in place |

The apps domain comes from `ingresses.config/cluster`. The certificate is the one of the default
IngressController (`spec.defaultCertificate`), or `router-certs-default` if there is none.
The traffic reuses the `*.apps` DNS record and certificate, so it works on every platform.

**Why the long timeouts.** Without streaming, no byte flows until an LLM answer is complete. A SOTA
model with reasoning can take a few minutes, and the AWS Classic load balancer closes idle connections
after 60 s by default: every longer answer was cut. The role repeats the current publishing strategy
of the default IngressController and changes only `connectionIdleTimeout`, so the load balancer is
not recreated. Clients should still prefer streaming.

## After the seed: Kuadrant wasm module

`tasks/verify.yml` runs from `playbooks/30-gitops-seed.yml`, after the seed (only when the seed
waits for the workloads). When gitops applies the AuthPolicy, Kuadrant adds a wasm filter to the
Gateway. Each gateway Envoy downloads the module once from the Service `kuadrant-operator-wasm`
(namespace `openshift-operators`), with no retry. If the download fails, the pod answers **503**
to every request (Envoy access log: `wasm_fail_stream`) and stays broken. This happened on
2026-09-29 on one of the two pods. The Route is passthrough and HAProxy balances by source IP, so
some clients always reached the broken pod and got only errors.

The check reads `wasm.remote_load_fetch_successes` and `_failures` from the Envoy stats of every
gateway pod (`pilot-agent request GET stats`). A probe of the public host is not enough: it
reaches one pod only. A pod is healthy with at least one download and no failed one. Pods with a
failed download are deleted once. The Deployment creates new pods, which download the module
again. The play fails if a new pod fails again, if a pod makes no download attempt within
`ingress_gateway_wasm_wait_timeout`, if the Envoy stats cannot be read, or if no gateway pod is
running. Then check the Service `kuadrant-operator-wasm`. On a healthy cluster the check changes
nothing.

The check runs only after the seed. A gateway pod recreated later (node drain, upgrade) is not
repaired: validation check P18 finds it, and `oc delete pod` fixes it.

Run it alone: `scripts/run-playbook.sh playbooks/30-gitops-seed.yml --tags ingress_gateway`.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `ingress_gateway_name` | `openshift-ai-inference` | Gateway name |
| `ingress_gateway_namespace` | `openshift-ingress` | Namespace of Gateway, ConfigMap and Route |
| `ingress_gateway_class` | `gateway_class_name` or `openshift-default` | GatewayClass |
| `ingress_gateway_host_prefix` | `router` | Public host `<prefix>.<apps domain>`; must match the gitops HTTPRoute |
| `ingress_gateway_route_name` | `maas-router` | Route name |
| `ingress_gateway_route_timeout` | `10m` | Router timeout |
| `ingress_gateway_lb_idle_timeout` | `10m` | Idle timeout of the AWS Classic load balancer; empty = no change |
| `ingress_gateway_min_replicas` / `_max_replicas` | `2` / `2` | Gateway pods (HPA bounds). The GatewayClass default 2-10 scaled up on a few requests and cut long answers on scale-down |
| `ingress_gateway_drain_seconds` | `600` | Time a stopping gateway pod keeps serving the requests in flight (Istio `terminationDrainDuration`) |
| `ingress_gateway_apps_domain` | `""` | Override of the apps domain |
| `ingress_gateway_cert_secret` | `""` | Override of the certificate Secret |
| `ingress_gateway_timeout` | `600` | Seconds to wait for the Gateway `Programmed` condition |
| `ingress_gateway_pod_selector` | `gateway.networking.k8s.io/gateway-name=<name>` | Label selector of the gateway pods (wasm check) |
| `ingress_gateway_proxy_container` | `istio-proxy` | Container that runs Envoy in the gateway pods |
| `ingress_gateway_wasm_wait_timeout` | `300` | Seconds to wait for the wasm download of each pod and for the new pods |
| `ingress_gateway_wasm_poll_delay` | `10` | Seconds between two reads |
