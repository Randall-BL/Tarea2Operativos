; ============================================================
; boot_uefi.asm - Menu UEFI + juego UEFI x86-64 (PE32+)
; ============================================================

BITS 64
DEFAULT REL

IMAGE_BASE  EQU 0x0000000000400000
CODE_RVA    EQU 0x1000
CODE_SIZE   EQU 0x8000
IMAGE_SIZE  EQU 0x9000
HDR_SIZE    EQU 0x0200
CODE_FOFF   EQU 0x1000

ST_CONIN_OFF        EQU 48
ST_CONOUT_OFF       EQU 64
ST_BOOTSERV_OFF     EQU 96

CONIN_READKEY_OFF   EQU 8
CONIN_WAITKEY_OFF   EQU 16

CONOUT_OUTSTR_OFF   EQU 8
CONOUT_CLEAR_OFF    EQU 48

BS_WAITFOR_OFF      EQU 96
BS_LOCATEPROTO_OFF  EQU 320

GOP_MODE_OFF        EQU 24
GOPM_INFO_OFF       EQU 8
GOPM_FB_BASE_OFF    EQU 24
GOPI_HRES_OFF       EQU 4
GOPI_VRES_OFF       EQU 8
GOPI_PXFORMAT_OFF   EQU 12
GOPI_PPSL_OFF       EQU 32

EFI_SCAN_UP         EQU 1
EFI_SCAN_DOWN       EQU 2
EFI_SCAN_RIGHT      EQU 3
EFI_SCAN_LEFT       EQU 4
EFI_SCAN_ESC        EQU 23

SCR_W               EQU 320
SCR_H               EQU 200

COL_BG              EQU 0
COL_T1              EQU 1
COL_T2              EQU 2
COL_BRD             EQU 3
COL_WHT             EQU 4
COL_GRN             EQU 5
COL_RED             EQU 6

ORG IMAGE_BASE

dw 0x5A4D
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
dd 0x00000040

db 'PE', 0, 0

dw 0x8664
dw 1
dd 0
dd 0
dd 0
dw 240
dw 0x0206

dw 0x020B
db 0, 0
dd CODE_SIZE
dd 0
dd 0
dd CODE_RVA
dd CODE_RVA
dq IMAGE_BASE
dd 0x1000
dd 0x0200
dw 0, 0
dw 0, 0
dw 0, 0
dd 0
dd IMAGE_SIZE
dd HDR_SIZE
dd 0
dw 10
dw 0
dq 0
dq 0
dq 0
dq 0
dd 0
dd 16
times 16 dq 0

db '.text', 0, 0, 0
dd CODE_SIZE
dd CODE_RVA
dd CODE_SIZE
dd CODE_FOFF
dd 0
dd 0
dw 0
dw 0
dd 0x60000020

times (HDR_SIZE - ($ - $$)) db 0
times (CODE_FOFF - HDR_SIZE) db 0

_code_start:

efi_main:
    push    rbx
    sub     rsp, 32

    mov     [st_ptr], rdx
    mov     rax, [rdx + ST_BOOTSERV_OFF]
    mov     [bs_ptr], rax
    mov     rax, [rdx + ST_CONIN_OFF]
    mov     [conin_ptr], rax
    mov     rax, [rdx + ST_CONOUT_OFF]
    mov     [conout_ptr], rax

.menu:
    call    text_clear
    lea     rdx, [msg_title]
    call    text_print
    lea     rdx, [msg_info]
    call    text_print
    lea     rdx, [msg_menu]
    call    text_print

.menu_wait:
    call    wait_key
    movzx   eax, word [input_key + 2]
    cmp     eax, 13
    je      .launch_game
    cmp     eax, 27
    je      .exit
    movzx   eax, word [input_key]
    cmp     eax, EFI_SCAN_ESC
    je      .exit
    jmp     .menu_wait

.launch_game:
    call    demo_hola
    jmp     .menu

.exit:
    call    text_clear
    lea     rdx, [msg_bye]
    call    text_print
    xor     eax, eax
    add     rsp, 32
    pop     rbx
    ret

text_clear:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 32
    mov     rcx, [conout_ptr]
    call    qword [rcx + CONOUT_CLEAR_OFF]
    leave
    ret

text_print:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 32
    mov     rcx, [conout_ptr]
    call    qword [rcx + CONOUT_OUTSTR_OFF]
    leave
    ret

