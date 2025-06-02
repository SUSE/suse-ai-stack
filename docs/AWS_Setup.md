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

As a guidance, following scenarios has been validated. 
Based on the image_arch, update the product registration_code.
Instance types configured for a specific arch should be supported in the chosen AWS region.
For example, the instance types mentioned in the table below is supported in us-west-2 region.
Not all instance types in this table are supported in other AWS regions. 
You can check by running ```aws ec2 describe-instance-type-offerings --region <REGION>```
arm based deployments are not supported when enable_suse_observability is true.

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
5. Get the public IP of the EC2 instance from the task output when the instance
   is created. For example:

   ```console
   TASK [vm : Display EC2 instance creation output] ************************************
   Friday 26 July 2024  15:31:01 -0700 (0:00:53.924)       0:00:56.436 *********** 
   ok: [localhost] => {
       "msg": {
           "instance_id": {
               "sensitive": false,
               "type": "string",
               "value": "i-013e5dd62d935ec62"
           },
           "instance_public_ip": {
               "sensitive": false,
               "type": "string",
               "value": "34.214.10.56"
           }
       }
   }
   ```
> **_NOTE:_** You can also get the public IP from the [AWS Console][aws-console]
> You instance name should be "<your SUSE username>-ai-dev".
6. Update your local `/etc/hosts` file with the public IP of your instance.
   For example:
   ```console
   34.214.10.56 private-ai suse-ollama-webui private-ai.suse.demo longhorn-private-ai suse-observability
   ```
   Since we are not using public DNS for the instance (to reduce cost), we'll
   need to manually create the DNS entry every time we create the Private AI
   stack.
6. Point your browser to `https://<open_webui_hostname>` to access the WebUI,
   where `open_webui_hostname` is default to `suse-ollama-webui`. Login
   using the `admin` account specified in your `extra_vars.yml`. Also, the
   Rancher is accessible by pointing your browser to https://private-ai.suse.demo, using
   the admin user and bootstrap password "rancher".
   Longhorn UI is accessible at https://longhorn-private-ai and the credentials to login is admin/longhorn.
   SUSE Observvability is accessible at `https://<suse_observability_hostname>` and the credentials are available in your EC2 instance (baseConfig_values.yaml).
7. Start asking AI interesting questions at the bottom text box.
8. You may also ssh into the VM via `ssh -o ServerAliveInterval=60 -o ServerAliveCountMax=3 ec2-user@private-ai`, assuming you've
   provided your SSH key in `extra-vars.yml` at the beginning.

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

