# AI Factory follow-ups

The lab now gives every smoke Blueprint/AIWorkload pair a unique display name and
provides a `chatbot` profile containing the exact charts and rendered container
images for `Simple Chatbot with RAG` 1.0.2. The following work belongs in AI
Factory.

## Blueprint workload visibility

- Resolve `AIWorkload.spec.source.blueprint` to the Blueprint display name and
  make the name/version a link.
- Show workload count and health for the selected version on Blueprint cards and
  list those workloads in Blueprint details.
- Reuse the existing family/version reference; no CRD change is required.

## Availability before install

- Check every component chart/version and required cluster capability before
  enabling **Install**.
- Mark unavailable Blueprints with an actionable reason instead of creating a
  workload that can only fail later.

## Offline Simple Chatbot with RAG

- Replace runtime downloads with a release-owned offline contract for the Ollama
  model, embedding/NLTK data, and MCP npm package.
- Publish an exact, licensed artifact manifest and configurable preload/cache
  mechanism; do not depend on public fallback.
- Under denied public egress, require all pods Ready, a successful model request,
  document ingestion, and a grounded RAG response.
