; ============================================================
; juego.asm - Juego de Rotacion de Nombres
; Integrantes: Randall y Chris
;
; Compilar: nasm -f bin src/juego.asm -o build/juego.bin
;
; Controles:
;   A / Flecha Izq : Rotacion 90 grados izquierda
;   D / Flecha Der : Rotacion 90 grados derecha
;   W / Flecha Arr : Rotacion 180 grados
;   S / Flecha Aba : Rotacion 180 grados
;   R              : Reiniciar posicion aleatoria
;   ESC            : Apagar / detener
; ============================================================

[BITS 16]
[ORG 0x8000]            ; El bootloader nos carga en 0000:8000

; ---- Constantes ----
VGA_SEG  equ 0xA000
SCR_W    equ 320
SCR_H    equ 200
COL_BG   equ 0
COL_T1   equ 14
COL_T2   equ 13
COL_BRD  equ 11
COL_WHT  equ 15
COL_GRN  equ 10
COL_RED  equ 12

; ============================================================
; ENTRADA - saltar los datos
; ============================================================
inicio:
    jmp  setup

; ---- Datos ------------------------------------------------
nombre1    db "RANDALL", 0
nombre2    db "CHRIS", 0
msg_tit    db "** JUEGO DE ROTACION **", 0
msg_ask    db "Deseas comenzar?", 0
msg_si     db "[ ENTER ] Jugar", 0
msg_no     db "[  ESC  ] Salir", 0
msg_hud    db "WASD/Flechas:Rot  R:Reset  ESC:Sal", 0
lbl0       db "NORMAL    ", 0
lbl1       db "ROT90-IZQ ", 0
lbl2       db "ROT 180   ", 0
lbl3       db "ROT90-DER ", 0

rotacion   db 0
pos_x      dw 80
pos_y      dw 80
seed       dw 0x5678
drw_x      dw 0
drw_y      dw 0
drw_col    db 0

; ---- Fuente 8x8 ASCII 32-90 --------------------------------
font:
db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00  ; 32 espacio
db 0x18,0x18,0x18,0x18,0x00,0x00,0x18,0x00  ; 33 !
db 0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00  ; 34 "
db 0x6C,0xFE,0x6C,0x6C,0xFE,0x6C,0x6C,0x00  ; 35 #
db 0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00  ; 36 $
db 0x62,0x66,0x0C,0x18,0x30,0x66,0x46,0x00  ; 37 %
db 0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00  ; 38 &
db 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00  ; 39 '
db 0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00  ; 40 (
db 0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00  ; 41 )
db 0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00  ; 42 *
db 0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00  ; 43 +
db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30  ; 44 ,
db 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00  ; 45 -
db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00  ; 46 .
db 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00  ; 47 /
db 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00  ; 48 0
db 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00  ; 49 1
db 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00  ; 50 2
db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00  ; 51 3
db 0x0C,0x1C,0x3C,0x6C,0xFE,0x0C,0x0C,0x00  ; 52 4
db 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00  ; 53 5
db 0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00  ; 54 6
db 0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00  ; 55 7
db 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00  ; 56 8
db 0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00  ; 57 9
db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00  ; 58 :
db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30  ; 59 ;
db 0x0E,0x18,0x30,0x60,0x30,0x18,0x0E,0x00  ; 60 <
db 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00  ; 61 =
db 0x70,0x18,0x0C,0x06,0x0C,0x18,0x70,0x00  ; 62 >
db 0x3C,0x66,0x06,0x1C,0x18,0x00,0x18,0x00  ; 63 ?
db 0x3C,0x66,0x6E,0x6A,0x6E,0x60,0x3C,0x00  ; 64 @
db 0x18,0x3C,0x66,0x7E,0x66,0x66,0x66,0x00  ; 65 A
db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00  ; 66 B
db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00  ; 67 C
db 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00  ; 68 D
db 0x7E,0x60,0x60,0x78,0x60,0x60,0x7E,0x00  ; 69 E
db 0x7E,0x60,0x60,0x78,0x60,0x60,0x60,0x00  ; 70 F
db 0x3C,0x66,0x60,0x6E,0x66,0x66,0x3C,0x00  ; 71 G
db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00  ; 72 H
db 0x7E,0x18,0x18,0x18,0x18,0x18,0x7E,0x00  ; 73 I
db 0x06,0x06,0x06,0x06,0x06,0x66,0x3C,0x00  ; 74 J
db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00  ; 75 K
db 0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00  ; 76 L
db 0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00  ; 77 M
db 0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00  ; 78 N
db 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00  ; 79 O
db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00  ; 80 P
db 0x3C,0x66,0x66,0x66,0x6E,0x3C,0x06,0x00  ; 81 Q
db 0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00  ; 82 R
db 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00  ; 83 S
db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00  ; 84 T
db 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00  ; 85 U
db 0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00  ; 86 V
db 0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00  ; 87 W
db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00  ; 88 X
db 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00  ; 89 Y
db 0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00  ; 90 Z

