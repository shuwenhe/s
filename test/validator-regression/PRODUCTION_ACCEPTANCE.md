# Production Validator acceptance

`production_acceptance_check.py` executes native ELF probes containing the real
MIR/SSA validators and AMD64 validator/emitter. It extracts their complete
function dependency closure, without replacing validation helpers. Constructed
objects reach the validators directly. Compilation, parsing, assembly, linking,
and execution must all succeed; parser failures never count as rejections.

Run from any directory:

```sh
python3 test/validator-regression/production_acceptance_check.py \
  --seed /absolute/path/to/s_seed \
  --compiler-a /absolute/path/to/compiler-A \
  --compiler-b /absolute/path/to/compiler-B \
  --output /tmp/validator-acceptance
```

The optional compiler pair checks a separate production CLI pipeline: both
compilers compile the same call/arithmetic program, produce identical assembly,
link ELF executables, and execute with exit 42. Without the pair, all object
validation, matrix, and production emitter probes still run. The default A
source revision is `ec8737231`, the strict MIR restoration. B uses the current
checkout. `--sizes 16 64` is a quick run; the default includes 16/64/256/1024.

The output directory retains every generated source, IR, assembly, object,
executable, diagnostic stream, and `results.json`. Assembly from the real
`emit_function_ssa_amd64` is included in the compared diagnostic stream, so its
byte parity is checked along with exact errors.

## Required negative controls

| Case | Exact production diagnostic |
| --- | --- |
| Undefined SSA value | `unknown operand: sample.main` |
| InvalidDominance | `nondominating operand: sample.main` |
| PhiInputs | `phi operand count: sample.main` |
| OperandID | `duplicate value: sample.main` |
| TypeMismatch | `return type: sample.main` |
| InvalidReference | `SSA reference operand referent type` |
| CFGEdge | `inconsistent successor edge: sample.main` |
| AMD64ABIcall | `amd64: call argument type: sample.external` |

Positive controls cover MIR, a scalar SSA function, a diamond CFG, and AMD64
validation/emission. An additional strictness control requires rejection of an
unknown MIR reference type, with exact error
`unproven reference parameter: sample.main.x (&missing)`.

## Optimization and measurements

The only production change reuses each private reachability array as the
corresponding dominance row. Each cell is read before replacement. It removes
construction of a second growing array; it changes no validation conditions.

Before changing production code, the copy-cost assertion failed because A and B
both copied 4,880 elements at 16 blocks. After the change, both MIR and SSA copy
2,960 elements. Native runtime instrumentation counts elements copied at the real
array-append allocation path; it does not estimate cost by inspecting source.

The fixed chain uses sparse block IDs, checks every dominance-matrix cell, and
runs once for each variant/size. A separate existing
`test/native-bootstrap-diagnostic/dominance_matrix_cost_check.py` passed diamond,
sparse-ID, backedge, unreachable, and operand checks for both MIR and SSA.
Timing is a single local observation, not a statistical speed guarantee.

| Validator | Blocks | A copied elements | B copied elements | A seconds | B seconds |
| --- | ---: | ---: | ---: | ---: | ---: |
| MIR | 16 | 4,880 | 2,960 | 0.005722 | 0.005531 |
| MIR | 64 | 307,776 | 178,752 | 0.021149 | 0.020947 |
| MIR | 256 | 19,605,760 | 11,249,920 | 0.986437 | 0.885774 |
| MIR | 1024 | 1,253,221,376 | 716,874,752 | 62.508341 | 56.295078 |
| SSA | 16 | 4,880 | 2,960 | 0.005478 | 0.005476 |
| SSA | 64 | 307,776 | 178,752 | 0.005515 | 0.005491 |
| SSA | 256 | 19,605,760 | 11,249,920 | 0.189705 | 0.169703 |
| SSA | 1024 | 1,253,221,376 | 716,874,752 | 11.681312 | 10.420016 |

Final recorded run: all object probes, all 16 matrix probes, and both CLI ELF
checks passed (exit 0 for the harness; each CLI-produced program exits 42).
The complete measurement and hash record is `production_acceptance_results.json`.

Recorded fixed-seed/fixed-closure run (2026-11-02):

- Seed SHA256: `9a2746e3b662ce46d70f2d62b4aeecd3aba24d1b6262614d518a843bb5c36670`.
- The 268-source A/B closure-list SHA256 is
  `2fa7e9ca222c0bd90450684d4ef15208ba88e2dfb947483604ac455f1eadde2c`.
- Source-content manifests differ only in MIR and SSA `program.s`.
- Full compiler A SHA256:
  `20f15251029268bb2ce88f47788a3d9c74dc499486b7b7a72f8bda68b980db4e`.
- Full compiler B SHA256:
  `7d20a21811b74b34994329680b392ef02aea1ad868910dfd6584d11e7f37d663`.
- Full compiler CLI production assembly SHA256:
  `f5f621cc05e0d33db0aa7a115576e9033ce1ad26ec2fa9c9978c10b9ff1a3fe1`.

Full compiler builds used the same commands and ordered source list:

```sh
s_seed --compile-native-unit compiler-A.ir $(cat sources.txt)
s_seed --emit-standalone-amd64 compiler-A.ir compiler-A
# Apply only the two dominance-row changes, retaining the ordered source list.
s_seed --compile-native-unit compiler-B.ir $(cat sources.txt)
s_seed --emit-standalone-amd64 compiler-B.ir compiler-B
```

A compile peaked at 710,736 KiB RSS. B compile took 138.78 s user + 0.35 s system
CPU, 139.17 s wall, and 710,804 KiB maximum RSS. Emission took 7.02/7.14 s wall
for A/B, with maximum child RSS 752,540/752,428 KiB. An initial A emission failed
under a 1 GiB **virtual-address** cap. The successful sequential runs used a
4 GiB virtual-address cap and 1.2 GiB process-tree resident watchdog; the seed
requires sparse virtual allocations. Small probes stay below 40 MiB RSS, and
benchmark execution has a 450 MiB resident watchdog and a 120 s timeout.

The native compiler CLI currently rejects recompilation of the large extracted
probe source in canonical semantic checking (first observed `no matching
overload [anchor=amd64_integer]`; preserving source order instead exposed a
return-type diagnostic at `int[] return_values`). Those frontend failures are
recorded as limitations, never accepted as validator rejection evidence. The
object probes are seed-built native executables; the full compiler pair is
checked separately through its production CLI. This is not a full bootstrap
fixed-point claim. No GC or generic-type acceptance changes are included.
