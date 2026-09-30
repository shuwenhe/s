# Object

Canonical home for object emission and relocation handling.

Expected files as migration proceeds:

- `object.s`
- `elf.s`
- `reloc.s`

ELF is the current concrete object format. Mach-O and COFF can be added here
without changing the pipeline stage name.