; ============================================================
; SETUP
; ============================================================
setup:
    cli
    xor  ax, ax
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0x7C00
    sti

    ; Modo video 13h (320x200 256 colores)
    mov  ax, 0x0013
    int  0x10

    ; Semilla random con timer
    mov  ah, 0x00
    int  0x1A
    mov  [seed], dx

    call pantalla_inicio
    call random_pos
    mov  byte [rotacion], 0

    ; Dibujo inicial
    call cls
    call borde
    call hud
    call draw_nombres

; ============================================================
; LOOP PRINCIPAL
; ============================================================
main_loop:
    call get_key            ; bloqueante: espera tecla valida
    call wait_vsync
    call cls
    call borde
    call hud
    call draw_nombres
    jmp  main_loop

; ============================================================
; PANTALLA DE CONFIRMACION
; ============================================================
pantalla_inicio:
    call cls
    call borde

    mov  si, msg_tit
    mov  cx, 88
    mov  dx, 60
    mov  al, COL_WHT
    call draw_str

    mov  si, msg_ask
    mov  cx, 92
    mov  dx, 82
    mov  al, COL_WHT
    call draw_str

    mov  si, msg_si
    mov  cx, 95
    mov  dx, 105
    mov  al, COL_GRN
    call draw_str

    mov  si, msg_no
    mov  cx, 95
    mov  dx, 120
    mov  al, COL_RED
    call draw_str

    mov  si, nombre1
    mov  cx, 110
    mov  dx, 148
    mov  al, COL_T1
    call draw_str

    mov  si, nombre2
    mov  cx, 110
    mov  dx, 161
    mov  al, COL_T2
    call draw_str

.wait:
    mov  ah, 0x00
    int  0x16
    cmp  ah, 0x1C           ; ENTER
    je   .ok
    cmp  ah, 0x01           ; ESC
    je   .salir
    jmp  .wait
.ok:
    ret
.salir:
    call modo_texto
    cli
.halt:
    hlt
    jmp  .halt

; ============================================================
; HUD
; ============================================================
hud:
    mov  si, msg_hud
    mov  cx, 8
    mov  dx, 191
    mov  al, COL_BRD
    call draw_str

    cmp  byte [rotacion], 1
    je   .h1
    cmp  byte [rotacion], 2
    je   .h2
    cmp  byte [rotacion], 3
    je   .h3
    mov  si, lbl0
    jmp  .show
.h1: mov  si, lbl1
    jmp  .show
.h2: mov  si, lbl2
    jmp  .show
.h3: mov  si, lbl3
.show:
    mov  cx, 212
    mov  dx, 4
    mov  al, COL_WHT
    call draw_str
    ret

; ============================================================
; DRAW_NOMBRES
; ============================================================
draw_nombres:
    cmp  byte [rotacion], 1
    je   .izq
    cmp  byte [rotacion], 2
    je   .r180
    cmp  byte [rotacion], 3
    je   .der

.normal:
    mov  si, nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_str
    mov  si, nombre2
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 14
    mov  al, COL_T2
    call draw_str
    ret

.izq:
    mov  si, nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 70
    mov  al, COL_T1
    call draw_r90l
    mov  si, nombre2
    mov  cx, [pos_x]
    add  cx, 14
    mov  dx, [pos_y]
    add  dx, 70
    mov  al, COL_T2
    call draw_r90l
    ret

.r180:
    mov  si, nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_r180
    mov  si, nombre2
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 14
    mov  al, COL_T2
    call draw_r180
    ret