wait_key:
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 32
    mov     rax, [conin_ptr]
    mov     rax, [rax + CONIN_WAITKEY_OFF]
    mov     [wait_event], rax
    mov     rcx, 1
    lea     rdx, [wait_event]
    lea     r8,  [wait_index]
    mov     rax, [bs_ptr]
    call    qword [rax + BS_WAITFOR_OFF]
.read:
    mov     rcx, [conin_ptr]
    lea     rdx, [input_key]
    call    qword [rcx + CONIN_READKEY_OFF]
    test    rax, rax
    jnz     .read
    leave
    ret

game_main:
    call    init_gop
    test    eax, eax
    jz      .ok
    call    text_clear
    lea     rdx, [msg_gop_error]
    call    text_print
    call    wait_key
    xor     eax, eax
    ret
.ok:
    rdtsc
    xor     eax, edx
    mov     [seed], eax
    mov     byte [rotacion], 0
    call    random_pos
.loop:
    call    render_frame
    call    wait_key
    movzx   eax, word [input_key]
    cmp     eax, EFI_SCAN_ESC
    je      .done
    cmp     eax, EFI_SCAN_LEFT
    je      .left
    cmp     eax, EFI_SCAN_RIGHT
    je      .right
    cmp     eax, EFI_SCAN_UP
    je      .flip
    cmp     eax, EFI_SCAN_DOWN
    je      .flip
    movzx   eax, word [input_key + 2]
    cmp     eax, 27
    je      .done
    cmp     eax, 'a'
    je      .left
    cmp     eax, 'A'
    je      .left
    cmp     eax, 'd'
    je      .right
    cmp     eax, 'D'
    je      .right
    cmp     eax, 'w'
    je      .flip
    cmp     eax, 'W'
    je      .flip
    cmp     eax, 's'
    je      .flip
    cmp     eax, 'S'
    je      .flip
    cmp     eax, 'r'
    je      .reset
    cmp     eax, 'R'
    je      .reset
    jmp     .loop
.reset:
    call    random_pos
    mov     byte [rotacion], 0
    jmp     .loop
.left:
    mov     al, [rotacion]
    dec     al
    and     al, 3
    mov     [rotacion], al
    jmp     .loop
.right:
    mov     al, [rotacion]
    inc     al
    and     al, 3
    mov     [rotacion], al
    jmp     .loop
.flip:
    mov     al, [rotacion]
    xor     al, 2
    mov     [rotacion], al
    jmp     .loop
.done:
    xor     eax, eax
    ret

demo_hola:
    call    init_gop
    test    eax, eax
    jz      .ok
    call    text_clear
    lea     rdx, [msg_gop_error]
    call    text_print
    call    wait_key
    xor     eax, eax
    ret
.ok:
    mov     ecx, COL_BG
    call    clear_frame
    lea     rsi, [msg_hola]
    mov     ecx, 142
    mov     edx, 96
    mov     r8d, COL_WHT
    call    draw_str
    call    wait_key
    xor     eax, eax
    ret

init_gop:
    push    rbx
    push    rbp
    mov     rbp, rsp
    and     rsp, -16
    sub     rsp, 32
    lea     rcx, [gop_guid]
    xor     edx, edx
    lea     r8,  [gop_ptr]
    mov     rax, [bs_ptr]
    call    qword [rax + BS_LOCATEPROTO_OFF]
    test    rax, rax
    jnz     .fail
    mov     rbx, [gop_ptr]
    mov     rbx, [rbx + GOP_MODE_OFF]
    mov     rax, [rbx + GOPM_INFO_OFF]
    mov     ecx, [rax + GOPI_HRES_OFF]
    mov     [screen_w], ecx
    mov     ecx, [rax + GOPI_VRES_OFF]
    mov     [screen_h], ecx
    mov     ecx, [rax + GOPI_PXFORMAT_OFF]
    mov     [pixel_format], ecx
    mov     ecx, [rax + GOPI_PPSL_OFF]
    mov     [pixels_per_scanline], ecx
    mov     rax, [rbx + GOPM_FB_BASE_OFF]
    mov     [fb_base], rax
    mov     eax, [screen_w]
    sub     eax, SCR_W
    js      .vx0
    shr     eax, 1
    mov     [viewport_x], eax
    jmp     .vy
.vx0:
    mov     dword [viewport_x], 0
.vy:
    mov     eax, [screen_h]
    sub     eax, SCR_H
    js      .vy0
    shr     eax, 1
    mov     [viewport_y], eax
    jmp     .ok2
