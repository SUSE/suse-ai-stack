# Require the old lab identity AND the synthetic chart/reference. User-created
# objects and real SUSE applications must survive this migration.
def legacy_name:
  test("^airgap-(smoke(-single|-multi)?|blueprint-source|git-chart-multi)-(fleetbundle|gitops)(-airgap-smoke)?$");
.items |= map(select(
  if .kind == "AIWorkload" then
    (.metadata.name | legacy_name) and
    (.metadata.labels["airgap-lab.suse.com/source"] | IN("rendered-matrix", "preprovisioned-matrix")) and
    (.spec.source.blueprint.name | . == "git-sourced-airgap" or legacy_name)
  elif .kind == "Blueprint" then
    (.metadata.labels["airgap-lab.suse.com/source"] | IN("rendered-matrix", "private-gitea")) and
    (.spec.components | length > 0 and all(.chartName == "airgap-smoke"))
  elif .kind == "HelmOp" or .kind == "Bundle" then
    (.metadata.name | legacy_name) and
    (.spec.helm.chart == "airgap-smoke" or
     any(.spec.resources[]?; .name == "airgap-smoke/Chart.yaml"))
  else false end
))