.der:
    mov  si, nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_r90r
    mov  si, nombre2
    mov  cx, [pos_x]
    add  cx, 14
    mov  dx, [pos_y]
    mov  al, COL_T2
    call draw_r90r
    ret

; ============================================================
; READ_FONT_ROW
; BX = puntero base del char en font
; DH = fila (0..7)
; Devuelve AL = byte de esa fila
; No modifica BX
; ============================================================
read_font_row:
    push bx
    push cx
    mov  cl, dh
    mov  ch, 0
    add  bx, cx
    mov  al, [bx]
    pop  cx
    pop  bx
    ret

; ============================================================
; DRAW_STR - texto horizontal normal
; SI=cadena  CX=x  DX=y  AL=color
; ============================================================
draw_str:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [drw_col], al
    mov  di, dx

.char:
    mov  al, [si]
    or   al, al
    jz   .fin
    xor  ah, ah
    sub  ax, 32
    jb   .next
    cmp  ax, 58
    ja   .next

    push cx
    push di
    push si
    push ax

    ; bx = &font[char * 8]
    mov  bx, ax
    shl  bx, 3
    add  bx, font

    mov  dh, 0              ; fila
.fila:
    cmp  dh, 8
    je   .char_done

    call read_font_row
    mov  dl, al             ; byte de la fila

    mov  ch, 0x80           ; mascara bit
    mov  cl, 0              ; columna
.col:
    cmp  cl, 8
    je   .col_done
    test dl, ch
    jz   .nopix
    push ax
    push bx
    push cx
    push dx
    push di
    mov  ah, [drw_col]
    call pix
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
.nopix:
    shr  ch, 1
    inc  cx
    jmp  .col

.col_done:
    inc  dh
    inc  di
    jmp  .fila

.char_done:
    pop  ax
    pop  si
    pop  di
    pop  cx
    add  cx, 9

.next:
    inc  si
    jmp  .char

.fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; DRAW_R90L - 90 grados izquierda
; pixel[f][c] -> pantalla( drw_x+c , drw_y-f )
; SI=cadena  CX=x  DX=y  AL=color
; ============================================================
draw_r90l:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [drw_x], cx
    mov  [drw_y], dx
    mov  [drw_col], al

.char:
    mov  al, [si]
    or   al, al
    jnz  .char_ok
    jmp  .fin
.char_ok:
    xor  ah, ah
    sub  ax, 32
    jb   .next
    cmp  ax, 58
    ja   .next

    push si

    mov  bx, ax
    shl  bx, 3
    add  bx, font

    mov  dh, 0              ; fila f
.floop:
    cmp  dh, 8
    je   .fdone

    call read_font_row
    mov  dl, al

    mov  ch, 0x80           ; mascara
    mov  cl, 0              ; columna c
.cloop:
    cmp  cl, 8
    je   .cdone
    test dl, ch
    jz   .nopix

    push bx
    push cx
    push dx

    ; x = drw_x + c
    mov  bx, [drw_x]
    xor  ax, ax
    mov  al, cl
    add  bx, ax
    mov  cx, bx

    ; y = drw_y - f
    mov  bx, [drw_y]
    xor  ax, ax
    mov  al, dh
    sub  bx, ax
    mov  di, bx

    mov  ah, [drw_col]
    call pix

    pop  dx
    pop  cx
    pop  bx

.nopix:
    shr  ch, 1
    inc  cl
    jmp  .cloop

.cdone:
    inc  dh
    jmp  .floop

.fdone:
    pop  si
    sub  word [drw_y], 9    ; siguiente char sube 9px

.next:
    inc  si
    jmp  .char

.fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; DRAW_R90R - 90 grados derecha
; pixel[f][c] -> pantalla( drw_x+(7-c) , drw_y+f )
; SI=cadena  CX=x  DX=y  AL=color
; ============================================================
draw_r90r:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [drw_x], cx
    mov  [drw_y], dx
    mov  [drw_col], al

.char:
    mov  al, [si]
    or   al, al
    jnz  .char_ok
    jmp  .fin
.char_ok:
    xor  ah, ah
    sub  ax, 32
    jb   .next
    cmp  ax, 58
    ja   .next

    push si

    mov  bx, ax
    shl  bx, 3
    add  bx, font

    mov  dh, 0
