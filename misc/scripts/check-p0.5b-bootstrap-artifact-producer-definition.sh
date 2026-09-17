#!/usr/bin/env bash

set -euo pipefail

root="${S_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
closure="${STAGE0_CLOSURE:-"$root/.bootstrap/modular/canonical-closure.txt"}"
report="${P05B_BOOTSTRAP_ARTIFACT_PRODUCER_REPORT:-"$root/.bootstrap/modular/p0.5b-bootstrap-artifact-producer-definition.txt"}"
p05a_report="$root/.bootstrap/modular/p0.5a-first-stage1-creation-method-audit.txt"

mkdir -p "$(dirname "$report")"

has_text() {
    local pattern="$1"
    shift
    rg -q -e "$pattern" "$root/$@" 2>/dev/null
}

status_bool() {
    if "$@"; then
        echo YES
    else
        echo NO
    fi
}

read_report_field() {
    local key="$1"
    local file="$2"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { value=$2 } END { if (value != "") print value; else print "UNKNOWN" }' "$file"
    else
        echo UNKNOWN
    fi
}

closure_count=0
canonical_snapshot=NOT_FOUND
canonical_snapshot_hash=NONE
if [ -f "$closure" ]; then
    closure_count=$(wc -l <"$closure" | tr -d ' ')
    if [ "$closure_count" -gt 0 ] && grep -qx 'src/cmd/compile/modular_build_main.s' "$closure"; then
        canonical_snapshot=FOUND
    fi
    tmp_hashes="${TMPDIR:-/tmp}/s-p05b-closure-hashes.$$"
    trap 'rm -f "$tmp_hashes"' EXIT HUP INT TERM
    while IFS= read -r rel; do
        [ -z "$rel" ] && continue
        if [ -f "$root/$rel" ]; then
            shasum -a 256 "$root/$rel" | awk -v rel="$rel" '{ print $1 "  " rel }'
        else
            printf 'MISSING  %s\n' "$rel"
        fi
    done <"$closure" >"$tmp_hashes"
    canonical_snapshot_hash=$(shasum -a 256 "$tmp_hashes" | awk '{print $1}')
fi

p05a_status=$(read_report_field 'P0_5A_FIRST_STAGE1_CREATION_METHOD_AUDIT' "$p05a_report")
p05a_method=$(read_report_field 'selected-creation-method' "$p05a_report")
p05a_artifact=$(read_report_field 'selected-artifact-level' "$p05a_report")

environment_os=YES
environment_host_cc=NO
environment_linker=NO
if command -v cc >/dev/null 2>&1; then
    environment_host_cc=YES
fi
if command -v ld >/dev/null 2>&1 || command -v cc >/dev/null 2>&1; then
    environment_linker=YES
fi

mechanical_low_level_tools=$(status_bool has_text 'ELF|Mach-O|relocation|assembler|linker|emit_aot|object|native' src/cmd/compile src/cmd/dist misc/scripts makefile)
reviewed_lowered_artifact_exists=NO
if [ -f "$root/src/cmd/compile/bootstrap/stage1.lowered" ] || \
   [ -f "$root/src/cmd/compile/bootstrap/stage1.mir" ] || \
   [ -f "$root/src/cmd/compile/bootstrap/stage1.machine" ]; then
    reviewed_lowered_artifact_exists=YES
fi

explicit_producer_script="$root/src/cmd/compile/bootstrap/create_stage1_artifact.sh"
explicit_producer_exists=NO
explicit_producer_executable=NO
explicit_producer_declares_no_s_semantics=NO
explicit_producer_declares_input=NO
explicit_producer_declares_output=NO
if [ -f "$explicit_producer_script" ]; then
    explicit_producer_exists=YES
    [ -x "$explicit_producer_script" ] && explicit_producer_executable=YES
    if rg -q 'requires-independent-S-semantics=NO|semantic-responsibility=NONE|semantic-responsibility=ENCODE_ONLY' "$explicit_producer_script"; then
        explicit_producer_declares_no_s_semantics=YES
    fi
    if rg -q 'canonical-closure|stage1\.lowered|stage1\.mir|stage1\.machine|bootstrap artifact' "$explicit_producer_script"; then
        explicit_producer_declares_input=YES
    fi
    if rg -q 'native-stage1|stage1$|stage1\.manifest|creation-report' "$explicit_producer_script"; then
        explicit_producer_declares_output=YES
    fi
fi

producer_identity=UNDEFINED
producer_input=UNDEFINED
producer_output=native-stage1
producer_algorithm=UNDEFINED
producer_semantic_responsibility=UNDEFINED
requires_independent_s_semantics=UNKNOWN
bounded=NOT_PROVEN
deterministic=REQUIRED_NOT_PROVEN
reviewable=NOT_PROVEN
verdict=NO_BOUNDED_NON_SEMANTIC_PRODUCER_DEFINED
first_unproven_edge='frozen canonical closure -> provenanced native Stage1 producer'

if [ "$explicit_producer_exists" = YES ] && \
   [ "$explicit_producer_executable" = YES ] && \
   [ "$explicit_producer_declares_no_s_semantics" = YES ] && \
   [ "$explicit_producer_declares_input" = YES ] && \
   [ "$explicit_producer_declares_output" = YES ]; then
    producer_identity="$explicit_producer_script"
    producer_input="frozen canonical closure + reviewed bootstrap representation"
    producer_algorithm="bounded mechanical encoding/linking"
    producer_semantic_responsibility=NONE
    requires_independent_s_semantics=NO
    bounded=YES
    deterministic=REQUIRED
    reviewable=YES
    verdict=PRODUCER_CONTRACT_DEFINED_NOT_EXECUTED
    first_unproven_edge='producer execution and artifact validation'
