#!/bin/sh
set -eu

root=${S_SOURCE_ROOT:-$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)}
# shellcheck source=../../src/cmd/dist/target-env.sh
. "$root/src/cmd/dist/target-env.sh"
s_target_init

printf 'host=%s/%s\n' "$S_HOST_OS" "$S_HOST_ARCH"
printf 'target=%s/%s\n' "$S_TARGET_OS" "$S_TARGET_ARCH"
if s_target_is_linux_amd64; then
    printf 'standalone_backend=linux/amd64 ELF\n'
elif [ "$S_TARGET_OS" = darwin ] && [ "$S_TARGET_ARCH" = arm64 ]; then
    printf 'standalone_backend=darwin/arm64 Mach-O (hosted)\n'
else
    printf 'standalone_backend=unavailable (implemented: linux/amd64 ELF, darwin/arm64 Mach-O hosted)\n'
fi
if s_target_needs_runner; then
    printf 'runner=required (set S_BOOTSTRAP_RUNNER for executable bootstrap stages)\n'
else
    printf 'runner=not-required\n'
fi
