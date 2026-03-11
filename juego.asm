; ============================================================
; JUEGO DE ROTACION DE NOMBRES - TASM 4.1  16-bit .COM
; Integrantes: Randall y Chris
;
; Controles:
;   A / Flecha Izq : Rotacion 90 grados izquierda
;   D / Flecha Der : Rotacion 90 grados derecha
;   W / Flecha Arr : Rotacion 180 grados
;   S / Flecha Aba : Rotacion 180 grados
;   R              : Reiniciar con posicion aleatoria
;   ESC            : Salir
; ============================================================
; NOTAS TECNICAS para TASM 4.1 / 8086:
;   - Programa .COM: un solo segmento, DS=CS=ES=SS
;   - NO usar @DATA, usar CS directo
;   - Modos de indexado validos: [bx], [bp], [si], [di],
;     [bx+si], [bx+di], [bp+si], [bp+di] + desplazamiento
;   - Saltos cortos (jz/jnz etc) tienen rango -128..+127
; ============================================================

.MODEL TINY
.8086

VGA_SEG   EQU 0A000h
SCR_W     EQU 320
SCR_H     EQU 200
COL_BG    EQU 0
COL_T1    EQU 14
COL_T2    EQU 13
COL_BRD   EQU 11
COL_WHT   EQU 15
COL_GRN   EQU 10
COL_RED   EQU 12

.CODE
ORG 100h

; ============================================================
; DATOS (dentro del segmento .CODE para programa .COM)
; ============================================================
jmp  inicio               ; saltar los datos al arrancar

nombre1    DB "HAROLD",0
nombre2    DB "CHRIS",0
msg_tit    DB "** JUEGO DE ROTACION **",0
msg_ask    DB "Deseas comenzar?",0
msg_si     DB "[ ENTER ] Jugar",0
msg_no     DB "[  ESC  ] Salir",0
msg_hud    DB "WASD/Flechas:Rot  R:Reset  ESC:Sal",0
lbl0       DB "NORMAL    ",0
lbl1       DB "ROT90-IZQ ",0
lbl2       DB "ROT 180   ",0
lbl3       DB "ROT90-DER ",0

rotacion   DB 0
pos_x      DW 80
pos_y      DW 80
seed       DW 5678h
drw_x      DW 0
drw_y      DW 0
drw_col    DB 0