elif [ "$reviewed_lowered_artifact_exists" = YES ] && [ "$mechanical_low_level_tools" = YES ]; then
    producer_identity=UNDEFINED_MECHANICAL_ENCODER_CANDIDATE
    producer_input='reviewed lowered/bootstrap representation'
    producer_algorithm='encode basic blocks/registers/calls/loads/stores/relocations'
    producer_semantic_responsibility=NONE_IF_REPRESENTATION_ALREADY_LOWERED
    requires_independent_s_semantics=NO_IF_INPUT_IS_REVIEWED_LOWERED
    bounded=POSSIBLE
    deterministic=REQUIRED_NOT_PROVEN
    reviewable=POSSIBLE
    verdict=PRODUCER_SHAPE_POSSIBLE_BUT_NOT_DEFINED
    first_unproven_edge='define explicit non-semantic producer and reviewed representation'
fi

gate=RED
if [ "$verdict" = PRODUCER_CONTRACT_DEFINED_NOT_EXECUTED ]; then
    gate=YELLOW
fi

{
    echo "P0.5b BOOTSTRAP_ARTIFACT_PRODUCER_DEFINITION"
    echo "P0_5B_BOOTSTRAP_ARTIFACT_PRODUCER=$gate"
    echo
    echo "source:"
    echo "  kind=frozen canonical closure"
    echo "  path=$closure"
    echo "  count=$closure_count"
    echo "  hash=$canonical_snapshot_hash"
    echo "  status=$canonical_snapshot"
    echo
    echo "environment:"
    echo "  os-loader=$environment_os"
    echo "  host-cc=$environment_host_cc"
    echo "  linker=$environment_linker"
    echo "  selected-ceremony-from-p0.5a=$p05a_method"
    echo "  selected-artifact-level-from-p0.5a=$p05a_artifact"
    echo "  note=environment-is-not-producer"
    echo
    echo "producer:"
    echo "  identity=$producer_identity"
    echo "  input=$producer_input"
    echo "  output=$producer_output"
    echo "  algorithm=$producer_algorithm"
    echo "  semantic-responsibility=$producer_semantic_responsibility"
    echo
    echo "producer-contract:"
    echo "  requires-independent-S-semantics=$requires_independent_s_semantics"
    echo "  bounded=$bounded"
    echo "  deterministic=$deterministic"
    echo "  reviewable=$reviewable"
    echo "  long-term-semantic-authority=FORBIDDEN"
    echo "  creation-authority-lifetime=ONE_TIME"
    echo
    echo "rejection-rules:"
    echo "  parses-S=REJECT_THIRD_COMPILER"
    echo "  resolves-types=REJECT_THIRD_COMPILER"
    echo "  instantiates-generics=REJECT_THIRD_COMPILER"
    echo "  resolves-methods=REJECT_THIRD_COMPILER"
    echo "  performs-ownership-or-borrow-or-NLL=REJECT_THIRD_COMPILER"
    echo "  lowers-S-AST-to-MIR=REJECT_THIRD_COMPILER"
    echo
    echo "allowed-producer-responsibility:"
    echo "  basic-block-encoding=YES"
    echo "  register-or-stack-slot-encoding=YES"
    echo "  calls-loads-stores-encoding=YES"
    echo "  relocation-encoding=YES"
    echo "  object-or-native-container-encoding=YES"
    echo "  S-parser-semantic-generic-method-ownership=NO"
    echo
    echo "candidate-shapes:"
    echo "  canonical-source-to-native:"
    echo "    producer-semantic-responsibility=parse+semantic+generic+method+ownership+mir"
    echo "    verdict=REJECT_THIRD_COMPILER"
    echo "  reviewed-lowered-representation-to-native:"
    echo "    producer-semantic-responsibility=encoding-only"
    echo "    verdict=POSSIBLE_IF_REPRESENTATION_AND_ENCODER_ARE_DEFINED"
    echo "  recovered-native-artifact:"
    echo "    producer-semantic-responsibility=none-in-repo"
    echo "    verdict=PREFERRED_IF_PROVENANCE_EXISTS_BUT_P0.4_FOUND_NONE"
    echo
    echo "existing-evidence:"
    echo "  mechanical-low-level-tools=$mechanical_low_level_tools"
    echo "  reviewed-lowered-artifact-exists=$reviewed_lowered_artifact_exists"
    echo "  explicit-producer-script=$explicit_producer_script"
    echo "  explicit-producer-exists=$explicit_producer_exists"
    echo "  explicit-producer-executable=$explicit_producer_executable"
    echo "  explicit-producer-declares-no-s-semantics=$explicit_producer_declares_no_s_semantics"
    echo "  explicit-producer-declares-input=$explicit_producer_declares_input"
    echo "  explicit-producer-declares-output=$explicit_producer_declares_output"
    echo
    echo "verdict=$verdict"
    echo "first-unproven-edge=$first_unproven_edge"
    echo
    echo "Trusted Environment != Trusted Producer != Semantic Authority"
    echo "trusted-environment=host OS/toolchain/permitted tooling"
    echo "trusted-producer=one-time bounded mechanical producer only"
    echo "semantic-authority=canonical S source"
    echo
    echo "DO_NOT_GENERATE_STAGE1_IN_P0_5B=YES"
    echo "DO_NOT_FIX_ABIUTILS_144=YES"
    echo "DO_NOT_FIX_HISTORICAL_IS_ERR=YES"
    echo "DO_NOT_IMPLEMENT_THIRD_COMPILER=YES"
} | tee "$report"

[ "$gate" = GREEN ]
