# gpu_node_prep

Creates one GPU MachineSet per availability zone on OpenShift on AWS.
To keep costs low, only the first `gpu_node_prep_active_zone_count` zones get machines. The
other MachineSets are created with 0 replicas, so you can scale them later.

## How it works

1. Reads the `Infrastructure` object and checks that the platform is AWS.
2. For each zone, picks the first worker MachineSet (sorted by name) as the source.
3. Creates `<infra-id>-gpu-<zone>`: a copy of the source `providerSpec` with a different
   `instanceType` and a bigger root disk (see "Root disk"), plus the GPU node labels and taints.
4. Waits until the expected machines are `Running` and the nodes are `Ready`. If a machine
   goes to `Failed` (for example, AWS quota or no capacity in the zone), the play stops and
   shows the AWS error message.
5. Waits until every GPU node exposes `nvidia.com/gpu`, that is, the NVIDIA driver is built
   and the device plugin runs. This step needs the GPU operator, so the waits run in stage 20,
   after the operators (stage 10).
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
| `gpu_node_prep_instance_type` | `g6.xlarge` | EC2 instance type (1x NVIDIA L4 24 GB) |
| `gpu_node_prep_zones` | `[]` | Zones to cover; empty means every zone with a worker MachineSet |
| `gpu_node_prep_active_zone_count` | `1` | How many zones (first in the list) get machines |
| `gpu_node_prep_replicas` | `1` | Machines per active zone; `0` scales every GPU MachineSet down |
| `gpu_node_prep_node_labels` | `node-role.kubernetes.io/gpu: ""` | Labels for the GPU nodes |
| `gpu_node_prep_taints` | `nvidia.com/gpu=true:NoSchedule` | Taints for the GPU nodes |
| `gpu_node_prep_volume_size` | `200` | Root disk size in GiB |
| `gpu_node_prep_volume_type` | `gp3` | EBS volume type of the root disk |
| `gpu_node_prep_volume_iops` | `""` | Root disk IOPS; empty keeps the source value (gp3 baseline 3000) |
| `gpu_node_prep_volume_throughput` | `""` | Root disk throughput in MB/s (gp3 only); empty = gp3 baseline 125 |
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
100 GiB disk was 57% full, and the kubelet starts deleting unused images at 85%.

IOPS and throughput keep the gp3 baseline by default. The image download from quay.io (about
22 MB/s, one stream for the 16 GB model layer) is slower than the baseline disk (125 MB/s), so
a faster disk does not make the pull faster.

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

# scale every GPU MachineSet to 0 (stops the EC2 costs, keeps the MachineSets)
scripts/run-playbook.sh playbooks/20-prereqs.yml -e gpu_node_prep_replicas=0

# GPU in a specific zone, for example when the first zone has no capacity
scripts/run-playbook.sh playbooks/20-prereqs.yml -e '{"gpu_node_prep_zones": ["us-east-2b", "us-east-2a", "us-east-2c"]}'
```

## Notes

- The instance type must exist in the cluster's region and zones. If it does not, the machine
  goes to `Failed` and the play shows the AWS error. Change `gpu_node_prep_instance_type` or
  the zone order.
- The role runs only when `gpu_enabled` and `gpu_nodes_managed` are both true.
- GPU workloads (for example vLLM) must tolerate the `nvidia.com/gpu` taint. The NVIDIA
  daemonsets tolerate it by default.
