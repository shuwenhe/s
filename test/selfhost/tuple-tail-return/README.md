# Current selfhost FIRST RED: tuple tail return

Seed accepts this source and its native executable returns 42. The canonical
compiler currently rejects `relay` with e3004 (function return type mismatch).
This reproduces `base.map_file_mmap` forwarding `map_file_read` as a tail
expression. It is tracked as an unresolved correctness frontier, not included
as a passing production regression.
