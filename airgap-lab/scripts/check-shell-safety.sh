#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

unsafe="$(grep -RIn --include='*.yml' --include='*.yaml' \
  'set -o pipefail' "${lab_dir}" || true)"
if [[ -n "${unsafe}" ]]; then
  printf '%s\n' 'Unsafe Ansible shell blocks use pipefail without errexit:' >&2
  printf '%s\n' "${unsafe}" >&2
  printf '%s\n' 'Use set -euo pipefail, or implement and document explicit status handling.' >&2
  exit 1
fi

printf 'Ansible shell safety check passed.\n'
