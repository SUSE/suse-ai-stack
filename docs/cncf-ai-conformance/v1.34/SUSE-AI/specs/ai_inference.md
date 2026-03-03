MUST: Support the Kubernetes Gateway API with an implementation for advanced traffic management for inference services, which enables capabilities like weighted traffic splitting, header-based routing (for OpenAI protocol headers), and optional integration with service meshes.

**Test 1: Weighted Traffic Splitting with APISIX**

**Step 1: Setup SUSE AI Test Environment**

- You can use the automated setup available at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) to spin up a SUSE AI instance.
- Note 1: the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.
- Note 2: the default ingress must be disabled by setting `ingress-controller: none` on the `/etc/rancher/rke2/config.yaml` file.
- Note 3: it was deployed 2 ollamas releases (ollama and ollama-1) for the purpose of using load balancing through APISIX.
- Note 4: APISIX has support for Gateway API but is not enabled by default and you should install Gateway API CRDs manually checking gateway api version, for example: apisix ingress controller is 1.8.4-14.5 from helm chart v2.11.3 and it uses gateway api v1.3.0.

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

NOTE: See [https://docs.apps.rancher.io/get-started/authentication#kubernetes](SUSE's Application Collection documentation) for more information about the `imagePullSecrets` parameter.

**Step 3: Create Route and Verify load balancing**

1. Create the required objects such as `GatewayClass`, `Gateway` and `HTTPRoute` objects as:

```
cat <<EOF | kubectl create -f -
---
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: apisix
spec:
  controllerName: apisix.apache.org/apisix-ingress-controller
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: apisix-gateway
  namespace: apisix
spec:
  gatewayClassName: apisix
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inference-service
  namespace: suse-private-ai
spec:
  parentRefs:
  - name: apisix-gateway
    namespace: apisix
  hostnames:
  - "inference.service.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/chat/completions
    backendRefs:
    - name: ollama
      port: 11434
      weight: 50
    - name: ollama-1
      port: 11434
      weight: 50
EOF
```

2. Verify load balancing based on weight

```
# Get the proper port
PORT=$(kubectl get svc -n apisix --selector app.kubernetes.io/service=apisix-gateway -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl --location -X POST "http://localhost:${PORT}/v1/chat/completions" -H "Host: inference.service.com" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```

**Test 2: Header-based Routing with APISIX**

**Step 1: Setup SUSE AI Test Environment**

- Follow the same setup process described in **Test 1** to initialize the SUSE AI testing environment.

**Step 2: Setup APISIX Gateway with API Gateway enabled**

- Use the same deployment configuration from **Test 1** to install and configure the APISIX Gateway.

**Step 3: Create Route and Verify header-based routing**

1. Create YAML file route configuration:

```
cat <<EOF | kubectl create -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: inference-service-header
  namespace: suse-private-ai
spec:
  parentRefs:
  - name: apisix-gateway
    namespace: apisix
  hostnames:
  - "inference.service-header.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /v1/chat/completions
    - headers:
      - name: OpenAI-Model
        value: gemma:2b
    backendRefs:
    - name: ollama
      port: 11434
    - name: ollama-1
      port: 11434
      weight: 100
EOF
```

2. Verify routing based on header

```
# Get the proper port
PORT=$(kubectl get svc -n apisix --selector app.kubernetes.io/service=apisix-gateway -o jsonpath='{.items[0].spec.ports[0].nodePort}')
curl --location -X POST "http://localhost:${PORT}/v1/chat/completions" -H "Content-Type: application/json" -H "OpenAI-Model: gemma:2b" -d '{ "model": "gemma:2b", "messages": [{ "role": "system", "content": "You are a helpful assistant."}, {"role": "user","content": "Hello!"}]}'
```

**Step 4: (Optional) Cleanup**

```
helm uninstall apisix -n apisix
kubectl delete namespace apisix
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/experimental-install.yaml
# Remove the `ingress-controller: none` setting on the `/etc/rancher/rke2/config.yaml` file and restart the rke2-server service
```