.vy0:
    mov     dword [viewport_y], 0
.ok2:
    xor     eax, eax
    jmp     .exit
.fail:
    mov     eax, 1
.exit:
    leave
    pop     rbx
    ret

render_frame:
    mov     ecx, COL_BG
    call    clear_frame
    call    draw_border
    call    draw_hud
    call    draw_names
    ret

clear_frame:
    push    rdi
    push    rcx
    call    color_to_pixel
    mov     r10d, eax
    mov     rdi, [fb_base]
    mov     eax, [pixels_per_scanline]
    imul    eax, dword [screen_h]
    mov     ecx, eax
    mov     eax, r10d
    cld
    rep stosd
    pop     rcx
    pop     rdi
    ret

draw_border:
    mov     edx, 2
    mov     ecx, 2
.t:
    cmp     ecx, 317
    jg      .b
    mov     r8d, COL_BRD
    call    plot_pixel
    inc     ecx
    jmp     .t
.b:
    mov     edx, 197
    mov     ecx, 2
.b2:
    cmp     ecx, 317
    jg      .l
    mov     r8d, COL_BRD
    call    plot_pixel
    inc     ecx
    jmp     .b2
.l:
    mov     ecx, 2
    mov     edx, 2
.l2:
    cmp     edx, 197
    jg      .r
    mov     r8d, COL_BRD
    call    plot_pixel
    inc     edx
    jmp     .l2
.r:
    mov     ecx, 317
    mov     edx, 2
.r2:
    cmp     edx, 197
    jg      .done
    mov     r8d, COL_BRD
    call    plot_pixel
    inc     edx
    jmp     .r2
.done:
    ret

draw_hud:
    lea     rsi, [msg_hud]
    mov     ecx, 8
    mov     edx, 191
    mov     r8d, COL_BRD
    call    draw_str
    movzx   eax, byte [rotacion]
    cmp     eax, 1
    je      .h1
    cmp     eax, 2
    je      .h2
    cmp     eax, 3
    je      .h3
    lea     rsi, [lbl0]
    jmp     .show
.h1:
    lea     rsi, [lbl1]
    jmp     .show
.h2:
    lea     rsi, [lbl2]
    jmp     .show
.h3:
    lea     rsi, [lbl3]
.show:
    mov     ecx, 212
    mov     edx, 4
    mov     r8d, COL_WHT
    call    draw_str
    ret

draw_names:
    movzx   eax, byte [rotacion]
    cmp     eax, 1
    je      .izq
    cmp     eax, 2
    je      .r180
    cmp     eax, 3
    je      .der
.normal:
    lea     rsi, [nombre1]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    mov     r8d, COL_T1
    call    draw_str
    lea     rsi, [nombre2]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    add     edx, 14
    mov     r8d, COL_T2
    call    draw_str
    ret
.izq:
    lea     rsi, [nombre1]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    add     edx, 70
    mov     r8d, COL_T1
    call    draw_r90l
    lea     rsi, [nombre2]
    mov     ecx, [pos_x]
    add     ecx, 14
    mov     edx, [pos_y]
    add     edx, 70
    mov     r8d, COL_T2
    call    draw_r90l
    ret
.r180:
    lea     rsi, [nombre1]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    mov     r8d, COL_T1
    call    draw_r180
    lea     rsi, [nombre2]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    add     edx, 14
    mov     r8d, COL_T2
    call    draw_r180
    ret
.der:
    lea     rsi, [nombre1]
    mov     ecx, [pos_x]
    mov     edx, [pos_y]
    mov     r8d, COL_T1
    call    draw_r90r
    lea     rsi, [nombre2]
    mov     ecx, [pos_x]
    add     ecx, 14
    mov     edx, [pos_y]
    mov     r8d, COL_T2
    call    draw_r90r
    ret

random_pos:
    mov     eax, [seed]
    imul    eax, eax, 1664525
    add     eax, 1013904223
    mov     [seed], eax
    xor     edx, edx
    mov     ecx, 160
    div     ecx
    add     edx, 20
    mov     [pos_x], edx
    mov     eax, [seed]
    imul    eax, eax, 1664525
    add     eax, 1013904223
    mov     [seed], eax
    xor     edx, edx
    mov     ecx, 120
    div     ecx
    add     edx, 20
    mov     [pos_y], edx
    ret

draw_str:
    mov     [ds_xbase], ecx
    mov     [ds_ybase], edx
    mov     [drw_col], r8d
