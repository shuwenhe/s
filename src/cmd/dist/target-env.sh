#!/bin/sh
# Shared host/target configuration for the bootstrap scripts.
#
# This deliberately mirrors Go's split between the machine that runs the
# compiler (S_HOST_*) and the machine that runs the produced program
# (S_TARGET_*).  A bootstrap stage is executable without an emulator only
# when those pairs are identical.

s_target_canonical_os() {
    case "$1" in
        Linux|linux) printf '%s\n' linux ;;
        Darwin|darwin|macos|macOS) printf '%s\n' darwin ;;
        Windows_NT|windows) printf '%s\n' windows ;;
        *) printf '%s\n' unknown ;;
    esac
}

s_target_canonical_arch() {
    case "$1" in
        x86_64|amd64) printf '%s\n' amd64 ;;
        aarch64|arm64) printf '%s\n' arm64 ;;
        i386|i486|i586|i686|386) printf '%s\n' 386 ;;
        *) printf '%s\n' unknown ;;
    esac
}

s_target_init() {
    S_HOST_OS=${S_HOST_OS:-$(s_target_canonical_os "$(uname -s)")}
    S_HOST_ARCH=${S_HOST_ARCH:-$(s_target_canonical_arch "$(uname -m)")}
    S_TARGET_OS=${S_TARGET_OS:-linux}
    S_TARGET_ARCH=${S_TARGET_ARCH:-amd64}
    export S_HOST_OS S_HOST_ARCH S_TARGET_OS S_TARGET_ARCH
}

s_target_is_linux_amd64() {
    [ "$S_TARGET_OS" = linux ] && [ "$S_TARGET_ARCH" = amd64 ]
}

s_target_needs_runner() {
    [ "$S_HOST_OS" != "$S_TARGET_OS" ] || [ "$S_HOST_ARCH" != "$S_TARGET_ARCH" ]
}

s_target_select_linux_amd64_tools() {
    # Homebrew provides prefixed GNU binutils on macOS.  On Linux, the normal
    # GNU tool names are the default.  Explicit S_BOOTSTRAP_* settings always
    # take precedence for cross toolchains and CI.
    if [ -z "${S_BOOTSTRAP_AS:-}" ] && [ "$S_HOST_OS" = darwin ] && command -v x86_64-elf-as >/dev/null 2>&1; then
        S_BOOTSTRAP_AS=x86_64-elf-as
    fi
    if [ -z "${S_BOOTSTRAP_LD:-}" ] && [ "$S_HOST_OS" = darwin ] && command -v x86_64-elf-ld >/dev/null 2>&1; then
        S_BOOTSTRAP_LD=x86_64-elf-ld
    fi
    if [ -z "${S_BOOTSTRAP_READELF:-}" ] && [ "$S_HOST_OS" = darwin ] && command -v x86_64-elf-readelf >/dev/null 2>&1; then
        S_BOOTSTRAP_READELF=x86_64-elf-readelf
    fi
    if [ -z "${S_BOOTSTRAP_NM:-}" ] && [ "$S_HOST_OS" = darwin ] && command -v x86_64-elf-nm >/dev/null 2>&1; then
        S_BOOTSTRAP_NM=x86_64-elf-nm
    fi
    if [ -z "${S_BOOTSTRAP_STRINGS:-}" ] && [ "$S_HOST_OS" = darwin ] && command -v x86_64-elf-strings >/dev/null 2>&1; then
        S_BOOTSTRAP_STRINGS=x86_64-elf-strings
    fi
    : "${S_BOOTSTRAP_AS:=as}"
    : "${S_BOOTSTRAP_LD:=ld}"
    : "${S_BOOTSTRAP_READELF:=readelf}"
    : "${S_BOOTSTRAP_NM:=nm}"
    : "${S_BOOTSTRAP_STRINGS:=strings}"
    export S_BOOTSTRAP_AS S_BOOTSTRAP_LD S_BOOTSTRAP_READELF S_BOOTSTRAP_NM S_BOOTSTRAP_STRINGS
}
