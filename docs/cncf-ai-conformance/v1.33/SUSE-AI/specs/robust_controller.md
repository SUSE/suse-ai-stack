MUST: The platform must prove that at least one complex AI operator with a CRD (e.g., Ray, Kubeflow) can be installed and functions reliably. This includes verifying that the operator's pods run correctly, its webhooks are operational, and its custom resources can be reconciled.

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

**Test 2: Deploy Kubeflow**

Follow instructions in this document https://documentation.suse.com/trd/kubeflow/html/gs_rancher_kubeflow/index.html 