.char:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .done
    inc     rsi
    sub     eax, 32
    jb      .char
    cmp     eax, 58
    ja      .char
    mov     ebx, eax
    shl     ebx, 3
    lea     r9, [font + rbx]
    mov     dword [tmp_fila], 0
.row:
    cmp     dword [tmp_fila], 8
    je      .next
    lea     r9, [font + rbx]
    mov     eax, [tmp_fila]
    movzx   eax, byte [r9 + rax]
    mov     [tmp_byte], eax
    mov     dword [tmp_col], 0
.col:
    cmp     dword [tmp_col], 8
    je      .row_next
    mov     eax, [tmp_byte]
    mov     ecx, 7
    sub     ecx, [tmp_col]
    shr     eax, cl
    and     eax, 1
    jz      .skip
    mov     ecx, [ds_xbase]
    add     ecx, [tmp_col]
    mov     edx, [ds_ybase]
    add     edx, [tmp_fila]
    mov     r8d, [drw_col]
    call    plot_pixel
.skip:
    inc     dword [tmp_col]
    jmp     .col
.row_next:
    inc     dword [tmp_fila]
    jmp     .row
.next:
    add     dword [ds_xbase], 9
    jmp     .char
.done:
    ret

draw_r90l:
    mov     [drw_x], ecx
    mov     [drw_y], edx
    mov     [drw_col], r8d
.char:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .done
    sub     eax, 32
    jb      .next
    cmp     eax, 58
    ja      .next
    mov     ebx, eax
    shl     ebx, 3
    lea     r9, [font + rbx]
    mov     dword [tmp_fila], 0
.row:
    cmp     dword [tmp_fila], 8
    je      .nextchar
    lea     r9, [font + rbx]
    mov     eax, [tmp_fila]
    movzx   eax, byte [r9 + rax]
    mov     [tmp_byte], eax
    mov     dword [tmp_col], 0
.col:
    cmp     dword [tmp_col], 8
    je      .row_next
    mov     eax, [tmp_byte]
    mov     ecx, 7
    sub     ecx, [tmp_col]
    shr     eax, cl
    and     eax, 1
    jz      .skip
    mov     ecx, [drw_x]
    add     ecx, [tmp_col]
    mov     edx, [drw_y]
    sub     edx, [tmp_fila]
    mov     r8d, [drw_col]
    call    plot_pixel
.skip:
    inc     dword [tmp_col]
    jmp     .col
.row_next:
    inc     dword [tmp_fila]
    jmp     .row
.nextchar:
    sub     dword [drw_y], 9
.next:
    inc     rsi
    jmp     .char
.done:
    ret

draw_r90r:
    mov     [drw_x], ecx
    mov     [drw_y], edx
    mov     [drw_col], r8d
.char:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .done
    sub     eax, 32
    jb      .next
    cmp     eax, 58
    ja      .next
    mov     ebx, eax
    shl     ebx, 3
    lea     r9, [font + rbx]
    mov     dword [tmp_fila], 0
.row:
    cmp     dword [tmp_fila], 8
    je      .nextchar
    lea     r9, [font + rbx]
    mov     eax, [tmp_fila]
    movzx   eax, byte [r9 + rax]
    mov     [tmp_byte], eax
    mov     dword [tmp_col], 0
.col:
    cmp     dword [tmp_col], 8
    je      .row_next
    mov     eax, [tmp_byte]
    mov     ecx, 7
    sub     ecx, [tmp_col]
    shr     eax, cl
    and     eax, 1
    jz      .skip
    mov     ecx, [drw_x]
    mov     eax, 7
    sub     eax, [tmp_col]
    add     ecx, eax
    mov     edx, [drw_y]
    add     edx, [tmp_fila]
    mov     r8d, [drw_col]
    call    plot_pixel
.skip:
    inc     dword [tmp_col]
    jmp     .col
.row_next:
    inc     dword [tmp_fila]
    jmp     .row
.nextchar:
    add     dword [drw_y], 9
.next:
    inc     rsi
    jmp     .char
.done:
    ret

draw_r180:
    mov     [drw_y], edx
    mov     [drw_col], r8d
    push    rsi
    xor     ebx, ebx
.len:
    cmp     byte [rsi + rbx], 0
    je      .len_ok
    inc     ebx
    jmp     .len
.len_ok:
    imul    ebx, ebx, 9
    pop     rsi
    add     ecx, ebx
    mov     [drw_x], ecx
