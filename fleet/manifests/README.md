# Prerequisites

## Create SUSE Application Collections (a.k.a. AppCo) Helm Registry Secret

This is needed in order to pull SUSE AI Helm charts from AppCo Helm registry during deployment. And the secret type must be *generic*.

> :warning: If the deployment is for a single node, make sure to create it in the ***fleet-local*** namespace. Otherwise, create it in the same namespace as the ***GitRepo*** resource.

> :warning: The name of the secret (i.e. ***appco-helm-secret***) must match the one specified in the ***GitRepo*** resource.

For example:

```
kubectl create secret generic appco-helm-secret --from-literal=username=foo@suse.com --from-literal=password=SDFBdsdf2sSDFwbnl3YWVudWFlbGR3Z3h3bSXdakWer86d2N6bWRhaw== -n fleet-local
```

## Create SUSE Application Collections (a.k.a. AppCo) Container Registry Secret

This is needed in order to pull SUSE AI container images from AppCo container registry during deployment. And the secret type must be ***docker-registry***.

> :warning: The name of the secret (i.e. ***application-collection***) must match the ***helmSecretName*** specified ***fleet.yaml***.

> :warning: The namespace (i.e. ***suse-ai***) must match the one specified in ***fleet.yaml***. Also, if the namespace doesn't already exist, you must first create it.

For example:

```
kubectl create namespace suse-ai
kubectl create secret docker-registry application-collection --docker-server=dp.apps.rancher.io --docker-username=foo@suse.com --docker-password=SDFBdsdf2sSDFwbnl3YWVudWFlbGR3Z3h3bSXdakWer86d2N6bWRhaw== -n suse-ai
```
