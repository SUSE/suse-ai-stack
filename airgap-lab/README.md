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
  `- Gitea (private-CA HTTPS and authentication)
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

## One-command AWS lab

For the repository's normal AWS workflow, keep the provider, SCC and vendor
credentials in the ignored top-level `extra_vars.yml`, then run:

```console
./setup_airgap_lab.sh
```

The command creates three CPU-only nodes, installs Rancher/RKE2, Harbor and
Gitea, builds the exact sibling AIF checkout, transfers the checksummed selected
bundle, applies the network gate, and runs the FleetBundle/GitOps single- and
multi-cluster matrix. It is resumable: completed phases have ignored markers
under `airgap-lab/generated/state/`, so run the same command after correcting a
failure. Useful lifecycle commands are:

```console
./setup_airgap_lab.sh --prepare-only  # validate and render; no AWS writes
./setup_airgap_lab.sh --status
./setup_airgap_lab.sh --reset-progress # retain resources, reconcile all phases
./destroy_airgap_lab.sh                # guarded dedicated-workspace destroy
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
switching an axis always forces installation, matrix and verification to run
again; changing Gitea transport also reconciles the services phase. Switching
back to combined mode removes the standalone UI release before reconciling the
operator-managed extension. A `workaround` or HTTP pass remains useful for
diagnosis, but is not native air-gap evidence.

For one-command `chatbot`, `vendor`, or `all` runs, the setup script reads the
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

## What is automated

- a connected-stage, single-node, CPU-only RKE2 services cluster;
- Harbor 2.15.2 through chart 1.19.2, private projects, authentication and a
  generated lab CA;
- Gitea 1.27.0 through chart 12.7.0, separate private repositories for
  Blueprint/GitOps resources and Helm charts, and a low-footprint
  SQLite/standalone configuration, with a switchable private-CA HTTPS ingress;
- checksummed chart and multi-architecture image export/import with Skopeo and
  Helm (no `docker save`, no silent skips, no password-on-command-line login);
- RKE2 `registries.yaml` on every schedulable management/workload node, Harbor
  authentication/CA, per-source rewrites, and
  `disable-default-registry-endpoint: true`;
- one managed CoreDNS `hosts` block per RKE2 cluster for Harbor, Gitea and the
  private Rancher endpoint, including consolidation of the base stack's Rancher
  record;
- AIF combined operator+UI or separate operator/UI installation from Harbor;
- Settings endpoints for mirrored AppCo, SUSE Registry and NVIDIA charts, plus
  the internal Gitea Fleet repository and Rancher catalog credential;
- an authenticated Rancher `ClusterRepo` that indexes the private Gitea Helm
  repository with its private CA;
- a tiny CPU-only chart/Blueprint fixture for FleetBundle and GitOps paths;
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

# AppCo credentials are needed by the chatbot and vendor profiles.
export APPCO_USERNAME APPCO_PASSWORD
# The remaining source credentials are vendor-profile inputs.
export SUSE_REGISTRY_USERNAME SUSE_REGISTRY_PASSWORD
export NGC_USERNAME NGC_PASSWORD
export DOCKERHUB_USERNAME DOCKERHUB_PASSWORD  # optional, avoids anonymous limits

# core: AIF + smoke; chatbot: core + Simple Chatbot chart/container closure;
# vendor: core + broader AppCo/SUSE/NVIDIA examples; all: every entry.
export AIF_AIRGAP_PROFILE=chatbot
airgap-lab/run.sh mirror

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

