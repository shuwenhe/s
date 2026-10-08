#!/bin/sh
set -u

root=${S_SOURCE_ROOT:-$(pwd)}
work=${1:-"$root/.bootstrap/stage2-stage3-diagnostic"}
stage2=${S_STAGE2_COMPILER:-"$root/.bootstrap/selfhost/native/stage2"}
source_file=${S_BOOTSTRAP_SOURCE:-"$root/src/cmd/compile/selfhost/compiler.s"}
runtime_object=${S_BOOTSTRAP_RUNTIME_OBJECT:-"$root/.bootstrap/selfhost/native/selfhost_runtime.o"}
linker_script=${S_BOOTSTRAP_LINKER_SCRIPT:-"$root/src/runtime/linker/nostdlib.ld"}
timeout_seconds=${S_BOOTSTRAP_TIMEOUT:-120}

if [ -f "$root/src/cmd/dist/target-env.sh" ]; then
    . "$root/src/cmd/dist/target-env.sh"
    s_target_init
    s_target_select_linux_amd64_tools
else
    S_TARGET_OS=${S_TARGET_OS:-linux}
    S_TARGET_ARCH=${S_TARGET_ARCH:-amd64}
    S_BOOTSTRAP_AS=${S_BOOTSTRAP_AS:-as}
    S_BOOTSTRAP_LD=${S_BOOTSTRAP_LD:-ld}
fi

assembler=$S_BOOTSTRAP_AS
linker=$S_BOOTSTRAP_LD
runner=${S_BOOTSTRAP_RUNNER:-}

report="$work/stage2-stage3-memory-report.txt"
stage3_asm="$work/stage3.S"
stage3_obj="$work/stage3.o"
stage3_bin="$work/stage3"

mkdir -p "$work"

git_commit() {
    git -C "$root" rev-parse HEAD 2>/dev/null || printf '%s\n' unknown
}

file_state() {
    if [ -f "$1" ]; then
        printf '%s\n' present
    else
        printf '%s\n' absent
    fi
}

file_size() {
    if [ -f "$1" ]; then
        wc -c <"$1" | tr -d ' '
    else
        printf '%s\n' 0
    fi
}

run_measured() {
    phase=$1
    shift
    out="$work/$phase.out"
    err="$work/$phase.err"
    metrics_file="$work/$phase.metrics"
    rm -f "$out" "$err" "$metrics_file"

    set +e
    "$@" >"$out" 2>"$err" &
    pid=$!

    max_rss=0
    max_vms=0
    start_epoch=$(date +%s)
    timed_out=0

    while kill -0 "$pid" 2>/dev/null; do
        if [ -r "/proc/$pid/status" ]; then
            rss=$(awk '$1 == "VmRSS:" { print $2 }' "/proc/$pid/status" 2>/dev/null)
            vms=$(awk '$1 == "VmSize:" { print $2 }' "/proc/$pid/status" 2>/dev/null)
        else
            rss=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{ print $1 }')
            vms=$(ps -o vsz= -p "$pid" 2>/dev/null | awk '{ print $1 }')
        fi

        case ${rss:-} in ''|*[!0-9]*) rss=0 ;; esac
        case ${vms:-} in ''|*[!0-9]*) vms=0 ;; esac
        [ "$rss" -gt "$max_rss" ] && max_rss=$rss
        [ "$vms" -gt "$max_vms" ] && max_vms=$vms

        now_epoch=$(date +%s)
        if [ $((now_epoch - start_epoch)) -ge "$timeout_seconds" ]; then
            timed_out=1
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null
            break
        fi

        sleep 1
    done

    wait "$pid"
    status=$?
    end_epoch=$(date +%s)
    if [ "$timed_out" = 1 ]; then
        status=124
    fi
    set -e

    printf '%s\n' "$status" >"$work/$phase.status"
    {
        printf 'max-rss-kb=%s\n' "$max_rss"
        printf 'max-vms-kb=%s\n' "$max_vms"
        printf 'elapsed-seconds=%s\n' $((end_epoch - start_epoch))
    } >"$metrics_file"
}

run_stage2_measured() {
    phase=$1
    shift
    if [ -n "$runner" ]; then
        run_measured "$phase" "$runner" "$@"
    else
        run_measured "$phase" "$@"
    fi
}

