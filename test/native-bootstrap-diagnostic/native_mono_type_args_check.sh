#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d /tmp/s-mono-type-args.XXXXXX)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]); work=Path(sys.argv[2])
source=(root/'src/cmd/compile/internal/mono/monomorphization.s').read_text()
def function(name):
    start=source.index('func '+name+'('); end=source.find('\nfunc ',start+1)
    return source[start:end if end>=0 else len(source)]
start=source.index('struct generic_instance_key {'); end=source.index('struct mono_ownership_summary {',start)
# Isolate the production cache and key lookup. Exact primitive spellings are
# sufficient here; type-alias normalization belongs to the type-system suite.
fixture='''package main
'''+source[start:end]+'''
func same_type_args(string[] left, string[] right) bool {
    if len(left) != len(right) { return false }
    i := 0
    for i < len(left) {
        if left[i] != right[i] { return false }
        i = i + 1
    }
    return true
}
'''+ '\n'.join(function(n) for n in ('mono_cache_lookup','mono_cache_lookup_item','mono_cache_lookup_key'))+'''
func main() int {
    entries := mono_instance[]()
    entries.push(mono_instance { item_kind: "function", receiver_type: "", generic_name: "id", instance_name: "id_int", type_args: ["int"] })
    entries.push(mono_instance { item_kind: "function", receiver_type: "", generic_name: "id", instance_name: "id_string", type_args: ["string"] })
    cache := mono_cache { instances: entries }
    if mono_cache_lookup_key(cache, generic_instance_key { function_name: "id", type_args: ["int"] }) != "id_int" { return 1 }
    if mono_cache_lookup_key(cache, generic_instance_key { function_name: "id", type_args: ["string"] }) != "id_string" { return 2 }
    if mono_cache_lookup_key(cache, generic_instance_key { function_name: "id", type_args: ["bool"] }) != "" { return 3 }
    return 42
}
'''
(work/'cache.s').write_text(fixture)
PY
"$root/bin/s_seed" --compile-native-unit "$work/cache.ir" "$work/cache.s"
S_SOURCE_ROOT="$root" "$root/bin/s_seed" --emit-standalone-amd64 "$work/cache.ir" "$work/cache"
status=0; timeout 15 "$work/cache" || status=$?; test "$status" -eq 42
echo 'production mono cache distinguishes declared type arguments: PASS'
