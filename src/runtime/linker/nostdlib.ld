 





ENTRY(_start)

PHDRS
{
    text PT_LOAD FILEHDR PHDRS FLAGS(5);  
    data PT_LOAD FLAGS(6);                 
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