That mode writes `caBundleSecretRef` for all three mirrored registry settings,
disables the lab's compatibility patch, verifies the three Fleet/Rancher Secret
copies generated for each registry, rotates the source CA without changing its
trust semantics, and requires every ClusterRepo to receive a new
`spec.forceUpdate`. The source CA and all copies are restored before
installation continues. A successful run in `workaround` mode is not evidence
for the native product implementation.
In compatibility mode, AIF rewrites the generated auth Secrets while creating
each AIWorkload; the smoke role therefore reapplies the CA after its HelmOp
appears and requires Fleet to accept the retried HelmOp. That timing-dependent
lab action is another reason a workaround pass must not be reported as native
product support.

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
airgap-lab/scripts/check-rendered-images.sh --profile chatbot rendered.yaml
```

The dedicated chatbot check pulls the three pinned charts, renders the exact
`Simple Chatbot with RAG` 1.0.2 values from the selected AIF checkout, and
requires every chart and literal image to be in the `chatbot` profile. The
one-command workflow runs it automatically before export:

```console
AIF_SOURCE_DIR=/path/to/aif airgap-lab/scripts/check-chatbot-container-closure.sh
```

The chatbot profile is a complete chart/container closure, including Redis and
Helm test hooks. It intentionally cannot turn runtime network downloads into
container artifacts: the Ollama model and the MCP npm package still need an
offline product-owned bootstrap contract before this lab can assert a healthy
RAG conversation. The broader vendor entries remain a starting set rather than
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

NVIDIA's vendor profile mirrors charts but deliberately does not claim a GPU
application is runnable. The QA assertion is limited to catalog readiness,
chart pull, HelmOp/Git commit creation and secret shape. Full NIM/model testing
belongs in a GPU/model-cache suite.

## Secure private Git baseline

The qualified path uses authenticated, private-CA HTTPS Gitea. One Fleet
setting references the CA Secret; AIF loads it into go-git and the Settings
controller writes the same PEM bundle to the generated Fleet `GitRepo`. The
matrix requires the unified username plus password/PAT configuration, proves
that AIF mirrors it to Fleet as `kubernetes.io/basic-auth`, and performs real
Git writes without an auth-type selector. It also moves the same `GitRepo` to a
clean alternate branch, requires AIF to republish the unchanged GitOps manifest
there, and restores `main`. The repository's `blueprints/` path delivers
Blueprint CRs with direct, stable `chartRepo` references while `workloads/`
carries AIF-generated Fleet resources. Insecure TLS is never used.

A separate private Gitea repository is also a Helm chart source. Rancher clones
it with a `ClusterRepo` credential and private CA, while AIF uses a Rancher API
token stored only in its namespace to retrieve the indexed chart archive. The
lab token inherits the lab administrator's access and lasts for the disposable
environment; a production installation must define least-privilege access,
expiry, rotation, and revocation for that credential.

The acceptance matrix contains seven deployments: direct Blueprints through
both FleetBundle and GitOps on local and downstream targets; a Blueprint
delivered from private Git; and a private-Gitea-backed chart through both
strategies. It covers the unified Git HTTPS credential path, branch-change
republication, and an in-place change of the `application-collection`
ClusterRepo endpoint while requiring its UID and the Blueprint spec to remain
unchanged. The final two cases embed the git-backed chart in Bundles in both
Fleet workspaces, proving that the workload no longer depends on Gitea at
install time.

Each rendered matrix Blueprint and AIWorkload now shares a unique case-specific
display name. One example is
`AI Factory air-gap smoke (airgap-smoke-single-fleetbundle)`. Verification rejects
duplicate fixture names and proves that every rendered workload references the
matching Blueprint family and version.

These checks keep the environment and operator responsibilities separate.
RKE2's registry mirror configuration redirects container image pulls; AIF
Settings and Rancher's existing `ClusterRepo`/Fleet resources select private
chart, Blueprint, and Git sources. The lab qualifies both contracts without
making either one a substitute for the other.

Set `AIF_AIRGAP_GITEA_TLS=false` only to diagnose an HTTP compatibility path;
that result is not accepted as release evidence.

## Rancher extension browser check

From an isolated client in `airgap_clients`, open AI Factory Settings and
confirm that each private chart endpoint appears in its corresponding
Application Collection, SUSE Registry, or NVIDIA section. There must be no
Advanced endpoint section and no Application Collection catalog-API field.
Then open Apps and Blueprints, deploy the `airgap-smoke` fixture, and retain a
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