; ---- Fuente 8x8 ASCII 32..90 -------------------------------
font LABEL BYTE
DB 00h,00h,00h,00h,00h,00h,00h,00h  ; 32 espacio
DB 18h,18h,18h,18h,00h,00h,18h,00h  ; 33 !
DB 66h,66h,24h,00h,00h,00h,00h,00h  ; 34 "
DB 6Ch,0FEh,6Ch,6Ch,0FEh,6Ch,6Ch,00h; 35 #
DB 18h,3Eh,60h,3Ch,06h,7Ch,18h,00h  ; 36 $
DB 62h,66h,0Ch,18h,30h,66h,46h,00h  ; 37 %
DB 38h,6Ch,38h,76h,0DCh,0CCh,76h,00h; 38 &
DB 18h,18h,30h,00h,00h,00h,00h,00h  ; 39 '
DB 0Ch,18h,30h,30h,30h,18h,0Ch,00h  ; 40 (
DB 30h,18h,0Ch,0Ch,0Ch,18h,30h,00h  ; 41 )
DB 00h,66h,3Ch,0FFh,3Ch,66h,00h,00h ; 42 *
DB 00h,18h,18h,7Eh,18h,18h,00h,00h  ; 43 +
DB 00h,00h,00h,00h,00h,18h,18h,30h  ; 44 ,
DB 00h,00h,00h,7Eh,00h,00h,00h,00h  ; 45 -
DB 00h,00h,00h,00h,00h,18h,18h,00h  ; 46 .
DB 06h,0Ch,18h,30h,60h,0C0h,80h,00h ; 47 /
DB 3Ch,66h,6Eh,76h,66h,66h,3Ch,00h  ; 48 0
DB 18h,38h,18h,18h,18h,18h,7Eh,00h  ; 49 1
DB 3Ch,66h,06h,0Ch,18h,30h,7Eh,00h  ; 50 2
DB 3Ch,66h,06h,1Ch,06h,66h,3Ch,00h  ; 51 3
DB 0Ch,1Ch,3Ch,6Ch,0FEh,0Ch,0Ch,00h ; 52 4
DB 7Eh,60h,7Ch,06h,06h,66h,3Ch,00h  ; 53 5
DB 1Ch,30h,60h,7Ch,66h,66h,3Ch,00h  ; 54 6
DB 7Eh,06h,0Ch,18h,30h,30h,30h,00h  ; 55 7
DB 3Ch,66h,66h,3Ch,66h,66h,3Ch,00h  ; 56 8
DB 3Ch,66h,66h,3Eh,06h,0Ch,38h,00h  ; 57 9
DB 00h,18h,18h,00h,00h,18h,18h,00h  ; 58 :
DB 00h,18h,18h,00h,00h,18h,18h,30h  ; 59 ;
DB 0Eh,18h,30h,60h,30h,18h,0Eh,00h  ; 60 <
DB 00h,00h,7Eh,00h,7Eh,00h,00h,00h  ; 61 =
DB 70h,18h,0Ch,06h,0Ch,18h,70h,00h  ; 62 >
DB 3Ch,66h,06h,1Ch,18h,00h,18h,00h  ; 63 ?
DB 3Ch,66h,6Eh,6Ah,6Eh,60h,3Ch,00h  ; 64 @
DB 18h,3Ch,66h,7Eh,66h,66h,66h,00h  ; 65 A
DB 7Ch,66h,66h,7Ch,66h,66h,7Ch,00h  ; 66 B
DB 3Ch,66h,60h,60h,60h,66h,3Ch,00h  ; 67 C
DB 78h,6Ch,66h,66h,66h,6Ch,78h,00h  ; 68 D
DB 7Eh,60h,60h,78h,60h,60h,7Eh,00h  ; 69 E
DB 7Eh,60h,60h,78h,60h,60h,60h,00h  ; 70 F
DB 3Ch,66h,60h,6Eh,66h,66h,3Ch,00h  ; 71 G
DB 66h,66h,66h,7Eh,66h,66h,66h,00h  ; 72 H
DB 7Eh,18h,18h,18h,18h,18h,7Eh,00h  ; 73 I
DB 06h,06h,06h,06h,06h,66h,3Ch,00h  ; 74 J
DB 66h,6Ch,78h,70h,78h,6Ch,66h,00h  ; 75 K
DB 60h,60h,60h,60h,60h,60h,7Eh,00h  ; 76 L
DB 63h,77h,7Fh,6Bh,63h,63h,63h,00h  ; 77 M
DB 66h,76h,7Eh,7Eh,6Eh,66h,66h,00h  ; 78 N
DB 3Ch,66h,66h,66h,66h,66h,3Ch,00h  ; 79 O
DB 7Ch,66h,66h,7Ch,60h,60h,60h,00h  ; 80 P
DB 3Ch,66h,66h,66h,6Eh,3Ch,06h,00h  ; 81 Q
DB 7Ch,66h,66h,7Ch,6Ch,66h,66h,00h  ; 82 R
DB 3Ch,66h,60h,3Ch,06h,66h,3Ch,00h  ; 83 S
DB 7Eh,18h,18h,18h,18h,18h,18h,00h  ; 84 T
DB 66h,66h,66h,66h,66h,66h,3Ch,00h  ; 85 U
DB 66h,66h,66h,66h,66h,3Ch,18h,00h  ; 86 V
DB 63h,63h,63h,6Bh,7Fh,77h,63h,00h  ; 87 W
DB 66h,66h,3Ch,18h,3Ch,66h,66h,00h  ; 88 X
DB 66h,66h,66h,3Ch,18h,18h,18h,00h  ; 89 Y
DB 7Eh,06h,0Ch,18h,30h,60h,7Eh,00h  ; 90 Z

