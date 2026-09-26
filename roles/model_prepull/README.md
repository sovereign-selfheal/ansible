# model_prepull

Pulls the images of the local model on the nodes that will serve it, before the model exists.
The pull starts as soon as the node joins, instead of after the operators, the GPU driver and
the Argo CD sync; the model pod then joins the pull in progress or finds the images in the node
cache. See the limits below: a restart of CRI-O by the NVIDIA toolkit can discard a pull in progress.

```
05-early-nodes: GPU MachineSet (no wait) + pre-pull DaemonSets
        │  AWS builds the GPU node         10-operators runs meanwhile
        ▼
GPU node joins ──> prepull-modelcar and prepull-runtime pull in parallel
        ▼
30-gitops-seed: report (no wait) ──> seed ──> model pod: images already present
```

## What it creates

| Object | Details |
|---|---|
| Namespace `sovereign-selfheal-prepull` | Not managed by Argo CD |
| DaemonSet `prepull-modelcar` | Modelcar image (the model weights) of the selected profile |
| DaemonSet `prepull-runtime` | vLLM runtime image of the selected profile |

One DaemonSet per image, so the two pulls run **in parallel** (the containers of one pod
start one after the other, and each start waits for its image). The node bandwidth is shared,
so the gain is small (measured: 16m25s for both vs 17m20s one after the other).

When the NVIDIA driver is ready, the container toolkit restarts CRI-O on the GPU node. A pull in
progress stops and starts again from zero: only images that finished before the restart are
kept. See "Model image pre-pull and GPU disk" in the repo README.

Each pod only runs `sleep`: no GPU request, minimal CPU and memory, `imagePullPolicy: IfNotPresent`, restricted security
context. No pull secret is needed: `registry.redhat.io` is pulled with the global pull secret
of the node, as the model pod does.

The DaemonSets are **not** removed after the pull. Their pods keep the images in use, so the
kubelet image garbage collection does not delete them, and a new model pod on the same node
starts without a pull.

Where the pods run:

| Profile | Nodes | Toleration |
|---|---|---|
| `gpu` | `node-role.kubernetes.io/gpu` (set by `roles/gpu_node_prep` when the node is created) | `nvidia.com/gpu` |
| `gpu`, `gpu_nodes_managed: false` | `nvidia.com/gpu.present=true` | `nvidia.com/gpu` |
| `cpu` | `node-role.kubernetes.io/worker` | none |

The DaemonSets are created before the GPU node exists: they have 0 pods until the node joins,
and the pull starts at that moment.

## Entry points

| Tasks | Called by | What it does |
|---|---|---|
| `main.yml` | `playbooks/05-early-nodes.yml` | Namespace and DaemonSets, no wait |
| `status.yml` | `playbooks/30-gitops-seed.yml`, before the seed | Reports each image: present, still pulling (for how long), no node yet. Warns about `ErrImagePull`/`ImagePullBackOff`. Never waits, never fails: if the pull is still running, the model pod joins it |
| `verify.yml` | `playbooks/30-gitops-seed.yml`, after the seed | Compares the images of the model pod with the pre-pulled ones and warns if they differ |

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `model_prepull_enabled` | `true` (in `group_vars/all/main.yml`) | Run the role |
| `model_prepull_namespace` | `sovereign-selfheal-prepull` | Namespace of the DaemonSets |
| `model_prepull_profile` | `gpu` when `gpu_enabled`, else `cpu` | Same rule as the seed |
| `model_prepull_images` | current digests of both profiles | `{modelcar, runtime}` per profile, without `oci://` |
| `model_prepull_commands` | `sleep infinity` | Command of each pre-pull container |
| `model_prepull_node_selectors` / `_tolerations` | see the table above | Per profile |
| `model_prepull_resources` | requests 10m / 32Mi, limit 64Mi | Per container |
| `model_prepull_predictor_namespace` / `_selector` | `local-models` / `component=predictor` | Model pod for `verify.yml` |

**Keep the images in sync with the gitops repo.** `model_prepull_images.<profile>` must match
`localModel.profiles.<profile>.storageUri` (without `oci://`) and `.runtimeImage` in
`gitops/bootstrap/values.yaml`. When they differ, the pre-pull downloads images nobody uses;
`verify.yml` prints a `WARNING` after the seed.

## Usage

```bash
# only the pre-pull (for example after changing the images)
scripts/run-playbook.sh playbooks/05-early-nodes.yml --tags model_prepull

# report the pre-pull
scripts/run-playbook.sh playbooks/30-gitops-seed.yml --tags model_prepull

# without pre-pull
scripts/run-playbook.sh playbooks/site.yml -e model_prepull_enabled=false
```
