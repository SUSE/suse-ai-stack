# Mirrored application QA and GPU configuration — 2026-09-09

The updated `suse` workflow passed against the existing three-node AWS lab.
It now presents two real mirrored Blueprints and two healthy AIWorkloads:
SUSE Registry Qdrant and SUSE Application Collection Ollama. The run retained
the existing CPU topology; no GPU instances were provisioned.

## Live results

- AIF source: `de4819a41d2d98cd878438e60c5dd64c3d78257c`.
- Operator/UI tag: `2.2.0-rc.1-de4819a41d2d`.
- Revised bundle: `aif-de4819a41d2d-suse-a3870026eba9`.
- Standalone UI, Settings-native CA trust, and authenticated HTTPS Git.
- Checksummed export, private transfer, and Harbor import passed.
- The seven synthetic Blueprint resources and three Harbor `airgap-smoke`
  chart repositories were retired. The active Git fixture and its private
  Gitea chart catalog were removed. Helm removed its bundled Blueprint cards.
- Only `appco-ollama-airgap-0-1-0` and `suse-qdrant-airgap-0-1-0` remained in
  the Blueprint list. Both corresponding AIWorkloads reported Running on
  `local` and downstream `c-bktbn`.
- Qdrant vector insertion/search and Ollama version/model-list API probes
  passed on both targets. Their image IDs match the earlier
  [application validation](suse-apps-2026-09-09.md).
- All four existing application PVCs retained their UIDs and remained Bound.
- Both nodes pulled the selected application images through Harbor. Public
  host and pod TCP probes were rejected while private services stayed reachable.
- The successful infrastructure probe pod was removed after evidence capture.

The RKE2 API load-balancer names were added to the lab's private host/DNS
records. Both names resolved to the corresponding private control-plane IPs.
`kubectl` read nodes through those original API hostnames with normal TLS
verification and the isolation services still active. Reapplying the DNS
configuration made no changes.

## Configuration validation

Ten offline regression tests passed. They cover CPU defaults, GPU opt-in,
invalid node settings, preserved credentials and target migration, the original
stack's GPU flag behavior, topology checkpoint keys, worker inventory coverage,
private API name generation, GPU image collection, CPU-only verification, and
preservation of real/user-owned resources during fixture selection.

Bash/ShellCheck and Ansible syntax checks passed. The Settings template rendered
valid catalog selections for `core`, `suse`, `chatbot`, `vendor`, and `all`.
The custom SUSE Blueprint chart/container closure check passed. GPU image
collection was also checked against the actual GPU Operator `v25.10.1` chart,
including its CUDA validator image and exclusion of the disabled driver image.

The optional GPU configuration reuses the original stack's connected driver
and GPU Operator installation paths, then captures and mirrors enabled runtime
images before isolation. This run validates configuration and orchestration;
GPU hardware installation and GPU workloads were not exercised. NVIDIA
Blueprints and model caches remain outside the default QA profile.

## Retained evidence

Detailed output remains in ignored files under `airgap-lab/generated/`:

- `qa-gpu-config-20260909-resume.log` and `qa-gpu-config-20260909-final.log`;
- `qa-catalog-after-cleanup.txt`;
- `qa-pvcs-before-cleanup.txt` and `qa-pvcs-after-cleanup.txt`;
- `suse-apps-mgmt-rancher.txt` and `suse-apps-suse-ai.txt`;
- `qa-private-api-dns-retry.log` and `qa-private-api-check-retry.log`;
- the node and management files under `evidence/`.

Setup logs include the requested UI credentials and are kept out of Git.
