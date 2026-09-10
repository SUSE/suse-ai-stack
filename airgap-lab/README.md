# SUSE AI Factory air-gap lab

This directory is a post-provisioning overlay for `suse-ai-stack`. Its default
QA environment deploys real, mirrored Qdrant and Ollama applications on the
management and downstream clusters. It verifies their APIs, private chart and
image delivery, authentication, TLS trust, Fleet, and rejected public egress.
GPU workers are optional and use the original stack's node configuration fields.
Ollama starts without models; an inference test needs separately imported models.

## Topology and trust boundary

```text
connected seed/controller
  |  export/import (only before the gate closes)
  v
services RKE2 cluster/VM
  |- Harbor (private projects, TLS, authentication)
  `- Gitea (private-CA HTTPS and authentication)
            ^                         ^
            | private CIDRs only      | private CIDRs only
management RKE2                 downstream RKE2
Rancher + AIF                   CPU/GPU workload targets
```

The services node is intentionally not part of `airgap_isolated`: Harbor is not
configured as a pull-through cache, and Gitea has no proxy role, so it cannot
provide an escape path. Keeping it connected avoids the registry-bootstrap
chicken-and-egg problem and lets it be rebuilt. Management, workload, GPU worker, and
optional browser nodes receive both host-output and pod-forward nftables rules.

## One-command AWS lab

For the repository's normal AWS workflow, keep the provider, SCC and vendor
credentials in the ignored top-level `extra_vars.yml`, then run:

```console
./setup_airgap_lab.sh
```

The command defaults to three CPU nodes, installs Rancher/RKE2, Harbor and
Gitea, builds the exact sibling AIF checkout, transfers the checksummed `suse`
bundle, applies the network gate, and deploys Qdrant and Ollama through their
custom Blueprints. It removes the earlier synthetic smoke fixtures and disables
bundled Blueprint cards whose complete offline dependencies are not staged. It is resumable: completed phases have ignored markers
under `airgap-lab/generated/state/`, so run the same command after correcting a
failure. Useful lifecycle commands are:

```console
./setup_airgap_lab.sh --prepare-only  # validate and render; no AWS writes
./setup_airgap_lab.sh --status
./setup_airgap_lab.sh --reset-progress # rerun source/application checks; retain infrastructure
./destroy_airgap_lab.sh                # guarded dedicated-workspace destroy
```

After a successful qualification, the setup command creates loopback-only HTTP
links for the private Harbor and Gitea UIs. A digest-pinned Caddy proxy preserves
each ingress host header over an SSH tunnel to the services node, so neither
service needs a public security-group rule, a local CA installation, or an
`/etc/hosts` entry:

```text
Harbor UI: http://127.0.0.1:18080/
Gitea UI: http://127.0.0.1:18081/
```

The final setup output also prints the management node's public IP and the
exact `<IP> suse-rancher.demo` entry needed in the controller's `/etc/hosts`.
The same values are retained in the ignored, mode-`0600`
`airgap-lab/generated/ui-links/links.txt`; `--status` reports whether the proxy
and SSH tunnel are still running. Both the final setup output and `--status`
also print the Rancher, Harbor, and Gitea UI usernames and passwords in plain
text. The UI helper reads the current credentials from
`airgap-lab/generated/vars.yml` (or `AIF_AIRGAP_VARS` when set); Harbor uses the
`admin` account and `harbor_admin_password`.

Override the local ports with
`AIF_AIRGAP_HARBOR_UI_PORT`, `AIF_AIRGAP_GITEA_UI_PORT`, and
`AIF_AIRGAP_UI_TUNNEL_PORT` when the defaults are occupied. Diagnostic HTTP
Gitea runs also use `AIF_AIRGAP_GITEA_UI_TUNNEL_PORT`, defaulting to `18444`.

`destroy_airgap_lab.sh` stops and removes the lab-owned proxy and SSH tunnel,
then deletes the generated links before destroying AWS resources. The helper
can also be managed independently:

```console
airgap-lab/scripts/ui-links.sh start
airgap-lab/scripts/ui-links.sh status
airgap-lab/scripts/ui-links.sh stop
```

The lab uses the dedicated `suseai-882-airgap` OpenTofu workspace and appends a
lab suffix to resource/key names. It never operates on the default workspace.
Generated AWS credentials, Rancher/Harbor/Gitea passwords, CA private keys,
inventories and state markers are mode `0600` and ignored by Git. The default
AWS shape is `m6i.2xlarge` for management and `m6i.xlarge` for downstream and
services, with no GPU instances. These are billable resources; always use the
guarded destroy command when the QA session ends.

By default the sibling checkout `../aif` is qualified and native Settings CA
propagation is required (`aif_registry_ca_mode: settings`). Existing values in
the ignored `airgap-lab/generated/vars.yml` are retained across resumable runs;
the script merges new example defaults into that file and overwrites only
machine-derived values. Environment overrides are available for the two
qualification axes and for a nonstandard SSH key:

```console
AIF_SOURCE_DIR=/path/to/aif AIF_AIRGAP_PROFILE=core ./setup_airgap_lab.sh
AIF_SOURCE_DIR=/path/to/aif AIF_AIRGAP_PROFILE=suse ./setup_airgap_lab.sh
AIF_SOURCE_DIR=/path/to/aif AIF_AIRGAP_PROFILE=chatbot ./setup_airgap_lab.sh
AIF_AIRGAP_INSTALL_MODE=separate ./setup_airgap_lab.sh
AIF_AIRGAP_CA_MODE=workaround ./setup_airgap_lab.sh
AIF_AIRGAP_GITEA_TLS=false ./setup_airgap_lab.sh  # diagnostic only
AIF_AIRGAP_SSH_KEY=/path/to/aws-private-key ./setup_airgap_lab.sh
```

The install mode defaults to `combined`, the CA mode to `settings`, and Gitea
to private-CA HTTPS in `vars.example.yml`. Each install/CA/Git-transport
combination has independent resumable qualification markers and an evidence
file, while the expensive AWS, build and mirror phases are reused. The runner
records the combination currently active on the management cluster, so
switching an axis always forces installation, applications and verification to run
again; changing Gitea transport also reconciles the services phase. Switching
back to combined mode removes the standalone UI release before reconciling the
operator-managed extension. A `workaround` or HTTP pass remains useful for
diagnosis, but is not native air-gap evidence.

For one-command `suse`, `chatbot`, `vendor`, or `all` runs, the setup script reads the
Application Collection email/token from the ignored top-level `extra_vars.yml`
unless `APPCO_USERNAME` and `APPCO_PASSWORD` are already exported. Manual
`run.sh` workflows use the environment variables shown below.

The services security group exposes SSH only to the controller's detected
public `/32`; Harbor and Gitea are reachable only from the private VPC. Set
`AIF_AIRGAP_CONTROLLER_CIDR` explicitly when the controller uses a stable VPN
or NAT address. Management/workload isolation retains only established admin
responses, private VPC/pod/service networks and AWS DNS while rejecting new
public egress. The configure phase publishes the private Harbor, Gitea and
Rancher records through each RKE2 cluster's CoreDNS; pod-side controllers cannot
rely on host `/etc/hosts` entries.

## Configure GPU workers

Copy the CPU defaults or the GPU example to the ignored `nodes.yml`:

```console
cp airgap-lab/nodes.gpu.example.yml airgap-lab/nodes.yml
./setup_airgap_lab.sh --prepare-only
# Review the generated node counts and instance types, then apply:
./setup_airgap_lab.sh
```

`nodes.yml` uses the original stack's `cluster` (management) and
`suse_ai_cluster` (downstream) fields. Omitted fields inherit
[`nodes.example.yml`](nodes.example.yml). A minimal override is:

```yaml
suse_ai_cluster:
  num_worker_nodes_gpu: 1
  instance_type_gpu: g4dn.2xlarge
  root_volume_size: 200
