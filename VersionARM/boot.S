.section .text
.align 4
.global _start

_start:
    mov x29, xzr
    b efi_main_c
