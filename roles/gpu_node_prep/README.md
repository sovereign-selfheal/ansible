# gpu_node_prep

Creates GPU pools on OpenShift on AWS. Each pool has one MachineSet per availability zone.
To keep costs low, only the first `active_zone_count` zones of a pool get machines. The
other MachineSets are created with 0 replicas, so you can scale them later.

| Pool | When | Instance | Node label | For |
|---|---|---|---|---|
| `gpu` | always | `g7e.2xlarge` (RTX PRO 6000 Blackwell, 96 GB) | `node-role.kubernetes.io/gpu` | the local model (Qwen3.8) |
| `gpu-decision` | `decision_model_enabled` | `g6e.2xlarge` (L40S, 48 GB) | `node-role.kubernetes.io/gpu-decision` | the decision model (DiffusionGemma) |

Both pools use the taint `nvidia.com/gpu=true:NoSchedule`. The node labels keep the two models
apart: each model selects the label of its own pool.

## How it works

1. Reads the `Infrastructure` object and checks that the platform is AWS.
2. For each zone, picks the first worker MachineSet (sorted by name) as the source.
3. For each pool, creates `<infra-id>-<pool>-<zone>` (for example `<infra-id>-gpu-us-east-2a`
   and `<infra-id>-gpu-decision-us-east-2a`): a copy of the source `providerSpec` with a
   different `instanceType` and a bigger root disk (see "Root disk"), plus the node labels and
   taints of the pool. The Machines carry `cluster-api-machine-type: <pool>`.
4. For each pool, waits until the expected machines are `Running` and the nodes are `Ready`.
   If a machine goes to `Failed` (for example, AWS quota), the play stops and shows the AWS
   error message. A machine without capacity in the zone stays `Provisioning` instead: the wait
   then runs until its timeout (see "Notes").
5. For each pool, waits until every node exposes `nvidia.com/gpu`, that is, the NVIDIA driver
   is built and the device plugin runs, and checks the GPU memory (GFD label
   `nvidia.com/gpu.memory`) against the minimum of the pool. This step needs the GPU operator,
   so the waits run in stage 20, after the operators (stage 10).
6. Waits until the NVIDIA `ClusterPolicy` is `ready`. After a new node joins, the metrics
   components (`dcgm`, `dcgm-exporter`) need about one more minute. When the play ends, the
   GPU stack is fully ready.

Steps 4-6 run only with `gpu_node_prep_wait: true` (default). `site.yml` runs the role twice:
`playbooks/05-early-nodes.yml` with `gpu_node_prep_wait: false` (steps 1-3 only, before the
operators, so AWS builds the node while the operators are installed), then
`playbooks/20-prereqs.yml` with the waits. The second run changes nothing in the MachineSets.

Nothing about the cluster is hard-coded. Region, zones, AMI, subnets, security groups, IAM
profile, tags and infrastructure ID all come from the existing worker MachineSets, so the role
works on a new cluster in a different region without changes.

## Variables (`defaults/main.yml`)

| Variable | Default | Meaning |
|---|---|---|
| `gpu_node_prep_instance_type` | `g7e.2xlarge` | EC2 instance type (1x NVIDIA RTX PRO 6000 Blackwell 96 GB, needed for the NVFP4 model) |
| `gpu_node_prep_zones` | `[]` | Zones to cover; empty means every zone with a worker MachineSet |
| `gpu_node_prep_active_zone_count` | `1` | How many zones (first in the list) get machines |
| `gpu_node_prep_replicas` | `1` | Machines per active zone; `0` scales every GPU MachineSet down |
| `gpu_node_prep_node_labels` | `node-role.kubernetes.io/gpu: ""` | Labels for the GPU nodes |
| `gpu_node_prep_taints` | `nvidia.com/gpu=true:NoSchedule` | Taints for the GPU nodes |
| `gpu_node_prep_volume_size` | `200` | Root disk size in GiB |
| `gpu_node_prep_volume_type` | `gp3` | EBS volume type of the root disk |
| `gpu_node_prep_volume_iops` | `""` | Root disk IOPS; empty keeps the source value (gp3 baseline 3000) |
| `gpu_node_prep_volume_throughput` | `""` | Root disk throughput in MB/s (gp3 only); empty = gp3 baseline 125 |
| `gpu_node_prep_min_gpu_memory_mib` | `90000` | Minimum GPU memory of the `gpu` pool (RTX PRO 6000: 97887) |
| `gpu_node_prep_decision_enabled` | `decision_model_enabled` (default `gpu_enabled`) | Add the `gpu-decision` pool |
| `gpu_node_prep_decision_instance_type` | `g6e.2xlarge` | One NVIDIA L40S 48 GB, 8 vCPU, 64 GiB. Not `g6e.xlarge`: vLLM uses 31 GiB of host memory after the load |
| `gpu_node_prep_decision_zones` | `[]` | Zones of the decision pool; empty means every worker zone |
| `gpu_node_prep_decision_active_zone_count` | `1` | Zones of the decision pool that get machines |
| `gpu_node_prep_decision_replicas` | `1` | Machines per active zone; `0` scales the decision MachineSets down |
| `gpu_node_prep_decision_volume_size` | `200` | Root disk of the decision nodes in GiB (gp3 baseline). 100 GiB is not enough: the pull of the 27 GB modelcar layer needs about 55 GB |
| `gpu_node_prep_decision_node_labels` | `node-role.kubernetes.io/gpu-decision: ""` | Labels of the decision nodes |
| `gpu_node_prep_decision_min_gpu_memory_mib` | `40000` | Minimum GPU memory of the decision pool (L40S: 46068) |
| `gpu_node_prep_pools` | built from the variables above | The pools; override only to add a pool of your own |
| `gpu_node_prep_wait` | `true` | `false`: create or scale the MachineSets and return (steps 1-3) |
| `gpu_node_prep_timeout` | `1500` | Seconds to wait for the machines |
| `gpu_node_prep_wait_gpu_allocatable` | `true` | Wait until the nodes expose `nvidia.com/gpu` |
| `gpu_node_prep_gpu_timeout` | `1500` | Seconds to wait for `nvidia.com/gpu`, and then for the ClusterPolicy |
| `gpu_node_prep_wait_cluster_policy` | `true` | Wait until the ClusterPolicy is `ready` |
| `gpu_node_prep_cluster_policy_name` | `gpu_cluster_policy_name` or `gpu-cluster-policy` | ClusterPolicy to check |
| `gpu_node_prep_poll_delay` | `15` | Poll interval in seconds |
| `gpu_node_prep_machine_api_namespace` | `openshift-machine-api` | MachineSet namespace |