; ============================================================
inicio:
    ; En .COM: CS=DS=ES=SS, todo en un segmento
    mov  ax, cs
    mov  ds, ax
    mov  es, ax
    mov  ss, ax
    mov  sp, 0FFFEh

    mov  ax, 0013h
    int  10h

    mov  ah, 00h
    int  1Ah
    mov  [seed], dx

    call pantalla_inicio
    call random_pos
    mov  byte ptr [rotacion], 0

; Dibujo inicial antes del loop
    call cls
    call borde
    call hud
    call draw_nombres

; ============================================================
main_loop:
    ; Esperar tecla BLOQUEANTE (no redibuja en loop vacio)
    call get_key
    ; Redibujar UNA vez tras la tecla, sincronizado con VGA
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

    mov  si, offset msg_tit
    mov  cx, 88
    mov  dx, 60
    mov  al, COL_WHT
    call draw_str

    mov  si, offset msg_ask
    mov  cx, 92
    mov  dx, 82
    mov  al, COL_WHT
    call draw_str

    mov  si, offset msg_si
    mov  cx, 95
    mov  dx, 105
    mov  al, COL_GRN
    call draw_str

    mov  si, offset msg_no
    mov  cx, 95
    mov  dx, 120
    mov  al, COL_RED
    call draw_str

    mov  si, offset nombre1
    mov  cx, 110
    mov  dx, 148
    mov  al, COL_T1
    call draw_str

    mov  si, offset nombre2
    mov  cx, 110
    mov  dx, 161
    mov  al, COL_T2
    call draw_str

pi_wait:
    mov  ah, 00h
    int  16h
    cmp  ah, 1Ch
    je   pi_ok
    cmp  ah, 01h
    je   pi_sal
    jmp  pi_wait
pi_ok:
    ret
pi_sal:
    call modo_texto
    mov  ax, 4C00h
    int  21h

; ============================================================
; HUD
; ============================================================
hud:
    mov  si, offset msg_hud
    mov  cx, 8
    mov  dx, 191
    mov  al, COL_BRD
    call draw_str

    cmp  byte ptr [rotacion], 1
    je   hud1
    cmp  byte ptr [rotacion], 2
    je   hud2
    cmp  byte ptr [rotacion], 3
    je   hud3
    mov  si, offset lbl0
    jmp  hud_show
hud1:
    mov  si, offset lbl1
    jmp  hud_show
hud2:
    mov  si, offset lbl2
    jmp  hud_show
hud3:
    mov  si, offset lbl3
hud_show:
    mov  cx, 212
    mov  dx, 4
    mov  al, COL_WHT
    call draw_str
    ret

; ============================================================
; DRAW_NOMBRES
; ============================================================
draw_nombres:
    cmp  byte ptr [rotacion], 1
    je   dn_izq
    cmp  byte ptr [rotacion], 2
    je   dn_180
    cmp  byte ptr [rotacion], 3
    je   dn_der

dn_normal:
    mov  si, offset nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_str
    mov  si, offset nombre2
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 14
    mov  al, COL_T2
    call draw_str
    ret

dn_izq:
    mov  si, offset nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 70
    mov  al, COL_T1
    call draw_r90l
    mov  si, offset nombre2
    mov  cx, [pos_x]
    add  cx, 14
    mov  dx, [pos_y]
    add  dx, 70
    mov  al, COL_T2
    call draw_r90l
    ret

dn_180:
    mov  si, offset nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_r180
    mov  si, offset nombre2
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    add  dx, 14
    mov  al, COL_T2
    call draw_r180
    ret

