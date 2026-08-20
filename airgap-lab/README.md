# SUSE AI Factory air-gap lab

This directory is a post-provisioning overlay for `suse-ai-stack`. It creates a
repeatable, GPU-free test environment for AI Factory's control plane and its
dependencies. It does not claim that a workload containing a model or a GPU
runtime is healthy; it proves chart discovery, authentication, TLS trust,
artifact redirection, AIF installation, Fleet, GitOps, blueprints, and failure
without public egress.

## Topology and trust boundary

```text
connected seed/controller
  |  export/import (only before the gate closes)
  v
services RKE2 cluster/VM
  |- Harbor (private projects, TLS, authentication)
  `- Gitea (authentication; HTTP baseline or private-CA HTTPS gap test)
            ^                         ^
            | private CIDRs only      | private CIDRs only
management RKE2                 downstream RKE2
Rancher + AIF                   CPU-only workload target
```

The services node is intentionally not part of `airgap_isolated`: Harbor is not
configured as a pull-through cache, and Gitea has no proxy role, so it cannot
provide an escape path. Keeping it connected avoids the registry-bootstrap
chicken-and-egg problem and lets it be rebuilt. Management, workload, and
optional browser nodes receive both host-output and pod-forward nftables rules.

## What is automated

- a connected-stage, single-node, CPU-only RKE2 services cluster;
- Harbor 2.15.2 through chart 1.19.2, private projects, authentication and a
  generated lab CA;
- Gitea 1.27.0 through chart 12.7.0, a pre-initialized GitOps repository, and a
  low-footprint SQLite/standalone configuration, with a switchable private-CA
  HTTPS ingress;
- checksummed chart and multi-architecture image export/import with Skopeo and
  Helm (no `docker save`, no silent skips, no password-on-command-line login);
- RKE2 `registries.yaml` on every schedulable management/workload node, Harbor
  authentication/CA, per-source rewrites, and
  `disable-default-registry-endpoint: true`;
- AIF combined operator+UI or separate operator/UI installation from Harbor;
- Settings endpoints for mirrored AppCo, SUSE Registry and NVIDIA charts, plus
  the internal Gitea Fleet repository;
- a tiny CPU-only chart/Blueprint fixture for FleetBundle and GitOps paths;
- reversible egress denial and positive/negative verification probes.

## Prerequisites

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
2. Supply a third SUSE VM for `airgap_services`. It can be created with the same
   SLES/SLE Micro image, VPC, key, and security group as the stack. Local
   libvirt works equally well. Use private addresses between all three nodes.
3. Install Ansible collections and local tools on the seed/controller:

   ```console
   ansible-galaxy collection install -r airgap-lab/requirements.yml
   command -v ansible-playbook helm skopeo yq sha256sum
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

5. Make the names in `airgap_host_records` resolve to private addresses. The
   playbook writes `/etc/hosts` on lab nodes, but the seed and browser also need
   the records. On AWS, do not use the public IPs returned by the current stack.

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

# Optional source credentials for the vendor profile.
export APPCO_USERNAME APPCO_PASSWORD
export SUSE_REGISTRY_USERNAME SUSE_REGISTRY_PASSWORD
export NGC_USERNAME NGC_PASSWORD
export DOCKERHUB_USERNAME DOCKERHUB_PASSWORD  # optional, avoids anonymous limits

# Core is public AIF + the smoke fixture. "vendor" adds AppCo/SUSE/NVIDIA
# charts and an explicit default-rendered image set; it does not run GPU apps.
AIF_AIRGAP_PROFILE=core airgap-lab/run.sh mirror

# Trust and node mirrors are connected-stage prerequisites. Close the actual
# egress gate before installing AIF, so the result proves disconnected install.
airgap-lab/run.sh configure
airgap-lab/run.sh isolate
airgap-lab/run.sh install
airgap-lab/run.sh smoke
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

Run the same gate twice, changing `aif_install_mode` in the generated vars. Use
a fresh management cluster for each qualification run (preferred), or fully
remove the previous AIF operator/UI releases and `InstallAIExtension` resources
before changing modes; this lab does not treat an in-place mode conversion as
part of either installation journey.

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
binary and image labels, copies the source charts under `generated/`, and emits
a manifest that reads the locally built single-platform images through
Skopeo's Docker-daemon transport. The exported bundle records the source
commit, version, image transport, and exact image digests before Harbor import.
Set `aif_version` in `generated/vars.yml` to the version printed by the build;
the install role and source manifest must describe the same release.

When qualifying native chart-registry CA propagation (for example AIF PR
`#200`), also set this in `generated/vars.yml`:

```yaml
aif_registry_ca_mode: settings
```

That mode writes `caBundleSecretRef` for all three mirrored registry settings,
disables the lab's compatibility patch, verifies all nine generated Fleet/Rancher
Secret copies, rotates the source CA without changing its trust semantics, and
requires every ClusterRepo to receive a new `spec.forceUpdate`. The source CA
and all copies are restored before installation continues. A successful run in
`workaround` mode is not evidence for the native product implementation.

## Profiles and artifact completeness

`artifacts.yml` is an allow-list, not a best-effort chart scraper. Every image
has an exact reference and every chart has a version; export records the
resolved image digests and import requires those same digests. Add all images
rendered by the exact values used in a test; Helm's default render is not enough
to discover conditional images, hooks, operators, init containers or runtime
model downloaders. The import step preserves the source registry as a path:

After rendering each selected chart with the qualification values, catch
literal omissions before transfer with:

```console
helm template release ./chart -f qualification-values.yaml > rendered.yaml
airgap-lab/scripts/check-rendered-images.sh rendered.yaml
```

The committed vendor entries are a starting set for the pinned examples, not a
release BOM: AppCo/NGC entitlements and the exact values profile determine the
remaining conditional images and model artifacts.

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

NVIDIA's vendor profile mirrors charts but deliberately does not claim a GPU
application is runnable. The QA assertion is limited to catalog readiness,
chart pull, HelmOp/Git commit creation and secret shape. Full NIM/model testing
belongs in a GPU/model-cache suite.

## Secure Git expected-failure mode

The passing baseline uses authenticated HTTP Gitea because the current AIF Git
client cannot consume a private CA and the generated Fleet `GitRepo` omits its
CA bundle. To reproduce AG-003, set `gitea_tls_enabled: true`,
`smoke_strategy: GitOps`, and `smoke_expect_git_ca_failure: true`; rerun
`services` while connected, then execute `configure`, `isolate`, `install`, and
`smoke`. Harbor and node-level Gitea health checks remain green with the lab CA,
while the smoke role passes only after the AIF operator logs the expected
certificate-authority rejection. Do not enable insecure TLS to make the normal
GitOps path pass.

## Evidence to retain

- the exact `artifacts.yml`, `SHA256SUMS`, source/destination digest report and
  AIF chart versions;
- `registries.yaml` redacted, RKE2 config flag and containerd logs;
- nftables rules and counters from each isolated node;
- Harbor project/audit logs and Gitea commit history;
- AIF Settings, ClusterRepo conditions, HelmOps, Bundles, GitRepo status,
  AIWorkload status and relevant pod events;
- browser network trace from a client VM in `airgap_clients`.

The corresponding product assessment and detailed journey matrix live in the
AIF repository under `docs/air-gap/`. The provider/VM firewall contract is in
[`network-rules.md`](network-rules.md).
