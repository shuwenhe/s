#!/bin/sh
set -eu

SOURCE_ROOT="${1:-${S_SOURCE_ROOT:-.}}"
COMPILER="${SOURCE_ROOT}/bin/s_compiler"
REPORT="${SOURCE_ROOT}/.bootstrap/stage12/canonical-ownership-gate.txt"
RAW_STAGE11="${REPORT}.stage11.raw.$$"
RAW_STAGE12="${REPORT}.stage12.raw.$$"
TMP_REPORT="${REPORT}.tmp.$$"

mkdir -p "$(dirname "$REPORT")"
trap 'rm -f "$RAW_STAGE11" "$RAW_STAGE12" "$TMP_REPORT"' EXIT HUP INT TERM

proof_value() {
    local key=$1
    local file=$2
    sed -n "s/^${key}=//p" "$file" | tail -n 1
}

write_s12_fail_report() {
    local contract=$1
    local reason=$2
    if [ "$contract" = "S12.4" ] && [ -z "$reason" ]; then
        reason="no observable Stage 12 ref-to-loan binding facts producer"
    fi
    if [ "$contract" = "S12.5" ] && [ -z "$reason" ]; then
        reason="no observable Stage 12 region point seed facts producer"
    fi
    if [ "$contract" = "S12.6" ] && [ -z "$reason" ]; then
        reason="no observable Stage 12 ref-use region point facts producer"
    fi
    {
        echo "STAGE 12 - OWNERSHIP / MOVE / BORROW / NLL"
        echo "Scope: Stage 12 gate only; canonical MIR input boundary before ownership analysis"
        echo "Monomorphization/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage12-ownership-gate"
        if [ "$contract" = "S12.2" ]; then
            echo "S12.1=PASS"
            echo "S12.1.evidence=$(proof_value S12.1.evidence "$RAW_STAGE12")"
            echo "S12.2=FAIL"
            echo "S12.2.reason=$reason"
        elif [ "$contract" = "S12.3" ] || [ "$contract" = "S12.4" ] || [ "$contract" = "S12.5" ] || [ "$contract" = "S12.6" ]; then
            echo "S12.1=PASS"
            echo "S12.1.evidence=$(proof_value S12.1.evidence "$RAW_STAGE12")"
            echo "S12.2=PASS"
            echo "S12.2.input-authority=$(proof_value S12.2.input-authority "$RAW_STAGE12")"
            echo "S12.2.analysis-authority=$(proof_value S12.2.analysis-authority "$RAW_STAGE12")"
            echo "S12.2.move-count=$(proof_value S12.2.move-count "$RAW_STAGE12")"
            echo "S12.2.mir-reconstruction=$(proof_value S12.2.mir-reconstruction "$RAW_STAGE12")"
            if [ "$contract" = "S12.4" ] || [ "$contract" = "S12.5" ] || [ "$contract" = "S12.6" ]; then
                echo "S12.3=PASS"
                echo "S12.3.contract=$(proof_value S12.3.contract "$RAW_STAGE12")"
                echo "S12.3.input-authority=$(proof_value S12.3.input-authority "$RAW_STAGE12")"
                echo "S12.3.analysis-authority=$(proof_value S12.3.analysis-authority "$RAW_STAGE12")"
                echo "S12.3.loan-count=$(proof_value S12.3.loan-count "$RAW_STAGE12")"
                echo "S12.3.mir-reconstruction=$(proof_value S12.3.mir-reconstruction "$RAW_STAGE12")"
                if [ "$contract" = "S12.5" ] || [ "$contract" = "S12.6" ]; then
                    echo "S12.4=PASS"
                    echo "S12.4.contract=$(proof_value S12.4.contract "$RAW_STAGE12")"
                    echo "S12.4.input-authority=$(proof_value S12.4.input-authority "$RAW_STAGE12")"
                    echo "S12.4.analysis-authority=$(proof_value S12.4.analysis-authority "$RAW_STAGE12")"
                    echo "S12.4.binding=$(proof_value S12.4.binding "$RAW_STAGE12")"
                    echo "S12.4.mir-reconstruction=$(proof_value S12.4.mir-reconstruction "$RAW_STAGE12")"
                    if [ "$contract" = "S12.6" ]; then
                        echo "S12.5=PASS"
                        echo "S12.5.contract=$(proof_value S12.5.contract "$RAW_STAGE12")"
                        echo "S12.5.input-authority=$(proof_value S12.5.input-authority "$RAW_STAGE12")"
                        echo "S12.5.analysis-authority=$(proof_value S12.5.analysis-authority "$RAW_STAGE12")"
                        echo "S12.5.region=$(proof_value S12.5.region "$RAW_STAGE12")"
                        echo "S12.5.point=$(proof_value S12.5.point "$RAW_STAGE12")"
                        echo "S12.5.mir-reconstruction=$(proof_value S12.5.mir-reconstruction "$RAW_STAGE12")"
                        echo "S12.6=FAIL"
                        echo "S12.6.reason=$reason"
                    else
                        echo "S12.5=FAIL"
                        echo "S12.5.reason=$reason"
                    fi
                else
                    echo "S12.4=FAIL"
                    echo "S12.4.reason=$reason"
                fi
            else
                echo "S12.3=FAIL"
                echo "S12.3.reason=$reason"
            fi
        else
            echo "S12.1=FAIL"
            echo "S12.1.reason=$reason"
        fi
        echo "first-unmet-contract=$contract"
        echo "reason=$reason"
        echo "stage12-ownership=NOT_CLOSED"
        echo "result=FAIL"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 1
}

write_s12_pass_report() {
    {
        echo "STAGE 12 - OWNERSHIP / MOVE / BORROW / NLL"
        echo "Scope: Stage 12 gate only; canonical MIR input boundary before ownership analysis"
        echo "Monomorphization/layout/ABI/codegen success is NOT required."
        echo "compiler=$COMPILER"
        echo "proof-source=stage12-ownership-gate"
        echo "S12.1=PASS"
        echo "S12.1.evidence=$(proof_value S12.1.evidence "$RAW_STAGE12")"
        echo "S12.2=PASS"
        echo "S12.2.input-authority=$(proof_value S12.2.input-authority "$RAW_STAGE12")"
        echo "S12.2.analysis-authority=$(proof_value S12.2.analysis-authority "$RAW_STAGE12")"
        echo "S12.2.move-count=$(proof_value S12.2.move-count "$RAW_STAGE12")"
        echo "S12.2.move.point=$(proof_value S12.2.move.point "$RAW_STAGE12")"
        echo "S12.2.move.source=$(proof_value S12.2.move.source "$RAW_STAGE12")"
        echo "S12.2.move.target=$(proof_value S12.2.move.target "$RAW_STAGE12")"
        echo "S12.2.mir-reconstruction=$(proof_value S12.2.mir-reconstruction "$RAW_STAGE12")"
        echo "S12.3=PASS"
        echo "S12.3.contract=$(proof_value S12.3.contract "$RAW_STAGE12")"
        echo "S12.3.input-authority=$(proof_value S12.3.input-authority "$RAW_STAGE12")"
        echo "S12.3.analysis-authority=$(proof_value S12.3.analysis-authority "$RAW_STAGE12")"
        echo "S12.3.loan-count=$(proof_value S12.3.loan-count "$RAW_STAGE12")"
        echo "S12.3.loan.point=$(proof_value S12.3.loan.point "$RAW_STAGE12")"
        echo "S12.3.loan.ref=$(proof_value S12.3.loan.ref "$RAW_STAGE12")"
        echo "S12.3.loan.place=$(proof_value S12.3.loan.place "$RAW_STAGE12")"
        echo "S12.3.loan.mutable=$(proof_value S12.3.loan.mutable "$RAW_STAGE12")"
        echo "S12.3.mir-reconstruction=$(proof_value S12.3.mir-reconstruction "$RAW_STAGE12")"
        echo "S12.3.evidence=$(proof_value S12.3.evidence "$RAW_STAGE12")"
        echo "S12.4=PASS"
        echo "S12.4.contract=$(proof_value S12.4.contract "$RAW_STAGE12")"
        echo "S12.4.input-authority=$(proof_value S12.4.input-authority "$RAW_STAGE12")"
        echo "S12.4.analysis-authority=$(proof_value S12.4.analysis-authority "$RAW_STAGE12")"
        echo "S12.4.ref=$(proof_value S12.4.ref "$RAW_STAGE12")"
        echo "S12.4.ref-id=$(proof_value S12.4.ref-id "$RAW_STAGE12")"
        echo "S12.4.loan-id=$(proof_value S12.4.loan-id "$RAW_STAGE12")"
        echo "S12.4.binding=$(proof_value S12.4.binding "$RAW_STAGE12")"
        echo "S12.4.mir-reconstruction=$(proof_value S12.4.mir-reconstruction "$RAW_STAGE12")"
        echo "S12.4.evidence=$(proof_value S12.4.evidence "$RAW_STAGE12")"
        echo "S12.5=PASS"
        echo "S12.5.contract=$(proof_value S12.5.contract "$RAW_STAGE12")"
        echo "S12.5.input-authority=$(proof_value S12.5.input-authority "$RAW_STAGE12")"
        echo "S12.5.analysis-authority=$(proof_value S12.5.analysis-authority "$RAW_STAGE12")"
        echo "S12.5.region=$(proof_value S12.5.region "$RAW_STAGE12")"
        echo "S12.5.point=$(proof_value S12.5.point "$RAW_STAGE12")"
        echo "S12.5.mir-reconstruction=$(proof_value S12.5.mir-reconstruction "$RAW_STAGE12")"
        echo "S12.5.evidence=$(proof_value S12.5.evidence "$RAW_STAGE12")"
        echo "S12.6=PASS"
        echo "S12.6.contract=$(proof_value S12.6.contract "$RAW_STAGE12")"
        echo "S12.6.input-authority=$(proof_value S12.6.input-authority "$RAW_STAGE12")"
        echo "S12.6.analysis-authority=$(proof_value S12.6.analysis-authority "$RAW_STAGE12")"
        echo "S12.6.region=$(proof_value S12.6.region "$RAW_STAGE12")"
        echo "S12.6.point=$(proof_value S12.6.point "$RAW_STAGE12")"
        echo "S12.6.mir-reconstruction=$(proof_value S12.6.mir-reconstruction "$RAW_STAGE12")"
        echo "S12.6.evidence=$(proof_value S12.6.evidence "$RAW_STAGE12")"
        echo "first-unmet-contract=S12.7"
        echo "stage12-ownership=NOT_CLOSED"
        echo "result=PASS"
    } > "$TMP_REPORT"
    mv "$TMP_REPORT" "$REPORT"
    cat "$REPORT"
    return 0
}

if [ ! -x "$COMPILER" ]; then
    write_s12_fail_report "S12.1" "no executable compiler available to observe Stage11 MIR verification output"
    exit $?
fi

input="${S_STAGE12_PROOF_INPUT:-$SOURCE_ROOT/test/compiler/stage12_move_semantics_real.s}"

"$COMPILER" canonical-mir-verification-proof "$input" "$RAW_STAGE11" || true

if [ ! -f "$RAW_STAGE11" ] || [ "$(proof_value S11.1 "$RAW_STAGE11")" != "PASS" ]; then
    write_s12_fail_report "S12.1" "Stage11 canonical MIR verification was not closed"
    exit $?
fi

if [ "$(proof_value S11.1.input-authority "$RAW_STAGE11")" != "stage10-canonical-mir-output" ] ||
   [ "$(proof_value S11.1.mir-input-consumed "$RAW_STAGE11")" != "yes" ] ||
   [ "$(proof_value S11.1.mir-reconstruction "$RAW_STAGE11")" != "no" ]; then
    write_s12_fail_report "S12.1" "Stage11 did not expose a clean canonical MIR handoff for Stage12"
    exit $?
fi

if "$COMPILER" canonical-ownership-proof "$input" "$RAW_STAGE12" >/dev/null 2>&1; then
    if [ "$(proof_value S12.1 "$RAW_STAGE12")" = "PASS" ] &&
       [ "$(proof_value S12.1.input-authority "$RAW_STAGE12")" = "stage11-verified-canonical-mir" ] &&
       [ "$(proof_value S12.1.mir-input-consumed "$RAW_STAGE12")" = "yes" ] &&
       [ "$(proof_value S12.1.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
       [ -n "$(proof_value S12.1.evidence "$RAW_STAGE12")" ]; then
        if [ "$(proof_value S12.2 "$RAW_STAGE12")" = "PASS" ] &&
           [ "$(proof_value S12.2.input-authority "$RAW_STAGE12")" = "stage10-canonical-mir" ] &&
           [ "$(proof_value S12.2.analysis-authority "$RAW_STAGE12")" = "build_ownership_facts_from_mir" ] &&
           [ "$(proof_value S12.2.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
           [ -n "$(proof_value S12.2.move-count "$RAW_STAGE12")" ] &&
           [ "$(proof_value S12.2.move-count "$RAW_STAGE12")" -gt 0 ] &&
           [ -n "$(proof_value S12.2.move.point "$RAW_STAGE12")" ] &&
           [ -n "$(proof_value S12.2.move.source "$RAW_STAGE12")" ] &&
           [ -n "$(proof_value S12.2.move.target "$RAW_STAGE12")" ]; then
            if [ "$(proof_value S12.3 "$RAW_STAGE12")" = "PASS" ] &&
               [ "$(proof_value S12.3.contract "$RAW_STAGE12")" = "loan-issuance-facts" ] &&
               [ "$(proof_value S12.3.input-authority "$RAW_STAGE12")" = "stage10-canonical-mir" ] &&
               [ "$(proof_value S12.3.analysis-authority "$RAW_STAGE12")" = "build_ownership_facts_from_mir" ] &&
               [ "$(proof_value S12.3.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
               [ -n "$(proof_value S12.3.loan-count "$RAW_STAGE12")" ] &&
               [ "$(proof_value S12.3.loan-count "$RAW_STAGE12")" -gt 0 ] &&
               [ -n "$(proof_value S12.3.loan.point "$RAW_STAGE12")" ] &&
               [ -n "$(proof_value S12.3.loan.ref "$RAW_STAGE12")" ] &&
               [ -n "$(proof_value S12.3.loan.place "$RAW_STAGE12")" ] &&
               [ -n "$(proof_value S12.3.loan.mutable "$RAW_STAGE12")" ] &&
               [ -n "$(proof_value S12.3.evidence "$RAW_STAGE12")" ]; then
                if [ "$(proof_value S12.4 "$RAW_STAGE12")" = "PASS" ] &&
                   [ "$(proof_value S12.4.contract "$RAW_STAGE12")" = "ref-loan-binding-facts" ] &&
                   [ "$(proof_value S12.4.input-authority "$RAW_STAGE12")" = "stage10-canonical-mir" ] &&
                   [ "$(proof_value S12.4.analysis-authority "$RAW_STAGE12")" = "build_ownership_facts_from_mir" ] &&
                   [ "$(proof_value S12.4.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
                   [ -n "$(proof_value S12.4.ref "$RAW_STAGE12")" ] &&
                   [ -n "$(proof_value S12.4.ref-id "$RAW_STAGE12")" ] &&
                   [ -n "$(proof_value S12.4.loan-id "$RAW_STAGE12")" ] &&
                   [ -n "$(proof_value S12.4.binding "$RAW_STAGE12")" ] &&
                   [ -n "$(proof_value S12.4.evidence "$RAW_STAGE12")" ]; then
                    if [ "$(proof_value S12.5 "$RAW_STAGE12")" = "PASS" ] &&
                       [ "$(proof_value S12.5.contract "$RAW_STAGE12")" = "region-point-seed-facts" ] &&
                       [ "$(proof_value S12.5.input-authority "$RAW_STAGE12")" = "stage10-canonical-mir" ] &&
                       [ "$(proof_value S12.5.analysis-authority "$RAW_STAGE12")" = "build_ownership_facts_from_mir" ] &&
                       [ "$(proof_value S12.5.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
                       [ -n "$(proof_value S12.5.region "$RAW_STAGE12")" ] &&
                       [ -n "$(proof_value S12.5.point "$RAW_STAGE12")" ] &&
                       [ -n "$(proof_value S12.5.evidence "$RAW_STAGE12")" ]; then
                        if [ "$(proof_value S12.6 "$RAW_STAGE12")" = "PASS" ] &&
                           [ "$(proof_value S12.6.contract "$RAW_STAGE12")" = "ref-use-region-point-facts" ] &&
                           [ "$(proof_value S12.6.input-authority "$RAW_STAGE12")" = "stage10-canonical-mir" ] &&
                           [ "$(proof_value S12.6.analysis-authority "$RAW_STAGE12")" = "build_ownership_facts_from_mir" ] &&
                           [ "$(proof_value S12.6.mir-reconstruction "$RAW_STAGE12")" = "no" ] &&
                           [ -n "$(proof_value S12.6.region "$RAW_STAGE12")" ] &&
                           [ -n "$(proof_value S12.6.point "$RAW_STAGE12")" ] &&
                           [ "$(proof_value S12.6.point "$RAW_STAGE12")" != "$(proof_value S12.5.point "$RAW_STAGE12")" ] &&
                           [ -n "$(proof_value S12.6.evidence "$RAW_STAGE12")" ] &&
                           [ "$(proof_value first-unmet-contract "$RAW_STAGE12")" = "S12.7" ]; then
                            write_s12_pass_report
                            exit $?
                        fi
                        if [ "$(proof_value first-unmet-contract "$RAW_STAGE12")" = "S12.6" ]; then
                            write_s12_fail_report "S12.6" "$(proof_value S12.6.reason "$RAW_STAGE12")"
                            exit $?
                        fi
                        write_s12_fail_report "S12.6" "no observable Stage 12 ref-use region point facts producer"
                        exit $?
                    fi
                    if [ "$(proof_value first-unmet-contract "$RAW_STAGE12")" = "S12.5" ]; then
                        write_s12_fail_report "S12.5" "$(proof_value S12.5.reason "$RAW_STAGE12")"
                        exit $?
                    fi
                    write_s12_fail_report "S12.5" "no observable Stage 12 region point seed facts producer"
                    exit $?
                fi
                if [ "$(proof_value first-unmet-contract "$RAW_STAGE12")" = "S12.4" ]; then
                    write_s12_fail_report "S12.4" "$(proof_value S12.4.reason "$RAW_STAGE12")"
                    exit $?
                fi
                write_s12_fail_report "S12.4" "no observable Stage 12 ref-to-loan binding facts producer"
                exit $?
            fi
            write_s12_fail_report "S12.3" "$(proof_value S12.3.reason "$RAW_STAGE12")"
            exit $?
        fi
        write_s12_fail_report "S12.2" "$(proof_value S12.2.reason "$RAW_STAGE12")"
        exit $?
    fi
fi

write_s12_fail_report "S12.1" "no observable Stage 12 proof producer"
exit $?
