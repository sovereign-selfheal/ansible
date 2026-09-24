# ingress_gateway

Creates the RHOAI inference Gateway and the public Route in front of it. The HTTPRoute,
AuthPolicy and TokenRateLimitPolicy that attach to this Gateway are in the gitops repo.

## What it creates (namespace `openshift-ingress`)

| Object | Details |
|---|---|
| ConfigMap `openshift-ai-inference-config` | Makes the generated Gateway Service `ClusterIP` (no extra load balancer) |
| Gateway `openshift-ai-inference` | Class `openshift-default` (created by the `rhcl` entry of `olm_operator`), HTTPS listener `*.<apps domain>` with the ingress certificate |
| Route `maas-router` | Host `router.<apps domain>`, TLS passthrough to the Gateway Service, timeout 180s |

The apps domain comes from `ingresses.config/cluster`. The certificate is the one of the default
IngressController (`spec.defaultCertificate`), or `router-certs-default` if there is none.
The traffic reuses the `*.apps` DNS record and certificate, so it works on every platform.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `ingress_gateway_name` | `openshift-ai-inference` | Gateway name |
| `ingress_gateway_namespace` | `openshift-ingress` | Namespace of Gateway, ConfigMap and Route |
| `ingress_gateway_class` | `gateway_class_name` or `openshift-default` | GatewayClass |
| `ingress_gateway_host_prefix` | `router` | Public host `<prefix>.<apps domain>`; must match the gitops HTTPRoute |
| `ingress_gateway_route_name` | `maas-router` | Route name |
| `ingress_gateway_route_timeout` | `180s` | Router timeout |
| `ingress_gateway_apps_domain` | `""` | Override of the apps domain |
| `ingress_gateway_cert_secret` | `""` | Override of the certificate Secret |
| `ingress_gateway_timeout` | `600` | Seconds to wait for the Gateway `Programmed` condition |
