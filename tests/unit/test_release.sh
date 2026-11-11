#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
root=$(mktemp -d)
trap 'rmdir -- "$root"' EXIT
export DEPLOYDOCK_ROOT=$root

result=0
output=$(bash scripts/deploydock deploy ./compose.yaml '../bad' 'bad' 'bad' 2>&1) || result=$?
[[ $result == 64 && $output == *'Invalid release ID'* ]]
[[ ! -e $root/state ]]
result=0
output=$(bash scripts/deploydock deploy ./compose.yaml abc123 'mutable:latest' 'mutable:latest' 2>&1) || result=$?
[[ $result == 64 && $output == *'digest-qualified'* ]]
[[ ! -e $root/state ]]
printf 'Release input checks passed.\n'
