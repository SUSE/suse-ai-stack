# MUST: The platform must allow for the installation and successful operation of at least one gang scheduling solution that ensures all-or-nothing scheduling for distributed AI workloads (e.g. Kueue, Volcano, etc.) To be conformant, the vendor must demonstrate that their platform can successfully run at least one such solution.

**Test: Deploy a distributed job using Volcano's gang scheduling capabilities**

**Step 1: Setup SUSE AI Test Environment**

Setup an end to end SUSE AI instance on AWS using the automated setup at [https://github.com/suse/suse-ai-stack](https://github.com/suse/suse-ai-stack) 

This test requires a multi node cluster with 1 control plane node (CPU) and 2 worker nodes (GPU). For example, You can use below cluster config in the suse-ai-stack extra-vars.yaml file.

```
cluster: 
  user: "ec2-user"
  user_home: "/home/ec2-user"
  root_volume_size: 350
  image_arch: "x86_64" # options supported "x86_64" and "arm64". Please update the instance type based on the chosen image_arch.
  #image_arch: "arm64" # options supported "x86_64" and "arm64". Please update the instance type based on the chosen image_arch.
  image_distro: "sle-micro" # options supported are "sles" and "sle-micro"
  image_distro_version: "6.0" # "15-sp6" for sles and "6.0" for sle-micro as example
  instance_type_cp: "m5d.2xlarge"
  instance_type_gpu: "g4dn.2xlarge" #g4dn instance type has GPU
  instance_type_nongpu: "m5d.2xlarge"
  num_cp_nodes: 1
  num_worker_nodes_gpu: 2
  num_worker_nodes_nongpu: 0
  token: "mgmt-rke2token"
  version: "v1.32.4+rke2r1" #RKE2 channel version. see https://update.rke2.io/v1-release/channels for a complete list
```

Note that the setup requires SUSE AI subcription for the SUSE OS registration, SUSE Application Collection and the SUSE Observability access.

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
  0, Tesla T4, 15360 MiB

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
distributed-job   Completed   3                         62m

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
gpu-blocker-6f99b7cbc5-dvdvw   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-ggmv8   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-hgt59   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-nchpr   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-pl7lh   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-qg8ld   1/1     Running   0          2m28s
gpu-blocker-6f99b7cbc5-z65t7   1/1     Running   0          2m28s
```

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
distributed-job-coordinator-0   0/1     Pending   0          9s
distributed-job-worker-0        0/1     Pending   0          9s
distributed-job-worker-1        0/1     Pending   0          9s
distributed-job-worker-0        0/1     Pending   0          6m49s
distributed-job-worker-1        0/1     Pending   0          6m49s
distributed-job-worker-1        0/1     Pending   0          7m20s
distributed-job-worker-0        0/1     Pending   0          7m20s
distributed-job-coordinator-0   0/1     Pending   0          7m20s
distributed-job-coordinator-0   0/1     ContainerCreating   0          7m20s
distributed-job-worker-1        0/1     ContainerCreating   0          7m20s
distributed-job-worker-0        0/1     ContainerCreating   0          7m20s
distributed-job-worker-0        0/1     ContainerCreating   0          7m20s
distributed-job-worker-1        0/1     ContainerCreating   0          7m20s
distributed-job-coordinator-0   0/1     ContainerCreating   0          7m20s
distributed-job-worker-0        1/1     Running             0          7m21s
distributed-job-worker-1        1/1     Running             0          7m21s
distributed-job-coordinator-0   1/1     Running             0          7m22s

```