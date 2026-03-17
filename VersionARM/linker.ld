ENTRY(_start)

SECTIONS {
  . = 0;

  .text : {
    *(.text*)
    *(.rodata*)
  }

  .data : {
    *(.data*)
  }

  .dynamic : {
    *(.dynamic)
  }

  .dynsym : {
    *(.dynsym)
  }

  .dynstr : {
    *(.dynstr)
  }

  .rela : {
    *(.rela*)
  }

  .reloc : {
    *(.reloc)
  }

  .bss : {
    *(.bss*)
    *(COMMON)
  }
}
