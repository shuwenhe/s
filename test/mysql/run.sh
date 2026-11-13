#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-mysql-crud.XXXXXX)
trap 'rm -rf "$work"' EXIT HUP INT TERM
python3 "$root/misc/scripts/build-openssl-client.py" "$root/test/mysql/crud/main.s" -o "$work/crud"
"$work/crud"