.floop:
    cmp  dh, 8
    je   .fdone

    call read_font_row
    mov  dl, al

    mov  ch, 0x80
    mov  cl, 0
.cloop:
    cmp  cl, 8
    je   .cdone
    test dl, ch
    jz   .nopix

    push bx
    push cx
    push dx

    ; x = drw_x + (7 - c)
    mov  bx, 7
    xor  ax, ax
    mov  al, cl
    sub  bx, ax
    add  bx, [drw_x]
    mov  cx, bx

    ; y = drw_y + f
    mov  bx, [drw_y]
    xor  ax, ax
    mov  al, dh
    add  bx, ax
    mov  di, bx

    mov  ah, [drw_col]
    call pix

    pop  dx
    pop  cx
    pop  bx

.nopix:
    shr  ch, 1
    inc  cl
    jmp  .cloop

.cdone:
    inc  dh
    jmp  .floop

.fdone:
    pop  si
    add  word [drw_y], 9

.next:
    inc  si
    jmp  .char

.fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; DRAW_R180 - 180 grados
; pixel[f][c] -> pantalla( drw_x + (ancho-1-c_off) , drw_y+(7-f) )
; SI=cadena  CX=x  DX=y  AL=color
; ============================================================
draw_r180:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov  [drw_y], dx
    mov  [drw_col], al

    ; Calcular longitud
    push si
    xor  bx, bx
.lenloop:
    cmp  byte [si + bx], 0
    je   .lendone
    inc  bx
    jmp  .lenloop
.lendone:
    mov  ax, bx
    mov  bx, 9
    mul  bx
    pop  si
    add  cx, ax
    mov  [drw_x], cx        ; x empieza desde la derecha

.char:
    mov  al, [si]
    or   al, al
    jz   .fin
    xor  ah, ah
    sub  ax, 32
    jb   .next
    cmp  ax, 58
    ja   .next

    sub  word [drw_x], 9

    push si

    mov  bx, ax
    shl  bx, 3
    add  bx, font

    mov  dh, 7              ; empezar desde fila 7 (invertir eje Y)
.floop:
    cmp  dh, 0xFF           ; underflow de 0 a FF
    je   .fdone

    call read_font_row
    mov  dl, al

    ; Invertir byte (espejo horizontal)
    push cx
    mov  al, dl
    xor  dl, dl
    mov  cx, 8
.inv:
    shl  al, 1
    rcr  dl, 1
    loop .inv
    pop  cx

    ; Dibujar fila en y = drw_y + (7 - dh)
    push bx
    push dx

    mov  cx, [drw_x]
    xor  ax, ax
    mov  al, 7
    sub  al, dh
    xor  bx, bx
    mov  bl, al
    mov  di, [drw_y]
    add  di, bx             ; di = drw_y + (7 - f)

    mov  bx, 8
.colloop:
    test dl, 0x80
    jz   .nopix
    push bx
    push cx
    push dx
    push di
    mov  ah, [drw_col]
    call pix
    pop  di
    pop  dx
    pop  cx
    pop  bx
.nopix:
    shl  dl, 1
    inc  cx
    dec  bx
    jnz  .colloop

    pop  dx
    pop  bx

    dec  dh
    jmp  .floop

.fdone:
    pop  si

.next:
    inc  si
    jmp  .char

.fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; PIX - escribir pixel en VGA modo 13h
; CX=x  DI=y  AH=color
; ============================================================
pix:
    push ax
    push bx
    push cx
    push dx
    push di
    push es

    cmp  cx, SCR_W
    jae  .out
    cmp  di, SCR_H
    jae  .out

    mov  bx, VGA_SEG
    mov  es, bx
    mov  ax, di
    mov  bx, SCR_W
    mul  bx
    add  ax, cx
    mov  di, ax
    mov  al, ah
    stosb

.out:
    pop  es
    pop  di
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; CLS
; ============================================================
cls:
    push ax
    push cx
    push di
    push es
    mov  ax, VGA_SEG
    mov  es, ax
    xor  di, di
    mov  cx, SCR_W * SCR_H
    mov  al, COL_BG
    rep  stosb
    pop  es
    pop  di
    pop  cx
    pop  ax
    ret

