ENTRY(_start)
SECTIONS {
  . = 0x8000;

  .start : {
    *(.start)
  }

  .text : {
    *(.text*)
    *(.rodata*)
  }

  .data : {
    *(.data*)
  }

  .bss : {
    *(.bss*)
    *(COMMON)
  }
}
