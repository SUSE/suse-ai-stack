# Networking: AI Inference

## Requirement

MUST: Support the Kubernetes Gateway API with an implementation for advanced traffic management for inference services, which enables capabilities like weighted traffic splitting, header-based routing (for OpenAI protocol headers), and optional integration with service meshes.

## Setup Configuration

- Setup an end to end SUSE AI instance on AWS using the automated setup at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) 
- Note: the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

### Gateway Configuration

```
helm upgrade -i apisix oci://dp.apps.rancher.io/charts/apache-apisix --version 2.11.3 --create-namespace  --namespace apisix \
    --set global.imagePullSecrets={application-collection} --set apisix.admin.enabled=true --set apisix.admin.type=NodePort \
    --set apisix.admin.allow.ipList={0.0.0.0/0} --set ingress-controller.enabled=true --set ingress-controller.config.apisix.serviceNamespace=apisix \ --set ingress-controller.config.apisix.adminAPIVersion="v3" --set ingress-controller.config.kubernetes.enableGatewayAPI=true
```

```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
```

## Route Configuration - Weighted Traffic Splitting

```
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: inference-service
spec:
  rules:
  - backendRefs:
      - name: ollama
        port: 11434
        weight: 50
      - name: ollama-1
        port: 11434
        weight: 50
    matches:
      - path:
          value: "/v1/chat/completions"
```

```
kubectl apply -f route-weight.yaml -n suse-private-ai
```

## Testing - Weighted Traffic Splitting

```
curl --location -X POST "http://localhost:31261/v1/chat/completions" -H "Host: inference.service.com" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```


## Route Configuration - Header-based Routing

```
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inference-routing
spec:
  rules:
  - matches:
    - headers:
      - name: OpenAI-Model
        value: gemma:2b
    backendRefs:
    - name: ollama
      port: 11434
  - backendRefs:
    - name: ollama-1
      port: 11434
      weight: 100
```

```
kubectl apply -f route-header.yaml -n suse-private-ai
```

## Testing - Header-based Routing

```
curl --location -X POST "http://localhost:31261/v1/chat/completions" -H "Content-Type: application/json" -H "OpenAI-Model: gemma:2b" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```