dn_der:
    mov  si, offset nombre1
    mov  cx, [pos_x]
    mov  dx, [pos_y]
    mov  al, COL_T1
    call draw_r90r
    mov  si, offset nombre2
    mov  cx, [pos_x]
    add  cx, 14
    mov  dx, [pos_y]
    mov  al, COL_T2
    call draw_r90r
    ret

; ============================================================
; DRAW_STR - texto horizontal normal
; SI=cadena  CX=x  DX=y  AL=color
; Modo indexado valido: [bx+si] donde bx=base, si=offset
; ============================================================
draw_str:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov  di, dx

ds_char:
    mov  al, [si]
    or   al, al
    jz   ds_fin
    mov  ah, 0
    sub  ax, 32
    jl   ds_next
    cmp  ax, 58
    jg   ds_next

    ; Calcular puntero al bitmap
    ; bx = ax * 8 (offset en font)
    ; Usamos bx como base, indice de fila con desplazamiento directo
    push cx
    push di
    push si
    push ax             ; guardar indice caracter

    mov  bx, ax
    shl  bx, 1
    shl  bx, 1
    shl  bx, 1          ; bx = ax * 8  (3 shifts = *8)
    add  bx, offset font

    ; Dibujar 8 filas
    mov  ah, 0          ; ah = fila actual (0..7)
ds_fila:
    cmp  ah, 8
    je   ds_char_done

    ; Leer byte de fila: [bx + ah] -> bx=base, desplaz=ah
    ; En 8086 no se puede [bx+ah], solo [bx+constante]
    ; Solucion: usar si como puntero directo (bx+ah calculado)
    push bx
    mov  bl, ah
    mov  bh, 0
    add  bx, offset font ; recalcular: usamos si=puntero directo
    pop  bx

    ; La forma correcta: copiar bx a si, usar si como puntero
    ; y acceder [si] con increment manual
    push ax             ; guardar fila actual
    mov  al, ah         ; al = fila
    mov  ah, 0
    push bx
    add  bx, ax         ; bx = base + fila
    mov  al, [bx]       ; leer byte de fila
    pop  bx
    mov  dl, al         ; dl = byte de la fila
    pop  ax             ; restaurar fila actual

    push cx
    mov  dh, 8          ; contador columnas
ds_col:
    test dl, 80h
    jz   ds_nopix
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
ds_nopix:
    shl  dl, 1
    inc  cx
    dec  dh
    jnz  ds_col
    pop  cx

    inc  ah             ; siguiente fila
    inc  di             ; siguiente fila en pantalla
    jmp  ds_fila

ds_char_done:
    pop  ax
    pop  si
    pop  di
    pop  cx
    add  cx, 9

ds_next:
    inc  si
    jmp  ds_char

ds_fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; Rutina auxiliar: dada cadena en SI, obtener bitmap en BX
; y fila en AH, devuelve byte de esa fila en AL
; (evita modo indexado ilegal)
; BX = base del bitmap del caracter, AH = fila (0..7)
; Devuelve AL = byte
; ============================================================
get_font_byte:
    push bx
    mov  al, ah
    mov  ah, 0
    add  bx, ax
    mov  al, [bx]
    pop  bx
    ret

; ============================================================
; DRAW_STR_V2 - version simplificada que usa puntero SI directo
; Reemplaza a draw_str con logica mas clara para rotaciones
; BX = offset en font (caracter*8), AH = fila
; Devuelve: DL = byte de esa fila
; ============================================================
read_font_row:
    ; BX = puntero base del char en font
    ; DH = fila (0..7)
    ; Devuelve: AL = byte
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
; DRAW_R90L - 90 grados izquierda
;
; Para que las letras queden verticales leibles de abajo->arriba:
;   pantalla_x = drw_x + c      (columna original = eje horizontal)
;   pantalla_y = drw_y - f      (fila original    = eje vertical, arriba)
;
; Cada caracter ocupa 8px de ancho (cols 0-7) y avanza drw_y += 9
; para que el siguiente caracter quede ENCIMA del anterior
; (leemos de abajo hacia arriba)
;
; SI=cadena  CX=x  DX=y(punto inferior)  AL=color
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

