# MUST: The platform must prove that at least one complex AI operator with a CRD (e.g., Ray, Kubeflow) can be installed and functions reliably. This includes verifying that the operator's pods run correctly, its webhooks are operational, and its custom resources can be reconciled.

**Test 1 (Simple): Deploy Ollama Inference engine via operator**

**Step 1: Setup SUSE AI Test Environment**

- Note 1: You can use the automated setup available at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) to spin up a SUSE AI instance.
- Note 2: The setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.
- Note 2: the default ingress must be disabled by setting `ingress-controller: none` on the `/etc/rancher/rke2/config.yaml` file.

**Step 2: Install and verify Ollama via the community operator** **([https://ollama-operator.ayaka.io/pages/en/](https://ollama-operator.ayaka.io/pages/en/) )**

1. Install operator.

```
kubectl apply \
  --server-side=true \
  -f https://raw.githubusercontent.com/nekomeowww/ollama-operator/v0.10.1/dist/install.yaml
```

2. Wait for the operator to be ready:

```
kubectl wait \
   -n ollama-operator-system \
  --for=jsonpath='{.status.readyReplicas}'=1 deployment/ollama-operator-controller-manager
```

3. Deploy a sample model

```
kubectl apply -f - <<'YAML'
apiVersion: ollama.ayaka.io/v1
kind: Model
metadata:
  name: phi
spec:
  image: phi
  storageClassName: local-path
YAML
```

4. Wait for the ollama pods to come up

```
$ kubectl get pods
NAME                                READY   STATUS    RESTARTS   AGE
ollama-model-phi-7cd69569f7-pq9gl   1/1     Running   0          153m
ollama-models-store-0               1/1     Running   0          155m
```

5. Verify ollama CRD is created

```
$ kubectl get crd | grep -i ollama
models.ollama.ayaka.io                      2025-10-06T21:57:57Z
```

6. Forward the port of the model service

```
$ kubectl port-forward svc/ollama-model-phi 11434:11434
```

7. Verify model access

```
$ curl http://localhost:11434/v1/chat/completions -H "Content-Type: application/json" -d '{
  "model": "phi",
  "messages": [
      {
          "role": "user",
          "content": "Hello!"
      }
  ]
}'
{"id":"chatcmpl-521","object":"chat.completion","created":1759798204,"model":"phi","system_fingerprint":"fp_ollama","choices":[{"index":0,"message":{"role":"assistant","content":" Hey there! How can I assist you today? Let me know if there's anything I can help you with. \n\n"},"finish_reason":"stop"}],"usage":{"prompt_tokens":34,"completion_tokens":28,"total_tokens":62}}
```

**Test 2: Deploy Kserve Inference**

**Step 1: Setup SUSE AI Test Environment**

Setup an end to end SUSE AI instance on AWS using the automated setup at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack)

Note that the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

**Step 2: Deply a LLM from Huggingface on Kserve**

1. Install KServe Quickstart Environment. This is the same script as [quick_install.sh](https://raw.githubusercontent.com/kserve/kserve/release-0.15/hack/quick_install.sh) from [Kserve docs](https://kserve.github.io/website/docs/getting-started/quickstart-guide) slightly tweaked to get it working on top of suse-ai-stack.

```
./kserve/quickstart.sh
```

2. Deploy the InferenceService

```
kubectl apply -f ./kserve/qwen-kserve.yaml
```

3. Check InferenceService status

```
> kubectl get pods
NAME                                                   READY   STATUS    RESTARTS   AGE
qwen-llm-predictor-00001-deployment-677c496c9b-vhcch   2/2     Running   0          3m37s

> kubectl get inferenceservice qwen-llm
NAME       URL                                   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION        AGE
qwen-llm   http://qwen-llm.default.example.com   True           100                              qwen-llm-predictor-00001   3m51s
```

4. Verify Kserve CRDs are created

```
> kubectl get crd | grep -i kserve
clusterservingruntimes.serving.kserve.io                          2026-02-13T14:48:14Z
clusterstoragecontainers.serving.kserve.io                        2026-02-13T14:48:14Z
inferencegraphs.serving.kserve.io                                 2026-02-13T14:48:14Z
inferenceservices.serving.kserve.io                               2026-02-13T14:48:14Z
localmodelcaches.serving.kserve.io                                2026-02-13T14:48:14Z
localmodelnodegroups.serving.kserve.io                            2026-02-13T14:48:14Z
localmodelnodes.serving.kserve.io                                 2026-02-13T14:48:14Z
servingruntimes.serving.kserve.io                                 2026-02-13T14:48:14Z
trainedmodels.serving.kserve.io                                   2026-02-13T14:48:14Z

```

5. Verify model access

Port forward the service to local machine.

```
> INGRESS_GATEWAY_SERVICE=$(kubectl get svc --namespace istio-system --selector="app=istio-ingressgateway" --output jsonpath='{.items[0].metadata.name}')
> kubectl port-forward --namespace istio-system svc/${INGRESS_GATEWAY_SERVICE} 8080:80
```

Open another terminal, and enter the following to perform inference:

```
> export INGRESS_HOST=localhost
> export INGRESS_PORT=8080
> export SERVICE_HOSTNAME=$(kubectl get inferenceservice qwen-llm -n default -o jsonpath='{.status.url}' | cut -d "/" -f 3)
> export MODEL_NAME=qwen

> curl -v http://${INGRESS_HOST}:${INGRESS_PORT}/openai/v1/completions -H "Host: ${SERVICE_HOSTNAME}" -H "Content-Type: application/json" -d '{
  "model": "'"${MODEL_NAME}"'",
  "prompt": "Write a poem about colors",
  "max_tokens": 100,
  "stream": false
}'
* Host localhost:8080 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:8080...
* Connected to localhost (::1) port 8080
* using HTTP/1.x
> POST /openai/v1/completions HTTP/1.1
> Host: qwen-llm.default.example.com
> User-Agent: curl/8.14.1
> Accept: */*
> Content-Type: application/json
> Content-Length: 102
>
* upload completely sent off: 102 bytes
< HTTP/1.1 200 OK
< content-length: 777
< content-type: application/json
< date: Fri, 13 Feb 2026 15:07:02 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 5088
<
* Connection #0 to host localhost left intact
{"id":"38dc003b-d538-444e-9aa4-6e6cf0ff3c16","object":"text_completion","created":1770995228,"model":"qwen","choices":[{"index":0,"text":" in the sky, focusing on the changing hues of the day and night. The sky is a canvas painted by the sun, a canvas of colors that change with the seasons. The sun rises and sets, painting the sky in hues of orange, pink, and purple, each one a new masterpiece. The sun sets and the sky darkens, painting the sky in shades of blue, green, and brown, each one a new masterpiece. The sky is a canvas painted by the stars, a canvas","logprobs":null,"finish_reason":"length","stop_reason":null,"prompt_logprobs":null}],"usage":{"prompt_tokens":5,"total_tokens":105,"completion_tokens":100,"prompt_tokens_details":null},"system_fingerprint":null}
```

**Test 3: Deploy Kubeflow**

Follow instructions in this document https://documentation.suse.com/trd/kubeflow/html/gs_rancher_kubeflow/index.html
