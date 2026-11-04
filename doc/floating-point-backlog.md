# Floating point — separate P1 language project

Native self-host certification does not require adding a new floating-point
language implementation. The historical syntax guide names `float`; the seed
interpreter uses C double, strtod and %.17g. This provides a compatibility
baseline but leaves edge behavior incompletely specified. Float-to-int C casts
outside range and unordered comparison handling require explicit decisions.

The active canonical tokenizer splits decimal literals at the point; its AST
has no float expression variant. MIR/SSA validation and the current AMD64
program emitter handle integer scalars. Calls use GP argument registers and
RAX results. Float-related historical parser, architecture or optimization
files do not establish active end-to-end support.

Required implementation, with independent tests at each boundary:

1. Specify binary precision, rounding, mixed arithmetic/conversions, signed
   zero, infinities, NaN, overflow/underflow and division by zero. Reconcile
   `float` with the existing f32/f64 type names deliberately.
2. Extend lexer/parser decimal and exponent validation, unary negation and
   source spans; add the AST variant and every clone/traversal/serialization
   consumer. Preserve exact literal bits through bootstrap, without assuming
   the compiler implementation can already execute floating-point operations.
3. Implement semantic inference and explicit conversions; separate invariant
   generic type identity from scalar assignment compatibility.
4. Add typed MIR and SSA constants, arithmetic, conversions and unordered-aware
   comparisons; reject malformed arity/types. Keep integer rewrites from
   applying identities invalid for NaN, signed zero or rounding.
5. Implement SSE2 code generation, floating register classes and liveness,
   spill/reload behavior, callee/caller preservation and stack alignment.
6. Implement System V AMD64 mixed GP/SSE argument classification, independent
   register exhaustion, stack arguments and XMM results; test aggregates and
   C interoperability separately. A private integer bit-carrier convention
   must not be advertised as the C floating-point ABI.
7. Extend records, arrays, references, enums, default initialization, copying
   and conservative GC scanning. Establish seed standalone execution support
   separately from canonical unboxed storage.
8. Provide exact native parse/format services and runtime errors without an
   accidental libc dependency. Test decimal rounding boundaries, subnormals,
   infinities/NaNs, conversions and repeated round trips against independent
   bit-pattern oracles.
9. Run complete production, ABI and memory regressions, then a new frozen
   multi-stage self-host and reproducibility acceptance at the integrated SHA.

Concrete enum payload validation can preserve semantic numeric/any assignment
rules without claiming those unsupported native executable representations.
No float implementation is included in the native certification increment.