r90l_char:
    mov  al, [si]
    or   al, al
    jnz  r90l_char_ok
    jmp  r90l_fin
r90l_char_ok:
    mov  ah, 0
    sub  ax, 32
    jb   r90l_next
    cmp  ax, 58
    ja   r90l_next

    push si

    ; bx = &font[char_idx * 8]
    mov  bx, ax
    shl  bx, 1
    shl  bx, 1
    shl  bx, 1
    add  bx, offset font

    ; Iterar fila f = 0..7
    mov  dh, 0            ; dh = f
r90l_floop:
    cmp  dh, 8
    je   r90l_fdone

    call read_font_row    ; BX=base, DH=fila -> AL=byte
    mov  dl, al           ; dl = byte ORIGINAL de la fila

    ; Iterar columna c = 0..7 con mascara deslizante
    mov  ch, 80h          ; ch = mascara bit (80h=col0, 40h=col1...)
    mov  cl, 0            ; cl = c

r90l_cloop:
    cmp  cl, 8
    je   r90l_cdone

    test dl, ch
    jz   r90l_nopix

    push bx
    push cx
    push dx

    ; pantalla_x = drw_x + c
    mov  bx, [drw_x]
    mov  al, cl
    mov  ah, 0
    add  bx, ax
    mov  cx, bx

    ; pantalla_y = drw_y - f
    mov  bx, [drw_y]
    mov  al, dh
    mov  ah, 0
    sub  bx, ax
    mov  di, bx

    mov  ah, [drw_col]
    call pix

    pop  dx
    pop  cx
    pop  bx

r90l_nopix:
    shr  ch, 1
    inc  cl
    jmp  r90l_cloop

r90l_cdone:
    inc  dh
    jmp  r90l_floop

r90l_fdone:
    pop  si
    ; Siguiente caracter: mover drw_y hacia ARRIBA 9px
    ; (para leer la cadena de abajo hacia arriba)
    sub  word ptr [drw_y], 9

r90l_next:
    inc  si
    jmp  r90l_char

r90l_fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; DRAW_R90R - 90 grados derecha
;
; Para que las letras queden verticales leibles de arriba->abajo:
;   pantalla_x = drw_x + (7 - c)   (columna invertida = eje X)
;   pantalla_y = drw_y + f          (fila original     = eje Y)
;
; Cada caracter avanza drw_y += 9
;
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

r90r_char:
    mov  al, [si]
    or   al, al
    jnz  r90r_char_ok
    jmp  r90r_fin
r90r_char_ok:
    mov  ah, 0
    sub  ax, 32
    jnb  r90r_check_hi
    jmp  r90r_next
r90r_check_hi:
    cmp  ax, 58
    ja   r90r_next

    push si

    mov  bx, ax
    shl  bx, 1
    shl  bx, 1
    shl  bx, 1
    add  bx, offset font

    mov  dh, 0            ; dh = f
r90r_floop:
    cmp  dh, 8
    je   r90r_fdone

    call read_font_row    ; AL = byte de fila f
    mov  dl, al           ; dl = byte ORIGINAL

    mov  ch, 80h          ; mascara deslizante
    mov  cl, 0            ; cl = c

r90r_cloop:
    cmp  cl, 8
    je   r90r_cdone

    test dl, ch
    jz   r90r_nopix

    push bx
    push cx
    push dx

    ; pantalla_x = drw_x + (7 - c)
    mov  bx, 7
    mov  al, cl
    mov  ah, 0
    sub  bx, ax
    add  bx, [drw_x]
    mov  cx, bx

    ; pantalla_y = drw_y + f
    mov  bx, [drw_y]
    mov  al, dh
    mov  ah, 0
    add  bx, ax
    mov  di, bx

    mov  ah, [drw_col]
    call pix

    pop  dx
    pop  cx
    pop  bx

