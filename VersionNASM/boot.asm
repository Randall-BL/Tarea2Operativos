; ============================================================
; boot.asm - Bootloader
; Compilar: nasm -f bin boot.asm -o build/boot.bin
; ============================================================

[BITS 16]
[ORG 0x7C00]

GAME_SEG   EQU 0x0000
GAME_OFF   EQU 0x8000
GAME_SECTS EQU 20

start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    sti

    mov  [boot_drive], dl

    mov  si, msg_loading
    call print_str

    mov  ax, GAME_SEG
    mov  es, ax
    mov  bx, GAME_OFF

    mov  ah, 0x02
    mov  al, GAME_SECTS
    mov  ch, 0
    mov  cl, 2
    mov  dh, 0
    mov  dl, [boot_drive]
    int  0x13

    jc   .error

    mov  si, msg_welcome
    call print_str

    ; Leer tick inicial
    mov  ah, 0x00
    int  0x1A
    mov  [boot_tick], dx

    ; Esperar cualquier tecla o 10 segundos
.wait_key:
    ; Verificar tiempo (182 ticks ~ 10 seg)
    mov  ah, 0x00
    int  0x1A
    mov  ax, dx
    sub  ax, [boot_tick]
    cmp  ax, 182
    jae  .go                ; tiempo agotado, arrancar

    ; Verificar tecla via puerto directo
    in   al, 0x64
    test al, 0x01
    jz   .wait_key          ; no hay tecla
    in   al, 0x60
    test al, 0x80           ; ignorar key-release
    jnz  .wait_key
    cmp  al, 0x01           ; ESC = halt
    je   .halt
.go:
    jmp  GAME_SEG:GAME_OFF

.error:
    mov  si, msg_error
    call print_str
.halt:
    cli
    hlt
    jmp  .halt

print_str:
    push ax
    push bx
.loop:
    lodsb
    or   al, al
    jz   .done
    mov  ah, 0x0E
    mov  bx, 0x0007
    int  0x10
    jmp  .loop
.done:
    pop  bx
    pop  ax
    ret

boot_drive  db 0
boot_tick   dw 0
msg_loading db "Cargando...", 13, 10, 0
msg_error   db "ERROR al leer disco", 13, 10, 0
msg_welcome db "Bienvenido! Presiona cualquier tecla...", 13, 10, 0

times 510 - ($ - $$) db 0
dw 0xAA55