; ============================================================
; BORDE
; ============================================================
borde:
    push ax
    push cx
    push di

    mov  di, 5
    mov  cx, 5
.top:
    cmp  cx, 314
    jg   .bot
    mov  ah, COL_BRD
    call pix
    inc  cx
    jmp  .top
.bot:
    mov  di, 186
    mov  cx, 5
.bot2:
    cmp  cx, 314
    jg   .left
    mov  ah, COL_BRD
    call pix
    inc  cx
    jmp  .bot2
.left:
    mov  cx, 5
    mov  di, 5
.left2:
    cmp  di, 186
    jg   .right
    mov  ah, COL_BRD
    call pix
    inc  di
    jmp  .left2
.right:
    mov  cx, 314
    mov  di, 5
.right2:
    cmp  di, 186
    jg   .done
    mov  ah, COL_BRD
    call pix
    inc  di
    jmp  .right2
.done:
    pop  di
    pop  cx
    pop  ax
    ret

; ============================================================
; RANDOM_POS
; ============================================================
random_pos:
    push ax
    push bx
    push dx

    mov  ah, 0x00
    int  0x1A

    mov  ax, [seed]
    mov  bx, 25173
    mul  bx
    add  ax, 13849
    mov  [seed], ax
    xor  dx, dx
    mov  bx, 160
    div  bx
    add  dx, 20
    mov  [pos_x], dx

    mov  ax, [seed]
    mov  bx, 25173
    mul  bx
    add  ax, 13849
    mov  [seed], ax
    xor  dx, dx
    mov  bx, 120
    div  bx
    add  dx, 20
    mov  [pos_y], dx

    pop  dx
    pop  bx
    pop  ax
    ret

; ============================================================
; WAIT_VSYNC - sincronizar con retrace vertical
; ============================================================
wait_vsync:
    push ax
    push dx
    mov  dx, 0x03DA
.end_retrace:
    in   al, dx
    test al, 0x08
    jnz  .end_retrace
.start_retrace:
    in   al, dx
    test al, 0x08
    jz   .start_retrace
    pop  dx
    pop  ax
    ret

; ============================================================
; GET_KEY - espera bloqueante, actualiza rotacion
; ============================================================
get_key:
    mov  ah, 0x01
    int  0x16
    jnz  .leer
    jmp  get_key            ; sin tecla, seguir esperando
.leer:
    mov  ah, 0x00
    int  0x16

    ; ESC
    cmp  ah, 0x01
    jne  .no_esc
    call modo_texto
    cli
.halt:
    hlt
    jmp  .halt
.no_esc:

    ; R - reset
    cmp  ah, 0x13
    jne  .no_r
    call random_pos
    mov  byte [rotacion], 0
    ret
.no_r:

    ; WASD
    cmp  al, 'a'
    je   .izq
    cmp  al, 'A'
    je   .izq
    cmp  al, 'd'
    je   .der
    cmp  al, 'D'
    je   .der
    cmp  al, 'w'
    je   .arr
    cmp  al, 'W'
    je   .arr
    cmp  al, 's'
    je   .aba
    cmp  al, 'S'
    je   .aba

    ; Flechas
    cmp  al, 0x00
    je   .flechas
    cmp  al, 0xE0
    je   .flechas
    jmp  get_key            ; tecla no reconocida, seguir esperando

.flechas:
    cmp  ah, 0x4B
    je   .izq
    cmp  ah, 0x4D
    je   .der
    cmp  ah, 0x48
    je   .arr
    cmp  ah, 0x50
    je   .aba
    jmp  get_key

.izq:
    mov  al, [rotacion]
    dec  al
    and  al, 0x03
    mov  [rotacion], al
    ret

.der:
    mov  al, [rotacion]
    inc  al
    and  al, 0x03
    mov  [rotacion], al
    ret

.arr:
    mov  al, [rotacion]
    xor  al, 0x02
    mov  [rotacion], al
    ret

.aba:
    mov  al, [rotacion]
    xor  al, 0x02
    mov  [rotacion], al
    ret

; ============================================================
; MODO_TEXTO
; ============================================================
modo_texto:
    mov  ax, 0x0003
    int  0x10
    ret
