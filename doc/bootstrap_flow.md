# bootstrap flow

this document is the canonical bootstrap sequence for the current `s` toolchain.

the goal is not a fully self-hosted final state yet. the goal is to keep the
current transition path explicit, reproducible, and fail-fast.

## prerequisites

- `python3`
- `cc`
- `as`
- `ld`
- a writable `tmp/` directory for bootstrap artifacts

## artifacts

- `tmp/s_compiler_stage1`: the first compiler binary produced by the bootstrap
- `tmp/s_final_compiler`: the launcher used for the current selfhosted path
- `bin/s-native`: the current native runner built from the bootstrap backend
- `bin/s-selfhosted`: the current launcher wrapper for the command surface

## sequence

1. resolve the compiler dependency graph with `misc/tools/s_resolver`
2. build `src/cmd/compile/main.s` with the initial compiler
3. require the produced `tmp/s_compiler_stage1` to be executable
4. export `S_COMPILER` and `s_compiler` to point at `tmp/s_compiler_stage1`
5. install the launcher and native runner artifacts
6. fail immediately if any output is missing

the current bootstrap driver is `misc/scripts/full_nopy_bootstrap.sh`.
when `S_COMPILER` is unset, the bootstrap scripts now prefer a repo-local
`bin/s-native` seed first, then `bin/s`, and only then the legacy
`/home/shuwen/tmp/s_compiler_improved` path.
the launcher install script now installs `bin/s-native` and `bin/s-selfhosted`
in the same pass, and can additionally materialize `s_final_compiler` for the
current bootstrap handoff.

## command surface

once the bootstrap is complete, these commands are expected to work:

- `s-native check <path> [--dump-tokens] [--dump-ast]`
- `s-native build <path> -o <output>`
- `s-native run <path>`
- `s-selfhosted check <path> [--dump-tokens] [--dump-ast]`
- `s-selfhosted build <path> -o <output>`
- `s-selfhosted run <path>`

## acceptance

the bootstrap is healthy when all of these pass:

- `misc/scripts/verify_bootstrap_flow.sh`
- `misc/scripts/check_stage2.sh`
- building `misc/examples/s/hello.s` prints `hello, world`
- building `misc/examples/s/sum.s` prints `5050`
- `src/cmd/compile/main.s` is accepted by the `check` command
