"""Offline regressions for provisioning, worker coverage, and fixture retirement."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from jinja2 import Template

LAB = Path(__file__).resolve().parents[1]


def run(*args, env=None, input=None, check=True):
    return subprocess.run(args, env={**os.environ, **(env or {})}, input=input,
                          text=True, capture_output=True, check=check)


def read_yaml(path):
    return json.loads(run('yq', '-o=json', '.', str(path)).stdout)


class NodeConfiguration(unittest.TestCase):
    def config(self, value=None):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'nodes.json'
            path.write_text(json.dumps(value or {}))
            return run(str(LAB / 'scripts/node-config.sh'),
                       env={'AIF_AIRGAP_NODE_CONFIG': str(path)}, check=False)

    def test_cpu_default_and_gpu_opt_in(self):
        cpu = json.loads(self.config().stdout)
        self.assertFalse(cpu['enable_gpu_operator'])
        self.assertFalse(cpu['enable_nvidia_driver_pkg_install'])
        self.assertEqual(cpu['suse_ai_cluster']['num_worker_nodes_gpu'], 0)
        gpu = json.loads(self.config({'suse_ai_cluster': {
            'num_worker_nodes_gpu': 2, 'instance_type_gpu': 'g6.2xlarge',
            'root_volume_size': 200}}).stdout)
        self.assertTrue(gpu['enable_gpu_operator'])
        self.assertTrue(gpu['enable_nvidia_driver_pkg_install'])
        self.assertFalse(gpu['use_nvidia_driver_installer'])
        self.assertEqual(gpu['cluster'], cpu['cluster'])
        self.assertEqual(gpu['suse_ai_cluster']['num_worker_nodes_gpu'], 2)

    def test_invalid_counts_types_and_unknown_options_fail_before_provisioning(self):
        for config in [
            {'suse_ai_cluster': {'num_worker_nodes_gpu': -1}},
            {'suse_ai_cluster': {'num_worker_nodes_gpu': 0.5}},
            {'suse_ai_cluster': {'num_worker_nodes_gpu': '1'}},
            {'suse_ai_cluster': {'num_worker_nodes_gpu': 1, 'instance_type_gpu': 'm6i.xlarge'}},
            {'suse_ai_cluster': {'num_worker_nodes_gpu': 1, 'instance_type_gpu': 'g4ad.xlarge'}},
            {'suse_ai_cluster': {'num_worker_nodes_gpu': 1, 'instance_type_gpu': 'g5g.xlarge'}},
            {'suse_ai_cluster': {'instance_type_cp': 'g4dn.2xlarge'}},
            {'suse_ai_cluster': {'num_worker_nodes_gpus': 1}},
            {'suse_ai_cluster': {'num_cp_nodes': 0}},
            {'enable_time_slicing': 'true'},
            {'time_slicing_replicas': 0},
            {'gpu_operator_chart_version': 'latest'},
        ]:
            with self.subTest(config=config):
                self.assertNotEqual(self.config(config).returncode, 0)

    def test_prepare_preserves_credentials_and_migrates_existing_vars(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lab = root / 'airgap-lab'
            (lab / 'scripts').mkdir(parents=True)
            for name in ['prepare-aws.sh', 'node-config.sh']:
                shutil.copy2(LAB / 'scripts' / name, lab / 'scripts' / name)
            for name in ['vars.example.yml', 'nodes.example.yml']:
                shutil.copy2(LAB / name, lab / name)
            source = root / 'aif'
            (source / 'charts/aif-operator').mkdir(parents=True)
            (source / 'charts/aif-operator/Chart.yaml').write_text('version: 1.2.3\n')
            run('git', 'init', '-q', str(source))
            run('git', '-C', str(source), 'add', 'charts')
            run('git', '-C', str(source), '-c', 'user.name=Lab Test',
                '-c', 'user.email=lab@example.invalid', '-c', 'core.hooksPath=/dev/null',
                'commit', '-qm', 'fixture')
            key = root / 'ssh-key'
            run('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key))
            base = {name: 'fixture' for name in [
                'aws_access_key', 'aws_secret_key', 'aws_region', 'aws_az1', 'aws_az2',
                'aws_resource_owner', 'aws_resource_prefix', 'aws_ssh_key_name',
                'registration_email', 'sles_registration_code']}
            base['aws_ssh_public_key'] = key.with_suffix('.pub').read_text().strip()
            (root / 'extra_vars.yml').write_text(json.dumps(base))
            env = {'AIF_SOURCE_DIR': str(source), 'AIF_AIRGAP_SSH_KEY': str(key),
                   'AIF_AIRGAP_CONTROLLER_CIDR': '192.0.2.1/32',
                   'AIF_AIRGAP_BASE_VARS': str(root / 'extra_vars.yml'),
                   'AIF_AIRGAP_NODE_CONFIG': str(lab / 'nodes.example.yml'),
                   'AIF_AIRGAP_STACK_VARS': str(lab / 'generated/stack-vars.yml'),
                   'AIF_AIRGAP_VARS': str(lab / 'generated/vars.yml')}
            run(str(lab / 'scripts/prepare-aws.sh'), env=env)
            first_stack = read_yaml(lab / 'generated/stack-vars.yml')
            old = read_yaml(lab / 'generated/vars.yml')
            credentials = {k: old[k] for k in ['harbor_admin_password', 'gitea_admin_password', 'rancher_bootstrap_password']}
            old.pop('airgap_target_clusters')
            old['smoke_target_clusters'] = ['local', 'c-fixture']
            old['suse_apps_target_clusters'] = '{{ smoke_target_clusters }}'
            old['smoke_workload_name'] = 'retired'
            (lab / 'generated/vars.yml').write_text(json.dumps(old))
            (lab / 'nodes.yml').write_text('suse_ai_cluster:\n  num_worker_nodes_gpu: 1\n')
            env['AIF_AIRGAP_NODE_CONFIG'] = str(lab / 'nodes.yml')
            run(str(lab / 'scripts/prepare-aws.sh'), env=env)
            second = read_yaml(lab / 'generated/vars.yml')
            stack = read_yaml(lab / 'generated/stack-vars.yml')
            self.assertEqual(credentials, {k: second[k] for k in credentials})
            self.assertEqual(first_stack['cluster']['token'], stack['cluster']['token'])
            self.assertEqual(second['airgap_target_clusters'], ['local', 'c-fixture'])
            self.assertEqual(second['suse_apps_target_clusters'], '{{ airgap_target_clusters }}')
            self.assertFalse(any(k.startswith('smoke_') for k in second))
            self.assertTrue(stack['enable_gpu_operator'])
            self.assertEqual(stack['suse_ai_cluster']['num_worker_nodes_gpu'], 1)
            self.assertEqual((lab / 'generated/vars.yml').stat().st_mode & 0o777, 0o600)

    def test_original_stack_gpu_flags_remain_compatible(self):
        for playbook in ['define_nodes_mgmt_cluster.yml', 'define_nodes_suse_ai_cluster.yml']:
            lines = (LAB.parent / 'playbooks' / playbook).read_text().splitlines()
            expressions = [line.split(': ', 1)[1] for line in lines
                           if line.strip().startswith(('driver_install:', 'gpu_operator_deploy:'))]
            self.assertEqual(len(expressions), 2)
            for lab_mode, count, expected in [(False, 0, 'true'), (True, 0, 'false'), (True, 1, 'true')]:
                variables = {'enable_gpu_operator': True, 'enable_nvidia_driver_pkg_install': True,
                             'airgap_lab_node_config': lab_mode,
                             'cluster': {'num_worker_nodes_gpu': count},
                             'suse_ai_cluster': {'num_worker_nodes_gpu': count}}
                for expression in expressions:
                    with self.subTest(playbook=playbook, lab=lab_mode, count=count):
                        self.assertEqual(Template(expression).render(**variables), expected)

    def test_topology_key_ignores_passwords_and_unused_gpu_types(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'stack.json'
            config = json.loads(self.config().stdout)
            def key():
                path.write_text(json.dumps(config))
                return run(str(LAB / 'scripts/topology-key.sh'), str(path)).stdout
            cpu_key = key()
            config['cluster']['token'] = 'another token'
            config['cluster']['instance_type_gpu'] = 'g6.2xlarge'
            config['harbor_admin_password'] = 'another password'
            self.assertEqual(cpu_key, key())
            config['cluster']['num_worker_nodes_gpu'] = 1
            self.assertNotEqual(cpu_key, key())


class InventoryAndImages(unittest.TestCase):
    def test_cpu_verification_skips_gpu_tasks_before_resolving_delegation(self):
        # Ansible resolves delegate_to even for an empty loop in a static role.
        # Exercise the actual optional play so CPU labs never require GPU facts.
        play = read_yaml(LAB / 'playbooks/06-verify.yml')[-1]
        play['hosts'] = 'localhost'
        play['become'] = False
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'cpu-verify.json'
            path.write_text(json.dumps([play]))
            result = run('ansible-playbook', '-i', 'localhost,', '-c', 'local', '--check', str(path),
                env={'ANSIBLE_CONFIG': str(LAB / 'ansible.cfg'),
                     'ANSIBLE_ROLES_PATH': str(LAB / 'roles')})
            self.assertIn('failed=0', result.stdout)

    def test_workers_join_isolation_and_use_their_own_cluster_api(self):
        outputs = {k: {'value': v} for k, v in {
            'mgmt_instance_public_ip': '192.0.2.1',
            'suse_ai_instance_public_ip': '192.0.2.2',
            'airgap_services_public_ip': '192.0.2.3',
            'instance_public_ip_worker_gpu': ['192.0.2.4'],
            'suse_ai_instance_public_ip_worker_gpu': ['192.0.2.5', '192.0.2.6'],
            'suse_ai_instance_public_ip_worker_nongpu': ['192.0.2.7'],
        }.items()}
        inventory = json.loads(run('jq', '--arg', 'user', 'ec2-user', '--arg', 'key', '/tmp/key',
            '-f', str(LAB / 'scripts/aws-inventory.jq'), input=json.dumps(outputs)).stdout)
        groups = inventory['all']['children']
        self.assertEqual(len(groups['aif_management']['hosts']), 1)
        self.assertEqual(len(groups['aif_workloads']['hosts']), 1)
        self.assertEqual(len(groups['aif_workers']['hosts']), 4)
        self.assertEqual(len(groups['aif_gpu_workers']['hosts']), 3)
        self.assertEqual(groups['aif_workers']['hosts']['suse-ai-wkrgpu2']['airgap_cluster_server'], 'suse-ai')
        self.assertIn('aif_workers', groups['rke2_airgap_nodes']['children'])
        self.assertIn('rke2_airgap_nodes', groups['airgap_isolated']['children'])
        self.assertNotIn('airgap_services', groups['airgap_isolated']['children'])

    def test_inventory_renderer_publishes_private_worker_bootstrap_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            lab = root / 'airgap-lab'
            (lab / 'scripts').mkdir(parents=True)
            (lab / 'generated').mkdir()
            for name in ['render-aws-inventory.sh', 'aws-inventory.jq']:
                shutil.copy2(LAB / 'scripts' / name, lab / 'scripts' / name)
            (lab / 'generated/lab-metadata.yml').write_text('workspace: fixture\n')
            (lab / 'generated/stack-vars.yml').write_text('cluster:\n  user: ec2-user\nansible_ssh_private_key_file: /tmp/key\n')
            (lab / 'generated/vars.yml').write_text('harbor_hostname: harbor.test\ngitea_hostname: gitea.test\n')
            outputs = {k: {'value': v} for k, v in {
                'mgmt_instance_public_ip': '192.0.2.1', 'mgmt_instance_private_ip': '10.0.0.1',
                'suse_ai_instance_public_ip': '192.0.2.2', 'suse_ai_instance_private_ip': '10.0.0.2',
                'airgap_services_public_ip': '192.0.2.3', 'airgap_services_private_ip': '10.0.0.3',
                'mgmt_kubeapi_fqdn': 'management.elb.example',
                'suse_ai_kubeapi_fqdn': 'downstream.elb.example',
                'suse_ai_instance_public_ip_worker_gpu': ['192.0.2.4'],
            }.items()}
            output_file = root / 'outputs.json'
            output_file.write_text(json.dumps(outputs))
            (root / 'bin').mkdir()
            tofu = root / 'bin/tofu'
            tofu.write_text('#!/bin/bash\nset -eu\n'
                'if [[ "$2" == workspace && "$3" == show ]]; then echo fixture; '
                'elif [[ "$2" == output && "$3" == -json ]]; then cat "$TEST_TOFU_OUTPUTS"; '
                'else exit 2; fi\n')
            tofu.chmod(0o755)
            run(str(lab / 'scripts/render-aws-inventory.sh'), env={
                'PATH': str(root / 'bin') + ':' + os.environ['PATH'],
                'TEST_TOFU_OUTPUTS': str(output_file)})
            variables = read_yaml(lab / 'generated/vars.yml')
            mappings = {name: record['ip'] for record in variables['airgap_host_records'] for name in record['names']}
            self.assertEqual(mappings['management.elb.example'], '10.0.0.1')
            self.assertEqual(mappings['downstream.elb.example'], '10.0.0.2')
            self.assertEqual(mappings['harbor.test'], '10.0.0.3')
            inventory = read_yaml(lab / 'generated/inventory.yml')
            self.assertEqual(inventory['all']['children']['aif_gpu_workers']['hosts']['suse-ai-wkrgpu1']['ansible_host'], '192.0.2.4')

    def test_gpu_capture_includes_init_and_future_daemonset_pods(self):
        docs = [{'items': [
            {'spec': {'containers': [{'image': 'nvcr.io/nvidia/gpu-operator:v25.10.1'}],
                      'initContainers': [{'image': 'nvcr.io/nvidia/cuda:12.8.1-base-ubuntu22.04'}]}},
            {'spec': {'template': {'spec': {'containers': [
                {'image': 'registry.k8s.io/nfd/node-feature-discovery:v0.17.3'}]}}}},
            {'kind': 'ClusterPolicy', 'spec': {
                'operator': {'initContainer': {'repository': 'nvcr.io/nvidia',
                    'image': 'cuda', 'version': '13.0.1-base-ubi9'}},
                'validator': {'repository': 'nvcr.io/nvidia', 'image': 'gpu-operator', 'version': 'v25.10.1'},
                'driver': {'enabled': False, 'repository': 'nvcr.io/nvidia', 'image': 'driver', 'version': '580.105.08'}}},
        ]}]
        artifacts = json.loads(run('jq', '-f', str(LAB / 'scripts/gpu-images.jq'), input=json.dumps(docs)).stdout)
        self.assertEqual(len(artifacts['spec']['images']), 4)
        self.assertFalse(any('/driver:' in image['source'] for image in artifacts['spec']['images']))
        self.assertEqual(artifacts['spec']['charts'], [])
        for image in artifacts['spec']['images']:
            self.assertEqual(image['target'], 'aif-images/' + image['source'])
        docs[0]['items'][0]['spec']['containers'][0]['image'] = 'unqualified:latest'
        self.assertNotEqual(run('jq', '-f', str(LAB / 'scripts/gpu-images.jq'),
                               input=json.dumps(docs), check=False).returncode, 0)

    def test_cleanup_preserves_real_and_user_created_blueprints(self):
        items = [
            {'kind': 'Blueprint', 'metadata': {'name': 'old', 'labels': {'airgap-lab.suse.com/source': 'rendered-matrix'}},
             'spec': {'components': [{'chartName': 'airgap-smoke'}]}},
            {'kind': 'Blueprint', 'metadata': {'name': 'qdrant', 'labels': {'airgap-lab.suse.com/source': 'private-gitea'}},
             'spec': {'components': [{'chartName': 'qdrant'}]}},
            {'kind': 'Blueprint', 'metadata': {'name': 'user-owned'}, 'spec': {'components': [{'chartName': 'airgap-smoke'}]}},
            {'kind': 'AIWorkload', 'metadata': {'name': 'airgap-smoke-single-gitops',
              'labels': {'airgap-lab.suse.com/source': 'rendered-matrix'}},
             'spec': {'source': {'blueprint': {'name': 'airgap-smoke-single-gitops'}}}},
            {'kind': 'AIWorkload', 'metadata': {'name': 'suse-qdrant-airgap', 'labels': {'airgap-lab.suse.com/profile': 'suse'}},
             'spec': {'source': {'blueprint': {'name': 'suse-qdrant-airgap'}}}},
        ]
        selected = json.loads(run('jq', '-f', str(LAB / 'roles/aif_airgap_catalog_cleanup/files/legacy-fixtures.jq'),
                                  input=json.dumps({'items': items})).stdout)
        self.assertEqual([x['metadata']['name'] for x in selected['items']], ['old', 'airgap-smoke-single-gitops'])


if __name__ == '__main__':
    unittest.main()
