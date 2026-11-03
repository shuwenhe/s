# Correctness failure found during clean-room validation

Attempt2, frozen commit ded34a00e45df2582c587d7ee83c92d4a40dea1f:
fresh Stage1 completed strict MIR verification but crashed while exporting the
complete public MIR. Exit139, elapsed1116.08 seconds, maximum RSS2868276KiB;
the output file was empty. Acceptance stopped. Stage2/Stage3 were NOT RUN.
All failed sources, binaries, logs and receipts remain in attempt2.

`src/runtime/selfhost_linux_amd64.S:s_write_string_fd` recursively traversed
rope nodes. A small native program concatenating50000 pieces reproduced SIGSEGV
under a256KiB stack. This is a demonstrated runtime correctness issue, not a
performance change. The writer now uses a private dynamically grown mapping
for traversal and releases it on success and failure. Interrupted writes retry;
short writes advance the cursor and zero progress returns an error.

Regression: `test/native-bootstrap-diagnostic/native_rope_writer_check.py`.
It checks distinct left/right leaf order, empty deep ropes, exact bytes,
interrupted writes, zero progress, allocation failure and mapping cleanup.
The full production suite passed with the fix: exit0,212.45seconds. The final
strengthened rope test and15 clean-room controller tests also pass. An independent
assembly/ABI review found no blocking issue.

A new clean-room attempt must rebuild the complete chain from this committed
fix; no failed-attempt output may be reused as acceptance evidence.