r90r_nopix:
    shr  ch, 1
    inc  cl
    jmp  r90r_cloop

r90r_cdone:
    inc  dh
    jmp  r90r_floop

r90r_fdone:
    pop  si
    add  word ptr [drw_y], 9

r90r_next:
    inc  si
    jmp  r90r_char

r90r_fin:
    pop  di
    pop  si
    pop  dx
    pop  cx
    pop  bx
    pop  ax
    ret

; ============================================================
; DRAW_R180 - 180 grados (invertido)
; pixel[f][c] -> pantalla(base_x + ancho - 1 - c, base_y + (7-f))
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
    mov  bx, 0
r180_len:
    cmp  byte ptr [si+bx], 0
    je   r180_lend
    inc  bx
    jmp  r180_len
r180_lend:
    mov  ax, bx
    mov  bx, 9
    mul  bx
    pop  si
    add  cx, ax
    mov  [drw_x], cx    ; drw_x = x + longitud*9 (empezar desde derecha)

r180_char:
    mov  al, [si]
    or   al, al
    jz   r180_fin
    mov  ah, 0
    sub  ax, 32
    jb   r180_next
    cmp  ax, 58
    ja   r180_next

    sub  word ptr [drw_x], 9

    push si

    mov  bx, ax
    shl  bx, 1
    shl  bx, 1
    shl  bx, 1
    add  bx, offset font

    ; f = 7 downto 0 (invertir eje vertical)
    mov  dh, 7
r180_f:
    cmp  dh, 0FFh
    je   r180_fdone

    call read_font_row
    mov  dl, al

    ; Invertir byte (espejo horizontal)
    push cx
    mov  al, dl
    mov  dl, 0
    mov  cx, 8
r180_inv:
    shl  al, 1
    rcr  dl, 1
    loop r180_inv
    pop  cx
    ; dl = byte invertido

    ; Dibujar fila en pantalla
    ; y_pantalla = drw_y + (7 - dh)
    push bx
    push dx

    mov  cx, [drw_x]    ; x = drw_x (empezar desde izquierda del char)

    mov  bl, 7
    mov  bh, 0
    mov  al, dh
    mov  ah, 0
    sub  bx, ax
    mov  di, [drw_y]
    add  di, bx         ; di = drw_y + (7 - f)

    mov  bx, 8          ; contador columnas
r180_col:
    test dl, 80h
    jz   r180_nopix
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
r180_nopix:
    shl  dl, 1
    inc  cx
    dec  bx
    jnz  r180_col

    pop  dx
    pop  bx

    dec  dh
    jmp  r180_f

r180_fdone:
    pop  si

r180_next:
    inc  si
    jmp  r180_char

r180_fin:
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
    jae  pix_out
    cmp  di, SCR_H
    jae  pix_out

    mov  bx, VGA_SEG
    mov  es, bx

    ; offset = y*320 + x
    mov  ax, di
    mov  bx, SCR_W
    mul  bx
    add  ax, cx
    mov  di, ax
    mov  al, ah
    stosb

pix_out:
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

    ; Superior
    mov  di, 5
    mov  cx, 5
borde_t:
    cmp  cx, 314
    jg   borde_b
    mov  ah, COL_BRD
    call pix
    inc  cx
    jmp  borde_t

    ; Inferior
borde_b:
    mov  di, 186
    mov  cx, 5
borde_b2:
    cmp  cx, 314
    jg   borde_l
    mov  ah, COL_BRD
    call pix
    inc  cx
    jmp  borde_b2

    ; Izquierda
borde_l:
    mov  cx, 5
    mov  di, 5
borde_l2:
    cmp  di, 186
    jg   borde_r
    mov  ah, COL_BRD
    call pix
    inc  di
    jmp  borde_l2

    ; Derecha
borde_r:
    mov  cx, 314
    mov  di, 5
borde_r2:
    cmp  di, 186
    jg   borde_fin
    mov  ah, COL_BRD
    call pix
    inc  di
    jmp  borde_r2