.char:
    movzx   eax, byte [rsi]
    test    eax, eax
    jz      .done
    sub     eax, 32
    jb      .next
    cmp     eax, 58
    ja      .next
    sub     dword [drw_x], 9
    mov     ebx, eax
    shl     ebx, 3
    lea     r9, [font + rbx]
    mov     dword [tmp_fila], 7
.row:
    cmp     dword [tmp_fila], -1
    je      .next
    lea     r9, [font + rbx]
    mov     eax, [tmp_fila]
    movzx   eax, byte [r9 + rax]
    mov     [tmp_byte], eax
    mov     dword [tmp_col], 0
.col:
    cmp     dword [tmp_col], 8
    je      .row_next
    mov     eax, [tmp_byte]
    mov     ecx, [tmp_col]
    shr     eax, cl
    and     eax, 1
    jz      .skip
    mov     ecx, [drw_x]
    add     ecx, [tmp_col]
    mov     edx, [drw_y]
    mov     eax, 7
    sub     eax, [tmp_fila]
    add     edx, eax
    mov     r8d, [drw_col]
    call    plot_pixel
.skip:
    inc     dword [tmp_col]
    jmp     .col
.row_next:
    dec     dword [tmp_fila]
    jmp     .row
.next:
    inc     rsi
    jmp     .char
.done:
    ret

plot_pixel:
    cmp     ecx, SCR_W
    jae     .out
    cmp     edx, SCR_H
    jae     .out
    add     ecx, [viewport_x]
    add     edx, [viewport_y]
    cmp     ecx, [screen_w]
    jae     .out
    cmp     edx, [screen_h]
    jae     .out
    mov     eax, edx
    imul    eax, dword [pixels_per_scanline]
    add     eax, ecx
    mov     r9, [fb_base]
    lea     r9, [r9 + rax*4]
    mov     ecx, r8d
    call    color_to_pixel
    mov     dword [r9], eax
.out:
    ret

color_to_pixel:
    cmp     ecx, 6
    jbe     .ok
    xor     ecx, ecx
.ok:
    mov     eax, ecx
    lea     rdx, [rax + rax*2]
    lea     rdx, [color_table + rdx]
    movzx   eax, byte [rdx]
    movzx   r10d, byte [rdx + 1]
    movzx   r11d, byte [rdx + 2]
    cmp     dword [pixel_format], 0
    je      .rgb
    mov     edx, eax
    mov     eax, r11d
    shl     r10d, 8
    or      eax, r10d
    shl     edx, 16
    or      eax, edx
    ret
.rgb:
    mov     edx, r11d
    shl     r10d, 8
    or      eax, r10d
    shl     edx, 16
    or      eax, edx
    ret

st_ptr               dq 0
bs_ptr               dq 0
conin_ptr            dq 0
conout_ptr           dq 0
gop_ptr              dq 0
fb_base              dq 0
wait_event           dq 0
wait_index           dq 0
input_key            dw 0, 0

screen_w             dd 0
screen_h             dd 0
pixel_format         dd 0
pixels_per_scanline  dd 0
viewport_x           dd 0
viewport_y           dd 0

rotacion             db 0
align 4
seed                 dd 0
pos_x                dd 80
pos_y                dd 80
drw_x                dd 0
drw_y                dd 0
drw_col              dd 0
ds_xbase             dd 0
ds_ybase             dd 0
tmp_fila             dd 0
tmp_col              dd 0
tmp_byte             dd 0

gop_guid:
    dd 0x9042A9DE
    dw 0x23DC
    dw 0x4A38
    db 0x96,0xFB,0x7A,0xDE,0xD0,0x80,0x51,0x6A

msg_title:
    dw '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', 13, 10
    dw ' ', 'U', 'E', 'F', 'I', ' ', 'B', 'O', 'O', 'T', ' ', '-', ' ', 'J', 'U', 'E', 'G', 'O', 13, 10
    dw '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', '=', 13, 10, 13, 10, 0
msg_info:
    dw 'E', 'N', 'T', 'E', 'R', ':', ' ', 'J', 'U', 'G', 'A', 'R', 13, 10
    dw 'E', 'S', 'C', ':', ' ', 'S', 'A', 'L', 'I', 'R', 13, 10, 13, 10, 0
