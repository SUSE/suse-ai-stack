# Validators can delete their successful CUDA pods before this inventory runs.
# Include their image contract from ClusterPolicy as well as actual workloads.
# Do not turn disabled driver/sandbox features into unrelated large downloads.
[.[] | .items[] |
  if .kind == "ClusterPolicy" then
    (.spec.operator.initContainer, .spec.validator) |
    select(.repository != null and .image != null and .version != null) |
    .repository + "/" + .image + ":" + .version
  else .spec | .. | objects | (.containers[]?.image, .initContainers[]?.image)
  end] | unique |
if length == 0 then error("No GPU component images found") else . end |
map(
  . as $image |
  if test("^(nvcr.io|registry.k8s.io|docker.io|ghcr.io|quay.io|registry.suse.com)/.+(:[^/]+|@sha256:[a-f0-9]{64})$") | not
    then error("GPU image needs an explicit supported registry and tag/digest: " + $image) else . end |
  {
    id: ("gpu-" + (. | gsub("[^a-zA-Z0-9]"; "-"))),
    profiles: ["core"], source: $image,
    bundlePath: ((. | gsub("[^a-zA-Z0-9_.-]"; "_")) + ".dir"),
    target: ("aif-images/" + (split("@") as $ref |
      if $ref | length == 1 then $ref[0]
      elif $ref[0] | test(":[^/]+$") then $ref[0]
      else $ref[0] + ":" + ($ref[1] | sub(":"; "-")) end))
  }) |
{apiVersion: "airgap.ai-factory.suse.com/v1alpha1", kind: "ArtifactSet",
 metadata: {name: "aif-gpu-runtime"}, spec: {charts: [], images: .}}
