MUST: Support the Kubernetes Gateway API with an implementation for advanced traffic management for inference services, which enables capabilities like weighted traffic splitting, header-based routing (for OpenAI protocol headers), and optional integration with service meshes.

**Test 1: Weighted Traffic Splitting with APISIX**

**Step 1: Setup SUSE AI Test Environment**

- Setup an end to end SUSE AI instance on AWS using the automated setup at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) 
- Note 1: the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.
- Note 2: it was deployed 2 ollamas releases (ollama and ollama-1) for the purpose of using load balancing through APISIX.
- Note 3: APISIX has support for Gateway API but is not enabled by default and you should install Gateway API CRDs manually checking gateway api version, for example: apisix ingress controller is 1.8.4-14.5 from helm chart v2.11.3 and it uses gateway api v1.3.0.

**Step 2: Setup APISIX Gateway with API Gateway enabled**

1. Install required CRDs
```
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
```

2. Install APISIX Gateway
```
helm upgrade -i apisix oci://dp.apps.rancher.io/charts/apache-apisix --version 2.11.3 --create-namespace  --namespace apisix \
    --set global.imagePullSecrets={application-collection} --set apisix.admin.enabled=true --set apisix.admin.type=NodePort \
    --set apisix.admin.allow.ipList={0.0.0.0/0} --set ingress-controller.enabled=true --set ingress-controller.config.apisix.serviceNamespace=apisix \
    --set ingress-controller.config.apisix.adminAPIVersion="v3" --set ingress-controller.config.kubernetes.enableGatewayAPI=true
```

**Step 3: Create Route and Verify load balancing**

1. Create YAML file route configuration
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

2. Apply route configuration to ollama namespace (suse-private-ai)
```
kubectl apply -f route-weight.yaml -n suse-private-ai
```

3. Verify load balancing based on weight
```
curl --location -X POST "http://localhost:31261/v1/chat/completions" -H "Host: inference.service.com" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```

**Test 2: Header-based Routing with APISIX**

**Step 1: Setup SUSE AI Test Environment**
- the same as the test 1

**Step 2: Setup APISIX Gateway with API Gateway enabled**
- the same as the test 1

**Step 3: Create Route and Verify header-based routing**

1. Create YAML file route configuration
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

2. Apply route configuration to ollama namespace (suse-private-ai)
```
kubectl apply -f route-header.yaml -n suse-private-ai
```

3. Verify routing based on header
```
curl --location -X POST "http://localhost:31261/v1/chat/completions" -H "Content-Type: application/json" -H "OpenAI-Model: gemma:2b" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```