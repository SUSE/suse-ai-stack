# Table Of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [Create Virtual Network](#create_virtual_network)
  - [Assign A Static IP For WebUI](#assign_static_ip)
  - [Add WebUI DNS Entry in /etc/hosts](#add_dns_entry)
- [How Setup The Virtualized Private AI Stack](#setup_howto)
- [How Cleanup/Destroy The Virtualized Private AI Stack](#setup_howto_cleanup)

# Overview <a name="overview" />

Lightweight virtualized private AI stack intended for demo and development
purposes.

The instructions on this document are for setting it up on the local
environment using [libvirt][libvirt].

# Prerequisites <a name="prerequisites" />

* Production registration code to activate the
  [SUSE Linux Enterprise Micro][sle-micro] VM. You can obtain one from
  https://scc.suse.com.
* Ansible >= 2.16 The environments were tested with ansible-core 2.16.7.
* KVM (i.e. qemu-kvm) Hypervisor, preferably the latest and greatest.
* Host with at least 32GB RAM & 200GB free disk space.
* Have access to SUSE internal network, for IBS repo and gitlab access
* `mkisofs` executable. For some distributions, this utility maybe part of the
  `genisoimage` package. You can install it from vendor repo. For example:

  ```console
  sudo zypper install mkisofs
  ```

* Install the required Ansible modules in `requirements.yml`, after
  installing Ansible from above.

  ```console
  ansible-galaxy collection install -r requirements.yml
  ```
## Create Virtual Network <a name="create_virtual_network" />

By default, the libvirt `default` virtual network is used. Therefore, you must
make sure this network is enabled and active. You can check with the
`virsh` CLI. For example:

```console
> virsh net-list --all
 Name              State      Autostart   Persistent
------------------------------------------------------
 default           active     yes         yes
```

However, if you don't want to use the `default` virtual network for whatever
reason, you must create a separte virtual network for the stack to use. See
[libvirt net-create][libvirt-net-create] documentation for more details.
Again, *make sure the virtual network is enabled and active.*

> If you are not using the `default` virtual network, you must uncomment and
> set the `private_ai_vm_network:` option in `extra_vars.yml` file later on.

## Assign A Static IP For WebUI <a name="assign_static_ip" />

By default, you can access the WebUI via the static IP address
`192.168.122.100`, and this IP address is associated with a virtual MAC address
`52:54:00:6C:3C:88`. To make sure the virtual network's DHCP server alway
assign the static IP to the given MAC address, we must add an entry to the
virtual network's definition. We can accomplish by using 
[virsh net-edit][libvirt-net-edit] CLI, by inserting this line in the `<dhcp>`
section.

```console
<host mac='52:54:00:6C:3C:88' ip='192.168.122.100'/>
```
For example, to edit the `default` virtual network:

1. Run `virsh net-edit default`.
2. Insert `<host mac='52:54:00:6C:3C:88' ip='192.168.122.100'/>` into the
   `<dhcp>` section and save the changes in the editor. Your network defintion
   should look similar to this.

   ```console
   <network>
     <name>default</name>
     <uuid>314e5390-370b-4d2c-a0e7-57b220b43754</uuid>
     <forward mode='nat'/>
     <bridge name='virbr0' stp='on' delay='0'/>
     <mac address='52:54:00:49:f7:9e'/>
     <ip address='192.168.122.1' netmask='255.255.255.0'>
       <dhcp>
         <range start='192.168.122.2' end='192.168.122.254'/>
         <host mac='52:54:00:6C:3C:88' ip='192.168.122.100'/>
       </dhcp>
     </ip>
   </network>
   ```
3. Restart the virtual network. For example:
   ```console
   virsh net-destroy default
   virsh net-start default
   ```

> If you are using a different virtual network, static IP, or MAC address,
> adjust the above accordingly.

## Add WebUI DNS Entry in /etc/hosts <a name="add_dns_entry" />

To access the WebUI, we must use the name `suse-ollama-webui`, and this name
is associated with the assigned static IP mentioned above. Since this is not a
public DNS, we must manually add a record into the host's `/etc/hosts` file.

Additionally, the VM's host `private-ai` is also using the same static IP so we
should be adding both records  and rancher hostname `private-ai.suse.demo` 
into `/etc/hosts`. For example:

```console
192.168.122.100 private-ai suse-ollama-webui private-ai.suse.demo
```

> If you are using a different static IP, adjust the above accordingly.

# How Setup The Virtualized Private AI Stack <a name="setup_howto">

1. Copy `extra_vars.yml.local.example` to `extra_vars.yml`.
2. You must uncomment and specify both `registration_email` and
   `registration_code` in `extra_vars.yml` to registry the
   [SUSE Linux Enterprise Micro][sle-micro] VM.
3. Go through the optional configurations in `extra_vars.yml` to make
   additional adjustments if necessary. Make sure `ssh_authorized_keys`
   in `extra_vars.yml` has *your SSH key* so you can SSH into the VM without
   password. For example:

   ```console
   ssh_authorized_keys:
     - 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC/PFrEQRjraJTx5WulyLfPHiDf6OO0rLU3atox2xu18suohUjCrLTIuRaSMX6mHAX8wb/wPFd2hlk8oXKwBxUMFOn1sOlXFti0tYbtR+TidlKMB22hehCa2K6ckQg07l9IQOQhcccSprT4jXxKW3H4PzC5tA+LfrbaUE8eHEv1/5vBK51AsYRf2T2vbSjnUHIP3bWoYbVx1fdLPvCQsYVRwnP7bLcoaIkciWVqjDW6/xEfw9GrCZCl5QfCUs5lRT2TqrgalODJmBg3tWLO2Bfgmvr9+V4j1DGHX7TqSiVGjgqhruXjGZC675/jML2TXnAxvXDQIMaSz0KSsQSKpC/p foo@somedomain'
   ```
4. Run `setup_private_ai_stack.sh`

   ```console
   ./setup_private_ai_stack.sh
   ```
5. Point your browser to `https://<open_webui_hostname>` to access the WebUI,
   where `open_webui_hostname` is default to `suse-ollama-webui`. Login
   using the `admin` account specified in your `extra_vars.yml`. Also, the
   Rancher is accessible by pointing your browser to https://private-ai.suse.demo, using
   the admin user and bootstrap password "rancher".
6. Select the default `llama3` model at the top and start asking AI interesting
   questions at the bottom text box.
7. You may also ssh into the VM via `ssh ai@private-ai`, assuming you've
   provided your SSH key in `extra-vars.yml` at the beginning.

Happy AI'ing!

Note: The local virtualized private AI stack does not support multinode cluster and does not support SLES OS. It only supports SLE-Micro.

# How Cleanup/Destroy The Virtualized Private AI Stack <a name="setup_howto_cleanup">

To clean the local environment, run

```console
./destroy_private_ai_stack.sh
```

The above command will delete the Private AI stack, including the VM itself.

[libvirt]: https://libvirt.org/
[libvirt-net-create]: https://download.libvirt.org/virshcmdref/html/sect-net-create.html
[libvirt-net-edit]: https://download.libvirt.org/virshcmdref/html/sect-net-edit.html
[llm]: https://en.wikipedia.org/wiki/Large_language_model
[ollama]: https://ollama.com/
[open-webui]: https://github.com/open-webui/open-webui
[rancher-prime]: https://www.rancher.com/products/rancher-platform
[rke2]: https://www.rancher.com/products/secure-kubernetes-distribution
[sle-micro]: https://www.suse.com/products/micro/
