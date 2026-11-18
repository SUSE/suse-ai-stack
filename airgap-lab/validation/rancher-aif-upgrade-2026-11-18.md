# Disconnected Rancher and AI Factory upgrade on AWS

On 18 November 2026, the management cluster in the `suseai-882-airgap`
workspace upgraded from Rancher 2.14.3 to 2.15.3 and from AI Factory 2.3.1 to
2.4.0. Management and downstream ran RKE2 `v1.34.4+rke2r1` on CPU nodes in
`us-west-2`. A third node hosted the private Harbor registry and Gitea.

## Release and network checks

The seed exported six charts and 41 images for the `suse` profile. The bundle
was 14.85 GiB. The services node verified the file checksums, imported the
artifacts and compared each registry image digest with its recorded source
digest. The artifact manifest SHA-256 was
`10e4fc35332e0b48a20082a835814b3a9a573589bf28a53ee8d5987ebcb06411`.

Both cluster hosts had containerd's upstream fallback disabled and the
nftables isolation service active before AIF 2.3.1 was installed. A TCP probe
from each host and a fresh pod on each cluster confirmed rejected public
egress. Both hosts reached Harbor over private TLS, and both pods reached its
private address.

| Installed component | Before | After |
| --- | --- | --- |
| Rancher | 2.14.3 | 2.15.3 |
| Fleet chart | 109.0.4+up0.15.4 | 110.0.3+up0.16.3 |
| Rancher webhook chart | 109.0.3+up0.10.7 | 110.0.4+up0.11.4 |
| AI Factory operator and UI | 2.3.1 | 2.4.0 |

Rancher, the AIF operator and the UI server ran images from Harbor. All five
AIF CRDs were established. Rancher's local cluster and the imported downstream
cluster both reported `Connected=True`. The downstream ran the Rancher
2.15.3 cluster agent, Fleet agent 0.16.3 and webhook 0.11.4 from Harbor, each
with one of one replicas ready.

## Application continuity

Before the upgrade, private Gitea supplied the two Blueprints. AI Factory
deployed Qdrant 1.19.0 and Ollama 0.21.2 on both targets. The lab verified
Qdrant vector writes and searches and Ollama's version and model-list APIs.
One additional Qdrant point was written on each cluster before the upgrade
and successfully queried on each cluster afterward.

Both AIWorkloads retained their UIDs. On each cluster the Qdrant StatefulSet,
the Ollama Deployment and both bound persistent volume claims retained their
UIDs. The volume claims remained bound to the same persistent volumes.

## Extension delivery and access

In combined mode, the operator reconciled `InstallAIExtension/aif-ui` and
Rancher cached the 2.4.0 plugin. In separate mode, Helm installed
`aif-ui-server` from Harbor and `aif-ui` from the standalone server's
in-cluster chart endpoint. The operator-managed extension resource was absent
in separate mode. Both modes passed the private registry CA rotation check and
the Qdrant and Ollama API probes on both targets.

The final run restored combined mode with the operator-managed extension
Ready and the UI cached. A fresh pod on each target still reached the private
service and was denied public TCP. Both original Qdrant points were read
again and the temporary test collections were removed.

The Rancher ingress served `/ping` and `/dashboard/` over verified TLS.
The private extension catalog served its index, chart archive, logo and
2.4.0 JavaScript bundle with HTTP 200. The interactive browser reached the
Rancher first-login screen. The in-dashboard walkthrough requires the lab
owner to complete first sign-in.

The ignored `airgap-lab/generated/evidence/` directory contains the node
probes, separate and combined control-plane reports, release snapshots and
media checksums. The verified transfer bundle is available on the services
node at
`/var/lib/aif-airgap-lab/bundles/aif-release-2.4.0-suse-10e4fc35332e`.
