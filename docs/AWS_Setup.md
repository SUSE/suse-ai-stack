# Table Of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [How Setup The Virtualized Private AI Stack](#setup_howto)
- [How Cleanup/Destroy The Virtualized Private AI Stack](#setup_howto_cleanup)

# Overview <a name="overview" />

Lightweight virtualized private AI stack intended for demo and development
purposes.

The instructions on this document are for setting it on [AWS][aws].

> **_WARNING:_** Resources running on [AWS][aws] cost money. Since we are using
> enterprise GPU nodes, they can be relatively expensive. (i.e. $1.00/hour).
> Therefore, please cleanup/destroy the resources after are done for the day so
> the node doesn't sit idle for the night.

# Prerequisites <a name="prerequisites" />

* An AWS account which allow you to have access to the SLE Micro AMIs
  in the LTD geo location (image that has a EU/UK based tax authority).
  This should be your default account for the SUSE Cloud Solutions
  orgranization.
* Ansible >= 2.16 The environments were tested with ansible-core 2.16.7.
* Install the required Ansible modules in `requirements.yml`, after
  installing Ansible from above.

  ```console
  ansible-galaxy collection install -r requirements.yml
  ```
* opentofu: https://opentofu.org/docs/intro/install/

# How Setup The Virtualized Private AI Stack <a name="setup_howto">

1. Copy `extra_vars.yml.aws.example` to `extra_vars.yml`.
2. Fill in the reqired configurations. Make sure `aws_ssh_public_key`
   in `extra_vars.yml` has *your SSH key* so you can SSH into the EC2 node
   without password. For example:

   ```console
   aws_ssh_public_key: ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/PFrEQRjraJTx5WulyLfPHiDf6OO0rLU3atox2xu18suohUjCrLTIuRaSMX6mHAX8wb/wPFd2hlk8oXKwBxUMFOn1sOlXFti0tYbtR+TidlKMB22hehCa2K6ckQg07l9IQOQhcccSprT4jXxKW3H4PzC5tA+LfrbaUE8eHEv1/5vBK51AsYRf2T2vbSjnUHIP3bWoYbVx1fdLPvCQsYVRwnP7bLcoaIkciWVqjDW6/xEfw9GrCZCl5QfCUs5lRT2TqrgalODJmBg3tWLO2Bfgmvr9+V4j1DGHX7TqSiVGjgqhruXjGZC675/jML2TXnAxvXDQIMaSz0KSsQSKpC/p foo@somedomain
   ```
3. Go through the optional configurations in `extra_vars.yml` to make
   additional adjustments if necessary.

By default, we create a management RKE2 cluster where all the services including the AI workloads are deployed and suse observability components are deployed when enable_suse_observability is true. When enable_suse_observability is true, it will need at least 2 instances in the cluster of 2xlarge to handle the workload.

However if you want to seperate deploying AI workload onto its own RKE2 cluster and observability into its own RKE2 cluster, you can update the extra_vars.yml file to add these cluster definitions in addition to the ```cluster:``` section as in extra_vars.yml.aws.example which is the main cluster used for deploying rancher.


```
# For deploying AI workload into its own RKE2 cluster
suse_ai_cluster:
  user: "ec2-user"
  user_home: "/home/ec2-user"
  root_volume_size: 350
  image_arch: "x86_64" # options supported "x86_64" and "arm64". Please update the instance type based on the chosen image_arch.
  image_distro: "sles" # options supported are "sles" and "sle-micro"
  image_distro_version: "15-sp6" # "15-sp6" for sles and "6.0" for sle-micro as example
  instance_type_cp: "g4dn.2xlarge"
  instance_type_gpu: "g4dn.2xlarge" #g4dn instance type has GPU
  instance_type_nongpu: "m5d.2xlarge"
  num_cp_nodes: 1 # If you use only 1 cp node with no workers, you have to set instance_type_cp: "g4dn.2xlarge" for GPU
  num_worker_nodes_gpu: 0
  num_worker_nodes_nongpu: 0
  token: "suse-ai-rke2token"
  version: "v1.32.4+rke2r1" #RKE2 channel version. see https://update.rke2.io/v1-release/channels for a complete list
```

```
# For deploying SUSE observability into its own RKE2 cluster
suse_observability_cluster:
  user: "ec2-user"
  user_home: "/home/ec2-user"
  root_volume_size: 350
  image_arch: "x86_64" # options supported "x86_64" and "arm64". Please update the instance type based on the chosen image_arch.
  image_distro: "sles" # options supported are "sles" and "sle-micro"
  image_distro_version: "15-sp6" # "15-sp6" for sles and "6.0" for sle-micro as example
  instance_type_cp: "t3a.2xlarge"
  instance_type_worker: "t3a.2xlarge"
  num_cp_nodes: 1
  num_worker_nodes: 1
  token: "suse-observability-rke2token"
  version: "v1.32.4+rke2r1" #RKE2 channel version. see https://update.rke2.io/v1-release/channels for a complete list
```

We support deploying using SLE-Micro and SLES based EC2 instances.
As a guidance, following scenarios has been validated. 
Based on the image_arch chosen, update the product registration_code.
Instance types configured for a specific arch should be supported in the chosen AWS region.
For example, the instance types mentioned in the table below is supported in us-west-2 region.
Not all instance types in this table are supported in other AWS regions. 
You can check by running ```aws ec2 describe-instance-type-offerings --region <REGION>```

Note: arm based deployments are not supported when enable_suse_observability is true.

| image_arch             | image_distro           | image_distro_version | instance type family  (2xlarge)             |
| ---------------------  | ---------------------- | -------------------- | ------------------------------------------- |
| x86_64                 | sle-micro              | 6.0                  | g4dn for GPU, m5d for non-GPU               |
| x86_64                 | sle-micro              | 6.1                  | g4dn for GPU, m5d for non-GPU               |
| x86_64                 | sles                   | 15-sp6               | g4dn for GPU, m5d for non-GPU               |
| arm64                  | sle-micro              | 6.0                  | g5g for GPU, m6gd for non-GPU               |
| arm64                  | sle-micro              | 6.1                  | g5g for GPU, m6gd for non-GPU               |
| arm64                  | sles                   | 15-sp6               | g5g for GPU, m6gd for non-GPU               |

4. Run `setup_private_ai_stack.sh`

   ```console
   ./setup_private_ai_stack.sh
   ```
5. Based on the clusters that get created, you will see the public IP of the EC2 master instance from the task output when the instances
   are created for each cluster. For example:

   ```console
   TASK [vm : Display all cluster nodes mgmt cluster] *************************************************************************************************************************************
   Thursday 05 June 2025  12:02:45 -0700 (0:00:00.023)       0:03:24.333 *********
   ok: [localhost] => {
      "msg": [
         {
               "hostname": "mgmt-rancher",
               "ip": "52.25.204.43",
               "name": "mgmt-rancher"
         }
      ]
   }
   .
   .
   TASK [vm : Display all cluster nodes suse ai cluster] **********************************************************************************************************************************
   Thursday 05 June 2025  14:17:24 -0700 (0:00:00.021)       0:00:22.312 ********* 
   ok: [localhost] => {
      "msg": [
         {
               "hostname": "suse-ai",
               "ip": "54.245.160.93",
               "name": "suse-ai"
         }
      ]
   }
   ```
> **_NOTE:_** You can also get the public IP from the [AWS Console][aws-console]
> Your master cp instance name should be "<your SUSE username>-dev-mgmt-cp0" for the mgmt cluster.
> Your master cp instance name should be "<your SUSE username>-dev-ai-cp0" for the suse-ai-cluster when configured to deploy into its own cluster.
> Your master cp instance name should be "<your SUSE username>-dev-observability-cp0" for the suse-ai-cluster when configured to deploy into its own cluster.
6. Update your local `/etc/hosts` file with the public IP of your instance based on the instructions displayed when the `setup_private_ai_stack.sh` completes.
   For example: instructions look like:
   ```
   "Make sure to update the /etc/hosts file: 35.87.100.210 mgmt-rancher suse-rancher.demo",
   "Make sure to update the /etc/hosts file: 35.87.100.210 suse-ai suse-ollama-webui",
   "Make sure to update the /etc/hosts file: 35.87.100.210 suse-observability",
   "To access rancher UI, point your browser to https://suse-rancher.demo and login with user=admin and password=rancher",
   "To access open-webui, point your browser to https://suse-ollama-webui and login with user=admin@suse-private-ai.org and password=WelcomeToAI",
   "To access suse-observability, point your browser to https://suse-observability and login with user=admin and password=MldDMgj2eRHPUXMT"
   ```

   You /etc/hosts file should look like:
```console
  35.87.100.210 mgmt-rancher suse-rancher.demo
  35.87.100.210 suse-ai suse-ollama-webui
  35.87.100.210 suse-observability
```
   Since we are not using public DNS by default for the instance (to reduce cost), we'll
   need to manually create the DNS entry every time we create the Private AI
   stack.
6. Point your browser to `https://<open_webui_hostname>` to access the WebUI,
   where `open_webui_hostname` is default to `suse-ollama-webui`. Login
   using the `admin` account specified in your `extra_vars.yml`. Also, the
   Rancher is accessible by pointing your browser to https://suse-rancher.demo, using
   the admin user and bootstrap password "rancher".
   Longhorn UI is accessible at http://suse-longhorn and the credentials to login is admin/longhorn.
   SUSE Observvability is accessible at `https://<suse_observability_hostname>` and the credentials are available in your EC2 instance (baseConfig_values.yaml).
7. Start asking AI interesting questions at the bottom text box.
8. You may also ssh into the VM via `ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 ec2-user@mgmt-rancher` assuming you've
   provided your SSH key in `extra-vars.yml` at the beginning.
   When separate clusters are used for AI workload and observability, you can ssh into the VM via `ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 ec2-user@suse-ai` or `ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 ec2-user@suse-observability`

Happy AI'ing!

Note: The AWS based private AI stack supports multinode cluster and also supports both SLES or SLE-Micro based AMI.

# How Cleanup/Destroy The Virtualized Private AI Stack <a name="setup_howto_cleanup">

To clean the local environment, run

```console
./destroy_private_ai_stack.sh
```

The above command will delete the Private AI stack, including the VM itself.

[aws]: https://aws.amazon.com/
[aws-console]: https://aws.amazon.com/console/
[llm]: https://en.wikipedia.org/wiki/Large_language_model
[ollama]: https://ollama.com/
[open-webui]: https://github.com/open-webui/open-webui
[rancher-prime]: https://www.rancher.com/products/rancher-platform
[rke2]: https://www.rancher.com/products/secure-kubernetes-distribution
[sle-micro]: https://www.suse.com/products/micro/

