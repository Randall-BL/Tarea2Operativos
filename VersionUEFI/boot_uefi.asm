; ============================================================
; boot_uefi.asm  –  Aplicación UEFI x86-64 (PE32+)
; Compilar : nasm -f bin boot_uefi.asm -o BOOTX64.EFI
; Colocar  : /EFI/BOOT/BOOTX64.EFI  en una partición FAT32
; ============================================================

BITS 64

; ----- Layout en memoria al ser cargado por UEFI -----------
IMAGE_BASE  EQU 0x0000000000400000
CODE_RVA    EQU 0x1000
CODE_SIZE   EQU 0x0400
IMAGE_SIZE  EQU 0x2000
HDR_SIZE    EQU 0x0200
CODE_FOFF   EQU 0x1000

ORG IMAGE_BASE

; ============================================================
; DOS MZ stub (offset 0x00)
; ============================================================
dw 0x5A4D           ; "MZ"
dw 0x0090
dw 0x0003
dw 0x0000
dw 0x0004
dw 0x0000
dw 0xFFFF
dw 0x0000
dw 0x00B8
dw 0x0000
dw 0x0000
dw 0x0000
dw 0x0040
dw 0x0000
times 4 dw 0x0000
dw 0x0000
dw 0x0000
times 10 dw 0x0000
dd 0x00000040       ; e_lfanew

; ============================================================
; PE Signature (offset 0x40)
; ============================================================
db 'PE', 0, 0

; ============================================================
; COFF Header (offset 0x44)
; ============================================================
dw 0x8664           ; Machine = AMD64
dw 1                ; NumberOfSections
dd 0
dd 0
dd 0
dw 240              ; SizeOfOptionalHeader
dw 0x0206           ; Characteristics

; ============================================================
; Optional Header PE32+ (offset 0x58)
; ============================================================
dw 0x020B           ; Magic = PE32+
db 0, 0
dd CODE_SIZE
dd 0
dd 0
dd CODE_RVA         ; AddressOfEntryPoint
dd CODE_RVA         ; BaseOfCode
dq IMAGE_BASE       ; ImageBase
dd 0x1000           ; SectionAlignment
dd 0x0200           ; FileAlignment
dw 0, 0
dw 0, 0
dw 0, 0
dd 0
dd IMAGE_SIZE       ; SizeOfImage
dd HDR_SIZE         ; SizeOfHeaders
dd 0                ; CheckSum
dw 10               ; Subsystem = EFI_APPLICATION
dw 0
dq 0
dq 0
dq 0
dq 0
dd 0
dd 16               ; NumberOfRvaAndSizes
times 16 dq 0       ; DataDirectory[16]

; ============================================================
; Section Header: .text (offset 0x148)
; ============================================================
db '.text', 0, 0, 0
dd CODE_SIZE
dd CODE_RVA
dd CODE_SIZE
dd CODE_FOFF
dd 0
dd 0
dw 0
dw 0
dd 0x60000020       ; CODE | EXECUTE | READ

; Padding hasta HDR_SIZE (0x200)
times (HDR_SIZE - ($ - $$)) db 0

; Padding hasta CODE_FOFF (0x1000)
times (CODE_FOFF - HDR_SIZE) db 0

; ============================================================
; .text  – código UEFI
;
;   EFI_SYSTEM_TABLE offsets (64-bit):
;      +48  ConIn   (EFI_SIMPLE_TEXT_INPUT_PROTOCOL*)
;      +64  ConOut  (EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL*)
;
;   EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL offsets:
;       +8  OutputString(This, CHAR16*)
;      +48  ClearScreen(This)
;
;   EFI_SIMPLE_TEXT_INPUT_PROTOCOL offsets:
;       +8  ReadKeyStroke(This, EFI_INPUT_KEY*)
;           retorna 0=OK, 0x8000000000000003=EFI_NOT_READY
;
;   Convencion Microsoft x64: rcx,rdx,r8,r9 volatiles.
; ============================================================
_code_start:

efi_main:
    push    rbx
    sub     rsp, 48         ; shadow(32) + EFI_INPUT_KEY(4) + padding

    mov     rbx, rdx        ; rbx = EFI_SYSTEM_TABLE*

    ; ClearScreen(ConOut)
    mov     rcx, [rbx + 64]
    call    [rcx + 48]

    ; OutputString: titulo
    mov     rcx, [rbx + 64]
    lea     rdx, [rel msg_title]
    call    [rcx + 8]

    ; OutputString: info
    mov     rcx, [rbx + 64]
    lea     rdx, [rel msg_info]
    call    [rcx + 8]

    ; OutputString: esperar tecla
    mov     rcx, [rbx + 64]
    lea     rdx, [rel msg_wait]
    call    [rcx + 8]

    ; Polling ReadKeyStroke hasta que llegue una tecla
    ; EFI_INPUT_KEY (4 bytes) en [rsp+32]
.poll:
    mov     rcx, [rbx + 48]         ; ConIn
    lea     rdx, [rsp + 32]         ; &EFI_INPUT_KEY
    call    [rcx + 8]               ; ReadKeyStroke → 0=OK, otro=sin tecla
    test    rax, rax                ; EFI_SUCCESS == 0
    jnz     .poll

    ; ClearScreen y despedida
    mov     rcx, [rbx + 64]
    call    [rcx + 48]

    mov     rcx, [rbx + 64]
    lea     rdx, [rel msg_bye]
    call    [rcx + 8]

    ; Return EFI_SUCCESS = 0
    xor     eax, eax
    add     rsp, 48
    pop     rbx
    ret

; ============================================================
; Strings UTF-16LE  (dw 'X' -> bytes 58 00 en memoria)
; ============================================================

; Macro: emite string ASCII como UTF-16LE + CRLF
%macro U16 1+
  %assign %%i 1
  %strlen %%len %1
  %rep %%len
    %substr %%c %1 %%i
    dw %%c
    %assign %%i %%i+1
  %endrep
  dw 13, 10
%endmacro

msg_title:
    U16 "======================================"
    U16 "  UEFI Bootloader - Sistemas Operativos"
    U16 "======================================"
    dw 0

msg_info:
    U16 "  Cargado desde: /EFI/BOOT/BOOTX64.EFI"
    U16 "  Compilado con: nasm -f bin"
    U16 "--------------------------------------"
    dw 0

msg_wait:
    U16 "  Presiona cualquier tecla para salir..."
    dw 0

msg_bye:
    U16 "  Hasta luego."
    dw 0

; Padding para completar CODE_SIZE bytes desde _code_start
times (CODE_SIZE - ($ - _code_start)) db 0
