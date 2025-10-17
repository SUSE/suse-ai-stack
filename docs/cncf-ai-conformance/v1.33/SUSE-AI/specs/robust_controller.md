# MUST: The platform must prove that at least one complex AI operator with a CRD (e.g., Ray, Kubeflow) can be installed and functions reliably. This includes verifying that the operator's pods run correctly, its webhooks are operational, and its custom resources can be reconciled.

**Test 1 (Simple): Deploy Ollama Inference engine via operator**

**Step 1: Setup SUSE AI Test Environment**

Setup an end to end SUSE AI instance on AWS using the automated setup at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) 

Note that the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

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
./kserve/quick_install.sh
```

2. Deploy the InferenceService

```
kubectl apply -f ./kserve/qwen-kserve.yaml
```

3. Check InferenceService status

```
> kubectl get inferenceservice qwen-llm
NAME       URL                                   READY   PREV   LATEST   PREVROLLEDOUTREVISION   LATESTREADYREVISION        AGE
qwen-llm   http://qwen-llm.default.example.com   True           100                              qwen-llm-predictor-00001   104m
```

4. Verify Kserve CRDs are created

```
> kubectl get crd | grep -i kserve
clusterservingruntimes.serving.kserve.io                          2025-10-16T20:33:28Z
clusterstoragecontainers.serving.kserve.io                        2025-10-16T20:33:28Z
inferencegraphs.serving.kserve.io                                 2025-10-16T20:33:28Z
inferenceservices.serving.kserve.io                               2025-10-16T20:33:28Z
localmodelcaches.serving.kserve.io                                2025-10-16T20:33:28Z
localmodelnodegroups.serving.kserve.io                            2025-10-16T20:33:28Z
localmodelnodes.serving.kserve.io                                 2025-10-16T20:33:28Z
servingruntimes.serving.kserve.io                                 2025-10-16T20:33:28Z
trainedmodels.serving.kserve.io                                   2025-10-16T20:33:28Z

```

5. Verify model access

Port forward the service to local machine.

```
INGRESS_GATEWAY_SERVICE=$(kubectl get svc --namespace istio-system --selector="app=istio-ingressgateway" --output jsonpath='{.items[0].metadata.name}')
kubectl port-forward --namespace istio-system svc/${INGRESS_GATEWAY_SERVICE} 8080:80
```

Open another terminal, and enter the following to perform inference:

```
export INGRESS_HOST=localhost
export INGRESS_PORT=8080

SERVICE_HOSTNAME=$(kubectl get inferenceservice qwen-llm -n kserve-test -o jsonpath='{.status.url}' | cut -d "/" -f 3)
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
*   Trying 127.0.0.1:8080...
* Connected to localhost (127.0.0.1) port 8080
> POST /openai/v1/completions HTTP/1.1
> Host: qwen-llm.default.example.com
> User-Agent: curl/8.6.0
> Accept: */*
> Content-Type: application/json
> Content-Length: 104
> 
< HTTP/1.1 200 OK
< content-length: 779
< content-type: application/json
< date: Thu, 16 Oct 2025 22:53:36 GMT
< server: istio-envoy
< x-envoy-upstream-service-time: 10805
< 
* Connection #0 to host localhost left intact
{"id":"00be92d3-b2ca-40ff-918f-f64239d156f0","object":"text_completion","created":1760655228,"model":"qwen","choices":[{"index":0,"text":" in the sky, focusing on the changing hues of the day and night. The sun rises, casting a warm glow over the earth, and the sky transforms into a kaleidoscope of colors. The morning sky is a deep, rich blue, with clouds of white and gray, and the sun's rays dance across the earth, creating a mesmerizing display of light and shadow. As the day progresses, the sky becomes a vibrant tapestry of oranges, pinks, and purples, with","logprobs":null,"finish_reason":"length","stop_reason":null,"prompt_logprobs":null}],"usage":{"prompt_tokens":5,"total_tokens":105,"completion_tokens":100,"prompt_tokens_details":null},"system_fingerprint":null}
```

**Test 3: Deploy Kubeflow**

Follow instructions in this document https://documentation.suse.com/trd/kubeflow/html/gs_rancher_kubeflow/index.html 
