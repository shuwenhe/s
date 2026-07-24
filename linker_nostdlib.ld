/* Linker script for S compiler bootstrap without C library
 * 
 * This script links S code without any C library dependencies
 * Used for true self-hosting: compiler → IR → binary (no libc)
 */

ENTRY(__start)

SECTIONS
{
    . = 0x400000;
    
    /* Text segment: executable code */
    .text : {
        *(.text)
        *(.text.startup)
    }
    
    . = ALIGN(0x1000);
    
    /* Read-only data: constants, strings */
    .rodata : {
        *(.rodata)
        *(.rodata.str1.1)
    }
    
    . = ALIGN(0x1000);
    
    /* Initialized data */
    .data : {
        *(.data)
    }
    
    /* Uninitialized data (BSS) */
    .bss : {
        *(.bss)
        *(COMMON)
    }
    
    /* Discard unnecessary sections */
    /DISCARD/ : {
        *(.note.GNU-stack)
        *(.gnu_version)
        *(.gnu_version_r)
        *(.gnu_hash)
        *(.dynsym)
        *(.dynstr)
        *(.dynamic)
        *(.rel.*)
        *(.rela.*)
        *(.got)
        *(.got.plt)
        *(.plt)
        *(.interp)
        *(.comment)
        *(.symtab)
        *(.strtab)
        *(.shstrtab)
    }
}

PHDRS
{
    text    PT_LOAD FLAGS(5);      /* R+X */
    data    PT_LOAD FLAGS(6);      /* R+W */
    bss     PT_LOAD FLAGS(6);      /* R+W */
}

SECTIONS
{
    .text : { *(.text) } :text
    .rodata : { *(.rodata) } :text
    .data : { *(.data) } :data
    .bss : { *(.bss) } :bss
}
