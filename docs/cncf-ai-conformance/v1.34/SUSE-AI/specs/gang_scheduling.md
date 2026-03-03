# MUST: The platform must allow for the installation and successful operation of at least one gang scheduling solution that ensures all-or-nothing scheduling for distributed AI workloads (e.g. Kueue, Volcano, etc.) To be conformant, the vendor must demonstrate that their platform can successfully run at least one such solution.

**Test: Deploy a distributed job using Volcano's gang scheduling capabilities**

**Step 1: Setup SUSE AI Test Environment**

- You can use the automated setup available at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) to spin up a SUSE AI instance.
- Note 1: This test requires a multi node cluster with 1 control plane node (CPU) and 2 worker nodes (GPU).
- Note 2: The setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

**Step 2: Deploy Volcano**

```
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts
helm repo update

helm install volcano volcano-sh/volcano -n volcano-system --create-namespace
```

**Step 3: Deploy a distributed job with 1 coordinator and 2 workers**

```
kubectl apply -f ./volcano/distributed-job.yaml
```

**Step 3: Verify Gang Scheduling Behavior**

Check Pod Status.

```
kubectl get pods -l volcano.sh/job-name=distributed-job -w
```

If sufficient resources exist:

- All 3 pods transition to `Pending` → `Running` simultaneously
- Volcano only schedules when ALL 3 can be placed

**Step 3: Verify GPU Detection in Workers**

Check worker logs to confirm GPU access.

```
> kubectl logs distributed-job-worker-0
Worker 0 (distributed-job-worker-0) started
Coordinator address: distributed-job-coordinator-0.distributed-job

=== GPU Check ===
✓ GPU detected:
  0, NVIDIA A2-16Q, 16384 MiB

=== Coordinator Connection ===
Waiting for coordinator...
✓ Coordinator is ready
✓ Checked in successfully: Welcome distributed-job-worker-0!

Worker 0 doing work...
✓ Worker 0 finished

```

**Step 4: Verify Job Completion**

```
> kubectl get vcjob distributed-job
NAME              STATUS      MINAVAILABLE   RUNNINGS   AGE
distributed-job   Completed   3                         119s

```

**Step 4: Test Gang Scheduling "Nothing" Behavior**

Gang scheduling's key feature is **all-or-nothing**: if resources aren't available for ALL pods, NONE get scheduled. This prevents resource deadlocks and wasted partial allocations.

1. Delete the distributed job created before

```
kubectl delete -f ./volcano/distributed-job.yaml
```

2. Create a deployment that blocks most of the GPUs, leaving an insufficient number available for the distributed job. In the gpu-blocker.yaml file, set the number of replicas based on your cluster’s configuration. For example, if the cluster has 8 GPUs, configure the deployment to block 7 of them so that only 1 GPU remains available for the distributed job, which requires 2 GPUs.

```
kubectl apply -f ./volcano/gpu-blocker.yaml
```

Ensure the GPU blocker pods are running.

```
> kubectl get pods -l app=gpu-blocker
NAME                           READY   STATUS    RESTARTS   AGE
gpu-blocker-5c58597db4-5425l   1/1     Running   0          13s
gpu-blocker-5c58597db4-b2qhl   1/1     Running   0          13s
gpu-blocker-5c58597db4-djbmd   0/1     Pending   0          13s
gpu-blocker-5c58597db4-n6rf2   0/1     Pending   0          13s
gpu-blocker-5c58597db4-rmwvp   1/1     Running   0          13s
gpu-blocker-5c58597db4-xd6f8   1/1     Running   0          13s
gpu-blocker-5c58597db4-z2thh   0/1     Pending   0          13s

```

NOTE: In this case, there were only 4 GPUs available.

3. Now, deploy the distributed job again

```
kubectl apply -f ./volcano/distributed-job.yaml
```

4. Check Pod Status.

```
> kubectl get pods -l volcano.sh/job-name=distributed-job -w
NAME                            READY   STATUS    RESTARTS   AGE
distributed-job-coordinator-0   0/1     Pending   0          9s
distributed-job-worker-0        0/1     Pending   0          9s
distributed-job-worker-1        0/1     Pending   0          9s
```

You will see all the jobs are pending because there are not enough GPU resources required to run all the jobs in the group (gang).

5. Now, Delete the GPU blocker deployment and check the jobs pods status. You will see the jobs are scheduled.

```
> kubectl apply -f ./volcano/gpu-blocker.yaml
> kubectl get pods -l volcano.sh/job-name=distributed-job -w
NAME                            READY   STATUS    RESTARTS   AGE
distributed-job-coordinator-0   0/1     Pending   0          23s
distributed-job-worker-0        0/1     Pending   0          23s
distributed-job-worker-1        0/1     Pending   0          23s
distributed-job-worker-1        0/1     Pending   0          8m15s
distributed-job-worker-0        0/1     Pending   0          8m15s
distributed-job-coordinator-0   0/1     Pending   0          8m15s
distributed-job-coordinator-0   0/1     ContainerCreating   0          9m20s
distributed-job-worker-1        0/1     ContainerCreating   0          9m20s
distributed-job-worker-0        0/1     ContainerCreating   0          9m20s
distributed-job-worker-0        0/1     ContainerCreating   0          9m20s
distributed-job-worker-1        0/1     ContainerCreating   0          9m20s
distributed-job-coordinator-0   0/1     ContainerCreating   0          9m20s
distributed-job-worker-0        1/1     Running             0          9m21s
distributed-job-worker-1        1/1     Running             0          9m21s
distributed-job-coordinator-0   1/1     Running             0          9m22s

```

**Step 5: (Optional) Cleanup**

```
kubectl delete -f volcano/distributed-job.yaml
kubectl delete -f volcano/gpu-blocker.yaml
helm uninstall volcano -n volcano-system
kubectl delete namespace volcano-system
helm repo remove volcano-sh
helm repo update
```