msg_menu:
    dw 'W', 'A', 'S', 'D', '/', 'F', 'L', 'E', 'C', 'H', 'A', 'S', ':', ' ', 'R', 'O', 'T', 'A', 'R', 13, 10
    dw 'R', ':', ' ', 'R', 'E', 'I', 'N', 'I', 'C', 'I', 'A', 'R', 13, 10, 0
msg_bye:
    dw 'H', 'A', 'S', 'T', 'A', ' ', 'L', 'U', 'E', 'G', 'O', '.', 13, 10, 0
msg_gop_error:
    dw 'N', 'O', ' ', 'S', 'E', ' ', 'P', 'U', 'D', 'O', ' ', 'I', 'N', 'I', 'C', 'I', 'A', 'R', ' ', 'G', 'O', 'P', '.', 13, 10, 0

msg_hola             db 'HOLA', 0
nombre1              db 'RANDALL', 0
nombre2              db 'CHRIS', 0
msg_hud              db 'WASD/FLECHAS ROT  R RESET  ESC SALIR', 0
lbl0                 db 'NORMAL    ', 0
lbl1                 db 'ROT90-IZQ ', 0
lbl2                 db 'ROT 180   ', 0
lbl3                 db 'ROT90-DER ', 0

color_table:
    db   0,   0,   0
    db 255, 255,   0
    db 255,   0, 255
    db   0, 255, 255
    db 255, 255, 255
    db   0, 255,   0
    db 255,   0,   0

font:
db 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00
db 0x18,0x18,0x18,0x18,0x00,0x00,0x18,0x00
db 0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00
db 0x6C,0xFE,0x6C,0x6C,0xFE,0x6C,0x6C,0x00
db 0x18,0x3E,0x60,0x3C,0x06,0x7C,0x18,0x00
db 0x62,0x66,0x0C,0x18,0x30,0x66,0x46,0x00
db 0x38,0x6C,0x38,0x76,0xDC,0xCC,0x76,0x00
db 0x18,0x18,0x30,0x00,0x00,0x00,0x00,0x00
db 0x0C,0x18,0x30,0x30,0x30,0x18,0x0C,0x00
db 0x30,0x18,0x0C,0x0C,0x0C,0x18,0x30,0x00
db 0x00,0x66,0x3C,0xFF,0x3C,0x66,0x00,0x00
db 0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00
db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30
db 0x00,0x00,0x00,0x7E,0x00,0x00,0x00,0x00
db 0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00
db 0x06,0x0C,0x18,0x30,0x60,0xC0,0x80,0x00
db 0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00
db 0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00
db 0x3C,0x66,0x06,0x0C,0x18,0x30,0x7E,0x00
db 0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00
db 0x0C,0x1C,0x3C,0x6C,0xFE,0x0C,0x0C,0x00
db 0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00
db 0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00
db 0x7E,0x06,0x0C,0x18,0x30,0x30,0x30,0x00
db 0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00
db 0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00
db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x00
db 0x00,0x18,0x18,0x00,0x00,0x18,0x18,0x30
db 0x0E,0x18,0x30,0x60,0x30,0x18,0x0E,0x00
db 0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00
db 0x70,0x18,0x0C,0x06,0x0C,0x18,0x70,0x00
db 0x3C,0x66,0x06,0x1C,0x18,0x00,0x18,0x00
db 0x3C,0x66,0x6E,0x6A,0x6E,0x60,0x3C,0x00
db 0x18,0x3C,0x66,0x7E,0x66,0x66,0x66,0x00
db 0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00
db 0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00
db 0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00
db 0x7E,0x60,0x60,0x78,0x60,0x60,0x7E,0x00
db 0x7E,0x60,0x60,0x78,0x60,0x60,0x60,0x00
db 0x3C,0x66,0x60,0x6E,0x66,0x66,0x3C,0x00
db 0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00
db 0x7E,0x18,0x18,0x18,0x18,0x18,0x7E,0x00
db 0x06,0x06,0x06,0x06,0x06,0x66,0x3C,0x00
db 0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00
db 0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00
db 0x63,0x77,0x7F,0x6B,0x63,0x63,0x63,0x00
db 0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00
db 0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00
db 0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00
db 0x3C,0x66,0x66,0x66,0x6E,0x3C,0x06,0x00
db 0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00
db 0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00
db 0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00
db 0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00
db 0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00
db 0x63,0x63,0x63,0x6B,0x7F,0x77,0x63,0x00
db 0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00
db 0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00
db 0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00

times (CODE_SIZE - ($ - _code_start)) db 0
