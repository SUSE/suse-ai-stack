SUSE Private AI Stack
---
Lightweight virtualized private AI stack.

Please refer to https://apps.rancher.io/stacks/suse-ai for the official published charts.

This repo is intended to bring up AI components for demo and development purposes only.

At it's core, the stack is consist of the following:

* [SUSE Linux Enterprise Server][sles] 15SP6 virtual machine (VM) 
* [Rancher RKE2][rke2] Kubernetes distribution
* [Rancher Prime][rancher-prime] Kubernetes manager
* [Ollama][ollama] [LLM][llm] platform
* [Open WebUI][open-webui], front-end for [Ollama][ollama]
* [Milvus][milvus], Vector DB for AI stack

The stack is self-contained, designed to run on a local environment. However,
it can also be running in AWS if the local environment lacks the required
hardware resource.

For information on how to setup the Private AI stack on the local environment,
please see [Local Setup](./docs/Local_Setup.md).

For information on how to setup the Private AI stack on the local environment,
please see [AWS Setup](./docs/AWS_Setup.md).

[aws]: https://aws.amazon.com/
[aws-console]: https://aws.amazon.com/console/
[llm]: https://en.wikipedia.org/wiki/Large_language_model
[ollama]: https://ollama.com/
[open-webui]: https://github.com/open-webui/open-webui
[rancher-prime]: https://www.rancher.com/products/rancher-platform
[rke2]: https://www.rancher.com/products/secure-kubernetes-distribution
[sles]: https://www.suse.com/products/server/
