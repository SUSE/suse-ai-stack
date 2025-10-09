# Scheduling: Pod Autoscaling

## Requirement

MUST: If the platform supports the HorizontalPodAutoscaler, it must function correctly for pods utilizing accelerators. This includes the ability to scale these Pods based on custom metrics relevant to AI/ML workloads.

## Setup Configuration

### Ollama configuration

1. **Multi-Node Scaling (Shared PVC to Avoid Re-Downloading Models)**
- You can scale Ollama across multiple nodes as long as each node has a GPU available. To ensure optimal distribution, configure `podAntiAffinity` so that replicas are scheduled on different nodes, and use a shared **Persistent Volume** with **ReadWriteMany (RWX)** access mode—such as one provided by **Longhorn**, **NFS**, or another RWX-capable storage class—to allow all pods to access the same model data without re-downloading it. Alternatively, if you prefer isolated storage per replica, deploy Ollama as a `StatefulSet` with `volumeClaimTemplates`, giving each pod its own dedicated volume.
- Values file (ollama-values.yaml)
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

- Ollama helm installation from [AppCo](https://apps.rancher.io/applications/ollama)
```
helm upgrade -i ollama oci://dp.apps.rancher.io/charts/ollama -n suse-private-ai --version 1.26.0 -f ollama-values.yaml
```

2. **Single-Node Scaling**

## Scaling Configuration

1. **Install Prometheus Adapter**
- Values file (prom-adapter-values.yaml)
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
- Prometheus Adapter helm installation to expose GPU Metrics to the HPA from `SUSE Observability`
```
helm upgrade -i prom-adapter oci://ghcr.io/prometheus-community/charts/prometheus-adapter -n suse-observability -f prom-adapter-values.yaml
```

2. **HPA Configuration**
- YAML file (ollama-hpa.yaml)
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
- HPA Config creation targetting `ollama` deployment
```
kubectl apply -f ollama-hpa.yaml -n suse-private-ai
```

## Testing

1. If you’re testing from outside the cluster, expose the `ollama` service using either a `NodePort` or a `LoadBalancer`.

2. The testing performed was done using a `NodePort` service.
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