/* Linker script for S compiler bootstrap without C library
 * 
 * This script links S code without any C library dependencies
 * Used for true self-hosting: compiler → IR → binary (no libc)
 */

ENTRY(_start)

PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5); /* R+X */
    data PT_LOAD FLAGS(6);                /* R+W */
}

SECTIONS
{
    . = 0x400000 + SIZEOF_HEADERS;

    .text : {
        *(.text.startup)
        *(.text .text.*)
    } :text

    .rodata : {
        *(.rodata .rodata.*)
    } :text

    . = ALIGN(CONSTANT(MAXPAGESIZE));

    .data : {
        *(.data .data.*)
    } :data

    .bss (NOLOAD) : {
        *(.bss .bss.*)
        *(COMMON)
    } :data

    /DISCARD/ : {
        *(.comment)
        *(.eh_frame .eh_frame_hdr)
        *(.gnu.hash)
        *(.gnu.version .gnu.version.*)
        *(.interp)
        *(.dynamic)
        *(.dynsym .dynstr)
        *(.got .got.* .plt .plt.*)
        *(.rel.* .rela.*)
        *(.note .note.*)
    }
}