metric_from_phase() {
    phase=$1
    key=$2
    file="$work/$phase.metrics"
    if [ -f "$file" ]; then
        awk -F= -v key="$key" '$1 == key { print $2; found=1 } END { if (!found) print "unknown" }' "$file"
    else
        printf '%s\n' unknown
    fi
}

phase_status() {
    if [ -f "$work/$1.status" ]; then
        cat "$work/$1.status"
    else
        printf '%s\n' not-run
    fi
}

write_report() {
    compile_status=$(phase_status compile)
    assemble_status=$(phase_status assemble)
    link_status=$(phase_status link)

    result=INCONCLUSIVE
    if [ "$compile_status" = 0 ] && [ "$assemble_status" = 0 ] && [ "$link_status" = 0 ] && [ -f "$stage3_bin" ]; then
        result=PASS_STAGE3_GENERATED
    elif [ "$compile_status" != 0 ]; then
        result=FAIL_COMPILE
    elif [ "$assemble_status" != 0 ]; then
        result=FAIL_ASSEMBLE
    elif [ "$link_status" != 0 ]; then
        result=FAIL_LINK
    fi

    {
        printf '%s\n' 's-stage2-stage3-memory-diagnostic-v1'
        printf 'git-commit=%s\n' "$(git_commit)"
        printf '%s\n' 'step=stage2-to-stage3'
        printf 'work=%s\n' "$work"
        printf 'stage2=%s\n' "$stage2"
        printf 'source=%s\n' "$source_file"
        printf 'target=%s/%s\n' "$S_TARGET_OS" "$S_TARGET_ARCH"
        if [ -n "$runner" ]; then
            printf 'runner=%s\n' "$runner"
        else
            printf '%s\n' 'runner=none'
        fi
        printf 'assembler=%s\n' "$assembler"
        printf 'linker=%s\n' "$linker"
        printf 'timeout-seconds=%s\n' "$timeout_seconds"

        for phase in compile assemble link; do
            printf 'phase.%s.stage=[3/7] stage2 -> stage3 / %s\n' "$phase" "$phase"
            printf 'phase.%s.status=%s\n' "$phase" "$(phase_status "$phase")"
            printf 'phase.%s.max-rss-kb=%s\n' "$phase" "$(metric_from_phase "$phase" max-rss-kb)"
            printf 'phase.%s.max-vms-kb=%s\n' "$phase" "$(metric_from_phase "$phase" max-vms-kb)"
            printf 'phase.%s.elapsed-seconds=%s\n' "$phase" "$(metric_from_phase "$phase" elapsed-seconds)"
            printf 'phase.%s.stdout=%s\n' "$phase" "$work/$phase.out"
            printf 'phase.%s.stderr=%s\n' "$phase" "$work/$phase.err"
            printf 'phase.%s.metrics=%s\n' "$phase" "$work/$phase.metrics"
        done

        printf 'artifact.stage3.S=%s\n' "$(file_state "$stage3_asm")"
        printf 'artifact.stage3.S.bytes=%s\n' "$(file_size "$stage3_asm")"
        printf 'artifact.stage3.o=%s\n' "$(file_state "$stage3_obj")"
        printf 'artifact.stage3.o.bytes=%s\n' "$(file_size "$stage3_obj")"
        printf 'artifact.stage3=%s\n' "$(file_state "$stage3_bin")"
        printf 'artifact.stage3.bytes=%s\n' "$(file_size "$stage3_bin")"
        printf 'result=%s\n' "$result"
    } >"$report"
}

set -e

if [ ! -x "$stage2" ]; then
    printf '%s\n' "stage2 compiler not executable: $stage2" >&2
    write_report
    exit 2
fi

if [ ! -f "$source_file" ]; then
    printf '%s\n' "compiler source not found: $source_file" >&2
    write_report
    exit 2
fi

run_stage2_measured compile "$stage2" --emit-asm "$source_file" "$stage3_asm"

if [ "$(phase_status compile)" = 0 ]; then
    run_measured assemble "$assembler" --64 -o "$stage3_obj" "$stage3_asm"
fi

if [ "$(phase_status compile)" = 0 ] && [ "$(phase_status assemble)" = 0 ]; then
    run_measured link "$linker" -static -T "$linker_script" -o "$stage3_bin" "$runtime_object" "$stage3_obj"
fi

write_report

cat "$report"

case "$(awk -F= '$1 == "result" { print $2 }' "$report")" in
    PASS_STAGE3_GENERATED) exit 0 ;;
    *) exit 1 ;;
esac