## Root disk

The first block device of the source MachineSet is copied with `volumeSize`, `volumeType` and,
when set, `iops` and `throughput` changed. Encryption, the KMS key and any other block device
stay as in the worker. The default is 200 GiB: after the first pull of Granite and vLLM a
100 GiB disk was 57% full, and the kubelet starts deleting unused images at 85%. With Qwen3.8
and vLLM the 200 GiB disk uses 69 of 214 GB after the first pull (2026-09-29).

IOPS and throughput keep the gp3 baseline by default. The image download from quay.io (one
stream per layer: about 22 MB/s for the 16 GB Granite layer, at least 36 MB/s for the 19.5 GB
Qwen3.8 layer) is slower than the baseline disk (125 MB/s), so a faster disk does not make the
pull faster.

**The disk settings apply only to new Machines.** An existing GPU node keeps its disk. To
change it, scale the MachineSet to 0 and back (the model is down in the meantime):

```bash
scripts/run-playbook.sh playbooks/20-prereqs.yml -e gpu_node_prep_replicas=0 --tags gpu_node_prep
scripts/run-playbook.sh playbooks/20-prereqs.yml --tags gpu_node_prep
```

## Usage

```bash
# create the MachineSets, one machine in the first zone (the GPU operator must be installed:
# run site.yml, or 10-operators.yml before this)
scripts/run-playbook.sh playbooks/20-prereqs.yml

# scale the gpu pool to 0 (stops the EC2 costs, keeps the MachineSets)
scripts/run-playbook.sh playbooks/20-prereqs.yml -e gpu_node_prep_replicas=0

# the decision pool (one g6e.2xlarge in the first zone) comes with the gpu pool, because
# decision_model_enabled follows gpu_enabled; a new cluster without it:
scripts/run-playbook.sh playbooks/20-prereqs.yml -e decision_model_enabled=false

# decision pool in a specific zone, for example when the first zone has no g6e capacity
scripts/run-playbook.sh playbooks/20-prereqs.yml \
  -e '{"gpu_node_prep_decision_zones": ["us-east-2a", "us-east-2b", "us-east-2c"]}'

# scale the decision pool to 0
scripts/run-playbook.sh playbooks/20-prereqs.yml -e gpu_node_prep_decision_replicas=0

# GPU in a specific zone, for example when the first zone has no capacity
scripts/run-playbook.sh playbooks/20-prereqs.yml -e '{"gpu_node_prep_zones": ["us-east-2b", "us-east-2a", "us-east-2c"]}'
```

## Notes

- The instance type must exist in the cluster's region and zones. If it does not, the machine
  goes to `Failed` and the play shows the AWS error. Change `gpu_node_prep_instance_type` or
  the zone order.
- With no capacity for the instance type in a zone, AWS answers `InsufficientInstanceCapacity`
  and the Machine stays `Provisioning` (it never goes to `Failed`). Watch the events of the
  Machine (`oc get events -n openshift-machine-api`) and change the zone order. On 2026-09-30
  `g6e.2xlarge` had no capacity in us-east-2b; us-east-2a had it at once.
- With `decision_model_enabled: false` the role does not read or change the decision
  MachineSets. To stop a decision node, scale it to 0 with the flag on (see "Usage").
- The role runs only when `gpu_enabled` and `gpu_nodes_managed` are both true.
- GPU workloads (for example vLLM) must tolerate the `nvidia.com/gpu` taint. The NVIDIA
  daemonsets tolerate it by default.