borde_fin:
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

    mov  ah, 00h
    int  1Ah

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
; GET_KEY - leer teclado
; ============================================================
get_key:
    ; Esperar BLOQUEANTE hasta que haya una tecla
    mov  ah, 01h
    int  16h
    jnz  gk_leer        ; hay tecla, procesarla
    jmp  get_key        ; sin tecla, seguir esperando
gk_leer:

    mov  ah, 00h
    int  16h

    ; ESC
    cmp  ah, 01h
    jne  gk_no_esc
    call modo_texto
    mov  ax, 4C00h
    int  21h
gk_no_esc:

    ; R - reiniciar
    cmp  ah, 13h
    jne  gk_no_r
    call random_pos
    mov  byte ptr [rotacion], 0
    ret
gk_no_r:

    ; WASD minusculas
    cmp  al, 'a'
    jne  gk_no_a1
    jmp  gk_izq
gk_no_a1:
    cmp  al, 'A'
    jne  gk_no_a2
    jmp  gk_izq
gk_no_a2:
    cmp  al, 'd'
    jne  gk_no_d1
    jmp  gk_der
gk_no_d1:
    cmp  al, 'D'
    jne  gk_no_d2
    jmp  gk_der
gk_no_d2:
    cmp  al, 'w'
    jne  gk_no_w1
    jmp  gk_arr
gk_no_w1:
    cmp  al, 'W'
    jne  gk_no_w2
    jmp  gk_arr
gk_no_w2:
    cmp  al, 's'
    jne  gk_no_s1
    jmp  gk_aba
gk_no_s1:
    cmp  al, 'S'
    jne  gk_no_s2
    jmp  gk_aba
gk_no_s2:

    ; Flechas (al=00h o E0h)
    cmp  al, 00h
    je   gk_flecha
    cmp  al, 0E0h
    je   gk_flecha
    jmp  gk_nada

gk_flecha:
    cmp  ah, 4Bh
    jne  gk_nof_l
    jmp  gk_izq
gk_nof_l:
    cmp  ah, 4Dh
    jne  gk_nof_r
    jmp  gk_der
gk_nof_r:
    cmp  ah, 48h
    jne  gk_nof_u
    jmp  gk_arr
gk_nof_u:
    cmp  ah, 50h
    jne  gk_nada
    jmp  gk_aba

gk_izq:
    mov  al, byte ptr [rotacion]
    dec  al
    and  al, 03h
    mov  byte ptr [rotacion], al
    ret

gk_der:
    mov  al, byte ptr [rotacion]
    inc  al
    and  al, 03h
    mov  byte ptr [rotacion], al
    ret

gk_arr:
    mov  al, byte ptr [rotacion]
    xor  al, 02h
    mov  byte ptr [rotacion], al
    ret

gk_aba:
    mov  al, byte ptr [rotacion]
    xor  al, 02h
    mov  byte ptr [rotacion], al
    ret

gk_nada:
    jmp  get_key        ; tecla no reconocida, seguir esperando

; ============================================================
; WAIT_VSYNC - esperar vertical blank del VGA
; Elimina el parpadeo esperando que el haz este fuera de pantalla
; Puerto 3DAh bit 3: 1 = en vertical retrace
; ============================================================
wait_vsync:
    push ax
    push dx
    mov  dx, 03DAh

    ; Esperar a que TERMINE el retrace actual (por si ya estamos en el)
vs_wait_end:
    in   al, dx
    test al, 08h
    jnz  vs_wait_end    ; si bit3=1, esperar a que baje

    ; Ahora esperar a que EMPIECE el proximo retrace
vs_wait_start:
    in   al, dx
    test al, 08h
    jz   vs_wait_start  ; si bit3=0, esperar a que suba

    pop  dx
    pop  ax
    ret

; ============================================================
; MODO_TEXTO
; ============================================================
modo_texto:
    mov  ax, 0003h
    int  10h
    ret

END inicio