```

The example retains a CPU control plane and adds a downstream GPU worker.
`instance_type_cp`, `instance_type_nongpu`, and `num_worker_nodes_nongpu` are
also configurable. GPU instances belong in `instance_type_gpu`; the other
instance fields are for CPU nodes. The lab keeps one control plane per cluster. As in the
original stack, `root_volume_size` applies to **every node in that cluster**;
increasing it also grows the control plane's volume. Choose the instance type
for the model's VRAM requirement: G4dn uses a 16 GiB T4, while G6 uses a 24 GB
L4 ([AWS instance specifications](https://docs.aws.amazon.com/ec2/latest/instancetypes/ac.html)).
The lab's SLES image is x86_64; AMD G4ad and Arm G5g configurations are rejected.

A custom file can be selected with `AIF_AIRGAP_NODE_CONFIG=/path/to/nodes.yml`.
Do not edit `generated/stack-vars.yml`; preparation regenerates it. Provider,
SCC and source-registry credentials remain in the normal `extra_vars.yml`.
With no `nodes.yml`, the default remains CPU-only.

Requesting GPUs enables the original stack's `enable_gpu_operator` and
`enable_nvidia_driver_pkg_install` paths for the clusters that have GPU workers.
The driver is installed while connected; the Operator uses `driver.enabled=false`.
`gpu_operator_chart_version` is pinned in the node defaults. Optional
`enable_time_slicing` and `time_slicing_replicas` use the original stack's names.
The GPU phase checks `nvidia-smi`, node readiness and `nvidia.com/gpu`, inventories
the enabled Operator workloads including init containers/validators, and exports
a separate checksummed image bundle to Harbor before isolation. After isolation,
verification pulls those references through each GPU node's registry mirror and
checks GPU availability again. This follows NVIDIA's separation of
[driver packages and container images](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/install-gpu-operator-air-gapped.html).

Changing node counts, instance types, disk sizes or GPU options invalidates the
provisioning and node-verification checkpoints. The next setup reconciles AWS,
refreshes the complete worker inventory, and reapplies trust, mirrors and
isolation. Node removal in the configuration removes those AWS workers during
reconciliation. Existing nodes temporarily regain public egress and upstream
registry access for the connected provisioning phase; the lab restores both
restrictions afterward. The original RKE2 load-balancer hostnames resolve to
each cluster's private control-plane IP inside the lab, retaining the existing
TLS names and allowing worker reconnection under isolation. Setup/status prints every node's SSH IP as well as the UI
credentials. Status lists only the active run's checkpoints and reports when
the desired node configuration has not yet been applied.

This supports GPU infrastructure for the lab's connected preparation followed
by isolated testing. Adding Operator features, upgrading drivers after
isolation, or deploying NIM/model workloads needs a new preparation/export.
The shipped Qdrant and Ollama Blueprints remain CPU applications. GPU hardware
provisioning is opt-in and is not part of the recorded CPU validation run.

## What is automated

- a connected-stage, single-node, CPU-only RKE2 services cluster;
- Harbor 2.15.2 through chart 1.19.2, private projects, authentication and a
  generated lab CA;
- Gitea 1.27.0 through chart 12.7.0, a private Blueprint/GitOps repository,
  SQLite storage, and a switchable private-CA HTTPS ingress;
- checksummed chart and multi-architecture image export/import with Skopeo and
  Helm (no `docker save`, no silent skips, no password-on-command-line login);
- RKE2 `registries.yaml` on every schedulable management/workload node, Harbor
  authentication/CA, per-source rewrites, and
  `disable-default-registry-endpoint: true`;
- one managed CoreDNS `hosts` block per RKE2 cluster for Harbor, Gitea and the
  private Rancher endpoint, including consolidation of the base stack's Rancher
  record;
- AIF combined operator+UI or separate operator/UI installation from Harbor;
- Settings endpoints for the catalogs populated by the selected profile;
- real Qdrant and Ollama Blueprints delivered by private Git, with application
  API checks on both selected targets;
- optional GPU workers, connected driver/GPU Operator installation, private
  mirroring of the enabled GPU component images, and GPU resource checks;
- reversible egress denial and positive/negative verification probes.

## Prerequisites

The manual/provider-independent workflow below remains useful for local VMs or
custom infrastructure. AWS users normally use the one-command path above.

1. Use `suse-ai-stack` to create the Rancher management cluster and, for the
   multi-cluster test, a CPU-only `suse_ai_cluster`. Set GPU worker counts and
   `enable_gpu_operator` to zero/false. Start with
   `stack-cpu-only.example.yml`, merged into your ordinary provider-specific
   vars. It deliberately sets `suse_ai_factory.enabled=false`: this lab must
   install AIF from Harbor, not let the connected stack pre-install it. A
   practical AWS starting point is one
   `m6i.2xlarge` management control plane and one `m6i.xlarge` downstream
   control plane. The services VM needs at least 4 vCPU, 12 GiB RAM and 80 GiB
   disk for the core disposable lab. The optional NVIDIA/vendor bundle can be
   much larger; size the seed, transfer media, services disk, and
   `harbor_registry_storage_size` from an actual export (start around 250 GiB,
   then retain headroom) rather than assuming the core sizing.
2. Supply a third SUSE VM for `airgap_services`. The one-command AWS workflow
   provisions it automatically. For other providers it can be created with the same
   SLES/SLE Micro image, VPC, key, and security group as the stack. Local
   libvirt works equally well. Use private addresses between all three nodes.
3. Install Ansible collections and local tools on the seed/controller:

   ```console
   ansible-galaxy collection install -r airgap-lab/requirements.yml
   command -v ansible-playbook file helm skopeo yq sha256sum
   ```

4. Copy configuration outside version control and replace every placeholder:

   ```console
   mkdir -p airgap-lab/generated
   cp airgap-lab/inventory.example.yml airgap-lab/generated/inventory.yml
   cp airgap-lab/vars.example.yml airgap-lab/generated/vars.yml
   chmod 700 airgap-lab/generated
   chmod 600 airgap-lab/generated/*
   ```

   Prefer `ansible-vault encrypt airgap-lab/generated/vars.yml`. If encrypted,
   add your normal vault arguments to `play()` in a local copy of `run.sh` or
   invoke the playbooks directly.

5. Set `airgap_host_records` to private addresses. The configure playbook writes
   the records to node `/etc/hosts` and each RKE2 CoreDNS ConfigMap. The seed and
   browser still need equivalent local DNS or host records. On AWS, do not use
   the public IPs returned by the current stack.

## Run order

The gate closes after connected prerequisites are staged but before AIF is
installed. Each phase is idempotent unless noted.

```console
cd /path/to/suse-ai-stack

# Only for a fresh services VM; requires connected package/RKE2 endpoints.
airgap-lab/run.sh bootstrap-services

# Connected stage: install dependencies and create private Harbor projects/Git.
airgap-lab/run.sh services

# Set destination credentials without putting them in shell history if possible.
read -r -p 'Harbor user: ' HARBOR_USERNAME
read -r -s -p 'Harbor password: ' HARBOR_PASSWORD; printf '\n'
export HARBOR_USERNAME HARBOR_PASSWORD
export HARBOR_REGISTRY=harbor.airgap.test

# AppCo credentials are needed by the suse, chatbot and vendor profiles.
export APPCO_USERNAME APPCO_PASSWORD
# SUSE Registry credentials are needed by suse, chatbot and vendor profiles.
export SUSE_REGISTRY_USERNAME SUSE_REGISTRY_PASSWORD
export NGC_USERNAME NGC_PASSWORD
export DOCKERHUB_USERNAME DOCKERHUB_PASSWORD  # optional, avoids anonymous limits

# core: AIF only; suse (default): core + Qdrant and CPU Ollama Blueprints;
# chatbot: suse + Simple Chatbot chart/container closure;
# vendor: core + broader AppCo/SUSE/NVIDIA examples; all: every entry.
export AIF_AIRGAP_PROFILE=suse
airgap-lab/run.sh mirror

# Trust and node mirrors are connected-stage prerequisites. Close the actual
# egress gate before installing AIF, so the result proves disconnected install.
airgap-lab/run.sh configure
airgap-lab/run.sh isolate
airgap-lab/run.sh install
airgap-lab/run.sh discover-targets
airgap-lab/run.sh clean-catalog
airgap-lab/run.sh suse-apps
airgap-lab/run.sh verify
```

For a media-transfer workflow, run `mirror-export` on a connected seed, copy
the entire bundle directory across the transfer boundary, and run
`mirror-import` on a host that can reach Harbor. Import refuses a bundle whose
`SHA256SUMS` does not match. Set the same `AIF_AIRGAP_PROFILE` on both sides;
import rejects a profile mismatch. Use a unique `AIF_AIRGAP_BUNDLE` directory
for each artifact-manifest revision and profile rather than mixing releases.

To re-open egress, remove only the lab-owned nftables table:

```console
airgap-lab/run.sh restore
```

This does not flush or replace the host's other firewall tables.

## Install-mode matrix

Run the same gate twice by setting `AIF_AIRGAP_INSTALL_MODE` to `combined` and
`separate`. The one-command AWS workflow reuses the infrastructure and staged
artifacts while reconciling the UI ownership for the requested mode. A fresh
management cluster remains the strongest evidence for a pristine customer
installation; the in-place runs are the fast regression path.

| Mode | Operator chart | UI chart | Expected result |
|---|---|---|---|
| `combined` | Harbor via Helm CLI | Harbor via `InstallAIExtension` with secret refs and CA | both Ready |
| `separate` | Harbor via Helm CLI, auto-extension disabled | Harbor via Helm CLI with `standalone=true` | both Ready |

Record `helm list -A`, the `InstallAIExtension` status, pod image references,
and Harbor access logs for each run.

## Qualifying an AIF source checkout or pull request

The committed `core` profile uses published AIF artifacts. To test code that is
not released yet, build both containers and stage both charts from an exact,
clean AIF Git checkout while the seed is still connected:

```console
export AIF_SOURCE_DIR=/path/to/aif
airgap-lab/run.sh build-aif-source

export AIF_AIRGAP_MANIFEST="$PWD/airgap-lab/generated/artifacts-aif-source.yml"
export AIF_AIRGAP_BUNDLE="$PWD/airgap-lab/bundles/aif-$(git -C "$AIF_SOURCE_DIR" rev-parse --short=12 HEAD)"
AIF_AIRGAP_PROFILE=core airgap-lab/run.sh mirror
```

The build refuses tracked changes, stamps the source commit into the operator
binary and image labels, installs UI dependencies from the committed Yarn
lockfile inside a disposable Git-archive checkout, copies the source charts
under `generated/`, and emits a manifest that reads the locally built
single-platform images through Skopeo's Docker-daemon transport. A cached image
whose revision label differs from the requested commit is rebuilt automatically.
The source images use an immutable `<version>-<12-character-Git-commit>` tag,
so qualifying another commit always changes the Kubernetes pod template. The
exported bundle records the source commit, version, image tag, transport, and
exact image digests before Harbor import. Set both `aif_version` and
`aif_image_tag` in `generated/vars.yml` to the values printed by the build; the
AWS preparation workflow does this automatically.

Native chart-registry CA propagation (for example AIF PR `#200`) is the default.
Its equivalent explicit setting in `generated/vars.yml` is:

```yaml
aif_registry_ca_mode: settings
```

That mode writes `caBundleSecretRef` for each selected mirrored registry,
disables the lab's compatibility patch, verifies the three Fleet/Rancher Secret
copies generated for each selected registry, rotates the source CA without changing its
trust semantics, and requires every ClusterRepo to receive a new
`spec.forceUpdate`. The source CA and all copies are restored before
installation continues. A successful run in `workaround` mode is not evidence
for the native product implementation.
The `workaround` mode remains a diagnostic option. It no longer includes the
old smoke role's repeated credential patches during workload reconciliation;
use Settings-native CA propagation for application QA.

## Profiles and artifact completeness

`artifacts.yml` is an allow-list, not a best-effort chart scraper. Every image
has an exact reference and every chart has a version; export records the
resolved image digests and import requires those same digests. Add all images
rendered by the exact values used in a test; Helm's default render is not enough
to discover conditional images, hooks, operators, init containers or runtime
model downloaders. The import step preserves the source registry as a path.

After rendering each selected chart with the qualification values, catch
literal omissions before transfer with:

```console
helm template release ./chart -f qualification-values.yaml > rendered.yaml
airgap-lab/scripts/check-rendered-images.sh --profile chatbot rendered.yaml
```

The dedicated chatbot check pulls the three pinned charts, renders their
defaults and the exact `Simple Chatbot with RAG` 1.0.2 values from the selected
AIF checkout, and requires every chart and literal image to be in the `chatbot`
profile. The one-command workflow runs it automatically before export:

```console
AIF_SOURCE_DIR=/path/to/aif airgap-lab/scripts/check-chatbot-container-closure.sh
```

The chatbot profile covers chart defaults and Blueprint containers, including
Redis, Helm test hooks and Open WebUI's embedded Ollama. Runtime network
downloads still need separate artifacts: the Ollama model and the MCP npm
package need an offline product-owned bootstrap contract before this lab can
assert a healthy RAG conversation. The broader vendor entries remain a starting set rather than
a release BOM; AppCo/NGC entitlements and the exact values determine additional
conditional images and model artifacts.

```text
registry.suse.com/bci/bci-busybox:15.7
  -> harbor.airgap.test/aif-images/registry.suse.com/bci/bci-busybox:15.7
```

The matching RKE2 rewrite lets the Kubernetes manifest retain the original
reference while containerd can only reach Harbor. `ARTIFACTS.yaml`, tool
metadata and source digests travel inside the checksummed bundle, so an import
does not depend on a mutable manifest left on the connected seed.

The first-pass bundle uses Skopeo's directory transport so Docker/OCI media
types, multi-architecture indexes, manifest digests, and any
containers/image-format source signature files survive media transfer. Harbor's
registry transport cannot publish those simple-signature files, so import keeps
them in the checksummed bundle while removing them from the registry copy. The
lab proves file integrity and source/destination manifest digest equality, but
does **not** verify signatures or qualify referrer attestations, provenance, or
SBOM transfer; those remain part of AG-001's release-owned mirroring
requirement.

NVIDIA's `vendor` profile is an optional transfer inventory, not a complete
NIM/model bundle. The default `suse` profile leaves the NVIDIA catalog disabled.
The [NVIDIA RAG deployment guide](https://docs.nvidia.com/rag/latest/deploy-helm.html)
budgets approximately 20–30 GB for containers, 100–150 GB for model caches,
and at least 200 GB per NIM node. The local minimal RAG Blueprint still needs a
GPU and additional operator/model artifacts. GPU node configuration prepares
infrastructure; it does not automatically deploy or qualify a NVIDIA Blueprint.
We keep those large workloads out of the default QA setup.

### Ollama, Open WebUI and Open WebUI MCPO

Use the `chatbot` profile to make these SUSE Application Collection applications
available in Harbor and through each target node's containerd mirror:

```console
AIF_AIRGAP_PROFILE=chatbot ./setup_airgap_lab.sh
```

| Application | Chart version | Mirrored container tags |
| --- | --- | --- |
| Ollama | `1.55.0` | `0.21.2-11.48`; `0.12.9-11.15` for Open WebUI's bundled Ollama |
| Open WebUI | `8.19.1` | `0.6.41-15.2` for the Blueprint; `0.6.41-14.20` for chart defaults |
| Open WebUI MCPO | `1.0.2` | `0.0.17-2.18` |

Redis `8.4.0-2.1` and the charts' BusyBox test image are included. Images keep
their original `dp.apps.rancher.io/containers/...` references in Kubernetes;
containerd resolves them through
`harbor.airgap.test/aif-images/dp.apps.rancher.io/containers/...` with upstream
fallback disabled. Charts are published under `oci://harbor.airgap.test/aif-appco`.

To extend an existing lab, use the manual source credentials described above
(`APPCO_USERNAME` and `APPCO_PASSWORD`), then export and import a new bundle:

```console
airgap-lab/run.sh build-aif-source
export AIF_AIRGAP_PROFILE=chatbot
export AIF_AIRGAP_MANIFEST="$PWD/airgap-lab/generated/artifacts-aif-source.yml"
export AIF_AIRGAP_BUNDLE="$PWD/airgap-lab/bundles/chatbot-$(date -u +%Y%m%dT%H%M%SZ)"
airgap-lab/run.sh mirror-export
airgap-lab/run.sh transfer-import
airgap-lab/run.sh verify
```

Import refreshes existing Rancher catalogs so the newly mirrored charts appear
in AI Factory. Verification pulls every application image with `crictl` on each
isolated RKE2 node and records the results in the node evidence. These phases
populate the mirrors; deploy the applications from AI Factory when needed.
Models, embedding data and MCP packages still require the offline preparation
described above.

### Qdrant and CPU Ollama test Blueprints

The default `suse` profile installs two custom Blueprints for testing real SUSE application
images without GPUs, model downloads or runtime package installation:

| Blueprint | Chart source and version | Container image |
| --- | --- | --- |
| Qdrant from SUSE Registry (air-gap lab) | `registry.suse.com/ai/charts/qdrant:1.19.0` | `registry.suse.com/ai/containers/qdrant:v1.19.0` |
| Ollama from SUSE Application Collection (air-gap lab) | `dp.apps.rancher.io/charts/ollama:1.55.0` | `dp.apps.rancher.io/containers/ollama:0.21.2-11.48` |

Qdrant's custom values pin its Helm test image to
`registry.suse.com/bci/bci-base:15.7`, which is also mirrored. Ollama's upstream
Docker Hub test hook is disabled; the lab checks its API directly. Both
Blueprints request a 2 GiB volume using the target cluster's default storage
class. Qdrant GPU indexing and telemetry are disabled, and Ollama starts without
pulling, creating or running a model.

The lab configures local-path storage helpers to use the mirrored
`registry.suse.com/bci/bci-busybox:15.7` image, so creating a new persistent volume
after isolation does not require Docker Hub. The `suse-apps` phase also applies
this setting when extending an existing lab.

These artifacts are included in `chatbot`, `vendor` and `all` as well. Qdrant
requires SUSE Registry access. The one-command runner reads
`suse_ai_registration_code` from the ignored `extra_vars.yml` and uses the
`regcode` username; `SUSE_REGISTRY_USERNAME` and `SUSE_REGISTRY_PASSWORD` override
those values. It also reads the existing AppCo email/token for Ollama.

Default bundle directories and source/qualification checkpoints include the
artifact-manifest revision. Adding Qdrant or changing an image pin therefore
creates a new bundle and reruns qualification while retaining the lab's
infrastructure checkpoints. An explicit `AIF_AIRGAP_BUNDLE` must also point to a
fresh directory when the manifest changes.

For a complete lab run:

```console
AIF_AIRGAP_PROFILE=suse ./setup_airgap_lab.sh
```

The runner publishes the versioned Blueprint files from `fixtures/blueprints/`
to private Gitea's `blueprints/` directory. Fleet delivers them to AI Factory.
Their stable `suse-ai-registry` and `application-collection` references resolve
to the mirrored charts in Harbor; containerd resolves their original container
references through the existing private registry rewrites.

To extend a running lab, export `APPCO_USERNAME`/`APPCO_PASSWORD` and
`SUSE_REGISTRY_USERNAME`/`SUSE_REGISTRY_PASSWORD` as described in the manual
mirroring workflow, then run:

```console
airgap-lab/run.sh build-aif-source
export AIF_AIRGAP_PROFILE=suse
export AIF_AIRGAP_MANIFEST="$PWD/airgap-lab/generated/artifacts-aif-source.yml"
export AIF_AIRGAP_BUNDLE="$PWD/airgap-lab/bundles/suse-$(date -u +%Y%m%dT%H%M%SZ)"
airgap-lab/scripts/check-suse-container-closure.sh --manifest "$AIF_AIRGAP_MANIFEST"
airgap-lab/run.sh mirror-export
airgap-lab/run.sh transfer-import
airgap-lab/run.sh discover-targets
airgap-lab/run.sh suse-apps
airgap-lab/run.sh verify
```

Use `airgap-lab/run.sh suse-blueprints` to publish the Blueprint cards for manual
UI tests without creating workloads. `suse-apps` deploys both applications to
`suse_apps_target_clusters` (the discovered local and downstream targets by
default), waits for every target to report Running, and tests Qdrant vector
insertion/search and Ollama's version/model-list APIs while isolation is active.
The Qdrant probe removes its uniquely named test collection afterward. Redacted
results and pod image IDs are saved in `generated/suse-apps-<host>.txt`.
Set `suse_apps_strategy: GitOps` in the lab vars to exercise that deployment path.
Ollama inference still requires separately imported models.

The [catalog cleanup and GPU configuration validation](validation/mirrored-apps-gpu-config-2026-09-09.md)
records the current workflow. The earlier
[2026-09-09 AWS validation](validation/suse-apps-2026-09-09.md) records
successful deployment and API tests on both isolated clusters, plus the
storage-helper correction found during the run.

The custom Blueprint closure check can also use only exported charts:

```console
airgap-lab/scripts/check-suse-container-closure.sh \
  --manifest "$AIF_AIRGAP_BUNDLE/ARTIFACTS.yaml" \
  --charts-dir "$AIF_AIRGAP_BUNDLE/charts"
```

This check covers the custom Blueprint values, including Qdrant's pinned test
hook and init containers. It does not use the unmodified charts' test defaults.
The Qdrant chart location follows the
[SUSE AI installation documentation](https://documentation.suse.com/suse-ai/1.0/html/AI-deployment/ai-library-installing.html).

## Secure private Git baseline

The qualified path uses authenticated, private-CA HTTPS Gitea. AIF loads the
CA Secret into its Git client and writes the same PEM bundle to Fleet's
`GitRepo`. The repository's `blueprints/` directory delivers the two custom
Blueprints with stable `chartRepo` references. Its `workloads/` directory
carries AIF-generated Fleet resources when `suse_apps_strategy: GitOps` is used.
The default deployment strategy is `FleetBundle`.

`clean-catalog` migrates older labs: it removes only the labeled synthetic
AIWorkloads/Blueprints, their known active Git manifests and orphaned Fleet
resources, the lab's old Gitea smoke-chart catalog, and the `airgap-smoke` chart
repositories in Harbor. It keeps real applications, PVCs, user-created
Blueprints, Git history, and archived branches. `install` sets
`defaultBlueprints.enabled: false`, so Helm removes its bundled Blueprint
cards; the private Git source supplies only the mirrored custom cards.
Infrastructure probes save their evidence and remove the successful probe pod.

For an existing lab whose SUSE images are already mirrored:

```console
./setup_airgap_lab.sh --prepare-only
airgap-lab/run.sh install
airgap-lab/run.sh discover-targets
airgap-lab/run.sh clean-catalog
airgap-lab/run.sh suse-apps
airgap-lab/run.sh verify
```

The historical smoke matrix remains documented in earlier validation reports;
it is no longer created by the normal setup. Set
`AIF_AIRGAP_GITEA_TLS=false` only to diagnose an HTTP compatibility path.

## Rancher extension browser check

From an isolated client in `airgap_clients`, open AI Factory Settings and
confirm that each private chart endpoint appears in its corresponding
Application Collection, SUSE Registry, or NVIDIA section. There must be no
Advanced endpoint section and no Application Collection catalog-API field.
Then open Apps and Blueprints, inspect the Qdrant and Ollama deployments, and retain a
browser network trace proving that catalogs, logos, and installation do not
request public hosts. This remains a short manual check because the Ansible
suite intentionally validates Kubernetes state rather than Rancher page
layout.

## Evidence to retain

- the exact `artifacts.yml`, `SHA256SUMS`, source/destination digest report and
  AIF chart versions;
- `registries.yaml` redacted, RKE2 config flag and containerd logs;
- nftables rules and counters from each isolated node;
- Harbor project/audit logs and Gitea commit history;
- the exact four AIF CRDs, AIF Settings, ClusterRepo conditions, HelmOps,
  Bundles, GitRepo status, AIWorkload status and relevant pod events;
- browser network trace from a client VM in `airgap_clients`.

The corresponding product assessment and detailed journey matrix live in the
AIF repository under `docs/air-gap/`. The provider/VM firewall contract is in
[`network-rules.md`](network-rules.md).
