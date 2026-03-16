; ============================================================
; boot.asm - Bootloader
; Compilar: nasm -f bin src/boot.asm -o build/boot.bin
;
; La BIOS carga este sector en 0000:7C00 y salta aqui.
; Nosotros leemos el juego del disco y saltamos a el.
; ============================================================

[BITS 16]
[ORG 0x7C00]

GAME_SEG   EQU 0x0000
GAME_OFF   EQU 0x8000       ; cargamos el juego en 0000:8000
%ifndef GAME_SECTS
GAME_SECTS EQU 20           ; valor por defecto (se puede sobreescribir con -D GAME_SECTS=n)
%endif

start:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    mov  esp, 0x00007C00
    sti

    ; Guardar drive (BIOS lo pone en DL al arrancar)
    mov  [boot_drive], dl

    ; Mensaje de carga
    mov  si, msg_loading
    call print_str

    ; ---- Leer el juego con INT 13h ----
    ; AH=02  AL=sectores  CH=cilindro  CL=sector(base1)
    ; DH=cabeza  DL=drive  ES:BX=destino
    mov  ax, GAME_SEG
    mov  es, ax
    mov  bx, GAME_OFF

    mov  ah, 0x02
    mov  al, GAME_SECTS
    mov  ch, 0
    mov  cl, 2              ; sector 2 = justo despues del MBR
    mov  dh, 0
    mov  dl, [boot_drive]
    int  0x13

    jc   .error             ; carry flag = error

    ; Mostrar mensaje y saltar al juego
    mov  si, msg_welcome
    call print_str
    jmp  GAME_SEG:GAME_OFF  ; far jump al juego

.error:
    mov  si, msg_error
    call print_str
.halt:
    cli
    hlt
    jmp  .halt

; ---- print_str: SI = cadena terminada en 0 ----
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

; ---- Datos ----
boot_drive  db 0
msg_loading db "Cargando...", 13, 10, 0
msg_error   db "ERROR al leer disco", 13, 10, 0
msg_welcome db "Juego cargado. Iniciando...", 13, 10, 0

; ---- Padding hasta 510 bytes + firma 0xAA55 ----
times 510 - ($ - $$) db 0
dw 0xAA55