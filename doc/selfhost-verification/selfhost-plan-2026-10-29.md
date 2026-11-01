# Native self-hosting execution plan

Goal: an S compiler compiles its complete production source into stage2, stage2
repeats the compilation into stage3, and both assembly and executable bytes
converge. Each resulting compiler must compile and execute an independent S
program. ELF inspection alone is insufficient.

The user requested continuous execution. Work proceeds in the requested
checkout, preserving the pre-existing semantic regression additions.

- [x] Inspect the bootstrap driver, source closure, existing artifacts and logs.
- [ ] Reproduce and repair canonical receiver method checking with focused tests.
- [ ] Preserve semantic diagnostic locations in the native production pipeline.
- [ ] Run complete-source parsing, checking, specialization and lowering probes;
      fix each demonstrated blocker without disabling validation or delegation
      to the seed after stage1.
- [ ] Rebuild stage1 from the final sources and run the full native bootstrap.
- [ ] Verify stage2/stage3 convergence, source dependence and independent native
      execution, then update the documented status with measured evidence.

Seed build performance is being measured separately with optimized host C code;
this must not change generated IR or native program behavior.
