MUST: If the platform supports the HorizontalPodAutoscaler, it must function correctly for pods utilizing accelerators. This includes the ability to scale these Pods based on custom metrics relevant to AI/ML workloads.

**Test 1: Pod Autoscaling with GPU Metrics**

**Step 1: Setup SUSE AI Test Environment**

- You can use the automated setup  available at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) to spin up a SUSE AI instance.
- Note: the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

**Step 2: Install Ollama**

- Note: You can scale Ollama across multiple nodes as long as each node has a GPU available. To ensure optimal distribution, configure `podAntiAffinity` so that replicas are scheduled on different nodes, and use a shared **Persistent Volume** with **ReadWriteMany (RWX)** access mode—such as one provided by **Longhorn**, **NFS**, or another RWX-capable storage class—to allow all pods to access the same model data without re-downloading it. Alternatively, if you prefer isolated storage per replica, deploy Ollama as a `StatefulSet` with `volumeClaimTemplates`, giving each pod its own dedicated volume.

1. Create multi-Node Scaling (Shared PVC to Avoid Re-Downloading Models) configuration file (ollama-values.yaml)
```
global:
  imagePullSecrets:
  - application-collection
ingress:
  enabled: false
defaultModel: "gemma:2b"
ollama:
  models:
    pull:
      - "gemma:2b"
    run:
      - "gemma:2b"
  gpu:
    enabled: true
    type: 'nvidia'
    number: 1
persistentVolume:
  enabled: true
  storageClass: longhorn
  size: 20Gi
  accessModes:
    - ReadWriteMany
extraEnv:
  - name: OLLAMA_DEBUG
    value: "1"
runtimeClassName: "nvidia"
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          topologyKey: kubernetes.io/hostname
          labelSelector:
            matchExpressions:
              - key: app.kubernetes.io/name
                operator: In
                values:
                  - ollama
```

2. Deploy Ollama helm installation from [AppCo](https://apps.rancher.io/applications/ollama)
```
helm upgrade -i ollama oci://dp.apps.rancher.io/charts/ollama -n suse-private-ai --version 1.26.0 -f ollama-values.yaml
```

**Step 3: Configure custom metrics**
- Note: **The DCGM Exporter** bundled with the NVIDIA **GPU Operator** provides detailed GPU metrics—such as utilization, temperature, and memory usage—through a Prometheus-compatible endpoint. These metrics can be leveraged by an autoscaling solution to make informed scaling decisions. Since **SUSE Observability** includes **VictoriaMetrics**, which is fully compatible with Prometheus for ingesting and querying metrics, there’s no need to deploy a separate Prometheus server. However, GPU metrics are not exposed by default through the **Kubernetes Metrics API**, so to enable autoscaling based on GPU performance data, a **Custom Metrics API adapter** is required to export metrics from VictoriaMetrics to the Kubernetes API for use with the **Horizontal Pod Autoscaler (HPA)**.

1. Create Prometheus Adapter values file (prom-adapter-values.yaml)
```
prometheus:
  url: http://suse-observability-victoria-metrics-0
  port: 8428

rules:
  custom:
    - seriesQuery: 'DCGM_FI_DEV_GPU_UTIL{namespace!=""}'
      resources:
        overrides:
          namespace:
            resource: namespace
      name:
        matches: "DCGM_FI_DEV_GPU_UTIL"
        as: "gpu_utilization"
      metricsQuery: 'avg(DCGM_FI_DEV_GPU_UTIL{<<.LabelMatchers>>}) by (<<.GroupBy>>)'
```

2. Deploy Prometheus Adapter helm installation to expose GPU Metrics to the HPA from `SUSE Observability`
```
helm upgrade -i prom-adapter oci://ghcr.io/prometheus-community/charts/prometheus-adapter -n suse-observability -f prom-adapter-values.yaml
```

**Step 4: Create HPA Configuration and verify autoscaling**
1. Create HPA Configuration YAML file (ollama-hpa.yaml)
```
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ollama-hpa
spec:
  scaleTargetRef:
        apiVersion: apps/v1
        kind: Deployment
        name: ollama
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Object
    object:
      describedObject:
        apiVersion: v1
        kind: Namespace
        name: suse-private-ai
      metric:
        name: gpu_utilization
      target:
        type: AverageValue
        averageValue: "70"
```

2. Apply HPA Config creation targetting `ollama` deployment
```
kubectl apply -f ollama-hpa.yaml -n suse-private-ai
```

3. If you’re testing from outside the cluster, expose the `ollama` service using either a `NodePort` or a `LoadBalancer`.

4. The testing performed was done using a `NodePort` service.
```python
import requests
import threading
import time

def send_chat():
	while True:
    	res = requests.post("http://suse-ai:32481/api/chat", json={
        	"model": "gemma:2b",
        	"messages": [
            	{"role": "user", "content": "Explain quantum mechanics in detail for 10 minutes."}
        	]
    	})
    	print(res.status_code, res.elapsed)

threads = []

for _ in range(10):
	t = threading.Thread(target=send_chat)
	t.start()
	threads.append(t)

for t in threads:
	t.join()
```