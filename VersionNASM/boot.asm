; ============================================================
; boot.asm - BOOTLOADER LEGACY BIOS (MBR)
; ============================================================
;
; Propósito:
;   Bootloader de 512 bytes ejecutado por BIOS al arrancar.
;   Lee el programa principal (juego.c compilado a bin) desde el disco
;   y salta a su punto de entrada.
;
; Compilación:
;   nasm -f bin boot.asm -o build/boot.bin
;   El parámetro GAME_SECTS se pasa como: -D GAME_SECTS=N
;
; Funcionamiento:
;   1. BIOS carga este sector en memoria en 0000:7C00 (dirección lineal 0x7C00)
;   2. CPU salta aquí (en modo real 16-bit)
;   3. Inicializamos registros de segmento
;   4. Leemos N sectores del disco (dirección LBA 1, después del MBR actual)
;   5. Saltamos al programa cargado en 0000:8000
;   6. El programa tiene control de la máquina
;
; Modelo de Memoria (BIOS Legacy):
;   0x0000:0x1000  = Tabla de vectores de interrupción y BIOS data area
;   0x7C00:0x7E00  = Este bootloader (512 bytes)
;   0x8000:0x????  = Programa del juego (máx 17 sectores = ~8.5KB)
;   0xA0000        = Framebuffer VGA en modo 13h (320x200x256)
;
; Interrupciones BIOS usadas:
;   INT 0x13 (Disk services) : leer sectores del disco
;   INT 0x10 (Video services): salida de texto

[BITS 16]
[ORG 0x7C00]

; ---- Constantes de carga del juego ----
GAME_SEG   EQU 0x0000     ; Segmento donde cargar: 0x0000
GAME_OFF   EQU 0x8000     ; Offset dentro del segmento: juego en 0x8000
%ifndef GAME_SECTS
GAME_SECTS EQU 20         ; Número de sectores a leer (default 20, típicamente 3-6)
%endif

start:
    ; ---- Inicialización mínima de segmento y pila ----
    cli                         ; Deshabilitar interrupciones durante la inicialización
    xor  ax, ax                 ; AX = 0
    mov  ds, ax                 ; Segmento de datos = 0
    mov  es, ax                 ; Segmento extra = 0 (para operaciones de memoria)
    mov  ss, ax                 ; Segmento de pila = 0
    mov  sp, 0x7C00            ; Stack pointer = 0x7C00 (justo debajo del bootloader)
    mov  esp, 0x00007C00       ; Inicializar ESP (32-bit) por si acaso
    sti                         ; Re-habilitar interrupciones

    ; ---- Guardar el número de drive donde arrancamos ----
    ; La BIOS coloca el número de drive en DL antes de ejecutar este código
    mov  [boot_drive], dl       ; Guardar DL para usar en INT 0x13 después

    ; ---- Pantalla inicial ----
    ; Cambiamos a texto 80x25 para limpiar pantalla y mostrar bienvenida
    mov  ax, 0x0003
    int  0x10

    mov  si, msg_title1
    call print_str
    mov  si, msg_title2
    call print_str
    mov  si, msg_title3
    call print_str
    mov  si, msg_prompt
    call print_str

    ; Esperar ENTER para continuar; ESC cancela arranque
    call wait_enter
    jc   .halt

    mov  si, msg_loading
    call print_str

    ; ---- INTERRUPCION BIOS INT 0x13: Reset de controlador ----
    ; Mejora compatibilidad antes de leer caracteres.
    ; AH=0x00, DL=drive_number -> reset del drive
    xor  ax, ax                 ; AX = 0 (AH=0x00, AL=0x00)
    mov  dl, [boot_drive]       ; DL = número de drive guardado
    int  0x13                   ; Interrupción BIOS 0x13 (servicios de disco)

    ; ---- INTERRUPCION BIOS INT 0x13: Lectura de sectores ----
    ; Función 0x02 (Read Sectors): AH=0x02
    ;
    ; Parámetros de entrada:
    ;   AH = 0x02 (función Read)
    ;   AL = número de sectores a leer (GAME_SECTS)
    ;   CH = número de cilindro (bits 7:0)
    ;   CL = número de sector (bits 5:0) + cilindro (bits 9:8)
    ;   DH = cabeza (head)
    ;   DL = unidad de disco
    ;   ES:BX = dirección de destino en memoria
    ;
    ; Parámetros de salida:
    ;   CF (Carry Flag) = 0 si éxito, 1 si error
    ;   AH = código de error (si CF=1)
    ;   AL = número real de sectores leídos (si CF=0)
    ;
    ; Modelo de addressing:
    ;   Sector 1 = MBR (este programa)
    ;   Sector 2 = inicio del juego (GAME_SECTS)
    
    mov  ax, GAME_SEG           ; Segmento de destino
    mov  es, ax                 ; ES = 0x0000 (para alcanzar 0x0000:0x8000)
    mov  bx, GAME_OFF           ; BX = 0x8000 (offset = dirección física 0x8000)

    mov  ah, 0x02               ; AH = 0x02 (función Read Sectors)
    mov  al, GAME_SECTS         ; AL = número de sectores a leer
    mov  ch, 0                  ; CH = cilindro 0
    mov  cl, 2                  ; CL = sector 2 (después del MBR en sector 1)
    mov  dh, 0                  ; DH = cabeza 0
    mov  dl, [boot_drive]       ; DL = drive guardado
    int  0x13                   ; INTERRUPCION: leer del disco

    jnc  .loaded                ; Si CF=0 (éxito), saltar a .loaded

    ; ---- Si hay error en la lectura, reintentar una vez ----
    ; Si CF=1, intentamos de nuevo (reintento único)
    ; De todas formas preparamos línea de carga nuevamente
    xor  ax, ax                 ; Reset de drive nuevamente
    mov  dl, [boot_drive]
    int  0x13

    mov  ah, 0x02               ; Reintento: otra lectura
    mov  al, GAME_SECTS
    mov  ch, 0
    mov  cl, 2
    mov  dh, 0
    mov  dl, [boot_drive]
    int  0x13

    jc   .error                 ; Si CF=1 después del reintento, goto .error

.loaded:
    ; ---- Lectura exitosa: mostrar mensaje y saltar al juego ----
    ; El programa está ahora en memoria en 0000:8000
    mov  si, msg_welcome        ; SI = puntero a "Juego cargado..."
    call print_str              ; Mostrar mensaje

    ; Salto lejano al código del juego en 0x8000 (FAR JUMP)
    ; Formato: jmp segmento:offset
    jmp  GAME_SEG:GAME_OFF      ; Ejecutar el juego en 0x0000:0x8000

.error:
    ; ---- Error al leer el disco ----
    mov  si, msg_error          ; SI = puntero a "ERROR..."
    call print_str              ; Mostrar mensaje

.halt:
    ; ---- Bucle infinito ----
    cli                         ; Deshabilitar interrupciones
    hlt                         ; Detener el CPU
    jmp  .halt                  ; Por si acaso, loop infinito


; ============================================================
; Rutina: print_str
; ============================================================
; Propósito:
;   Imprime una cadena de caracteres en pantalla de forma simple.
;
; Entrada:
;   SI = puntero a cadena terminada en 0 (null-terminated)
;
; Implementación:
;   Usa INTERRUPCION BIOS INT 0x10 (Video Services)
;   Función 0x0E (Teletype output):
;   - AH = 0x0E
;   - AL = carácter ASCII a imprimir
;   - BX = página (página 0)
;   - Imprime el carácter y avanza el cursor automáticamente
;
; Modifica:
;   AX, BX (preserva otros registros con PUSH/POP)

print_str:
    push ax                     ; Guardar AX en pila
    push bx                     ; Guardar BX en pila
.loop:
    lodsb                       ; Cargar byte de [SI] en AL, incrementar SI
    or   al, al                 ; ¿es AL = 0? (test del byte cargado)
    jz   .done                  ; Si es 0 (fin de cadena), saltar a .done
    mov  ah, 0x0E               ; AH = 0x0E (función Teletype output)
    mov  bx, 0x0007             ; BX = 0x0007 (página 0, color blanco sobre fondo)
    int  0x10                   ; INTERRUPCION BIOS: imprimir carácter
    jmp  .loop                  ; Repetir para siguiente carácter
.done:
    pop  bx                     ; Restaurar BX
    pop  ax                     ; Restaurar AX
    ret                         ; Retornar

; ============================================================
; Rutina: wait_enter
; ============================================================
; Espera una tecla usando INT 16h:
;   ENTER -> CF=0 (continuar)
;   ESC   -> imprime cancelación y CF=1
wait_enter:
.loop:
    mov  ah, 0x00               ; BIOS keyboard: wait key
    int  0x16
    cmp  al, 0x0D               ; ENTER
    je   .ok
    cmp  al, 27                 ; ESC
    je   .cancel
    jmp  .loop

.ok:
    clc
    ret

.cancel:
    mov  si, msg_cancel
    call print_str
    stc
    ret

; ============================================================
; Sección de Datos
; ============================================================

boot_drive  db 0               ; Variable: número de drive (guardado de DL al inicio)

; Mensajes de texto (cadenas terminadas en 0)
msg_title1  db "==============================", 13, 10, 0
msg_title2  db " BOOTLOADER EN NASM", 13, 10, 0
msg_title3  db "==============================", 13, 10, 13, 10, 0
msg_prompt  db "ENTER: Iniciar juego", 13, 10, "ESC: Salir", 13, 10, 13, 10, 0
msg_loading db "Cargando juego...", 13, 10, 0
msg_cancel  db "Arranque cancelado.", 13, 10, 0
msg_error   db "ERROR al leer disco", 13, 10, 0 ; Mensaje si INT 0x13 falla
msg_welcome db "Juego cargado. Iniciando...", 13, 10, 0 ; Mensaje de éxito

; ---- Tabla de Particiones (MBR compatibility) ----
; Aunque usamos BIOS legacy (LBA), algunos BIOS requieren una tabla MBR válida.
; Rellenamos con 0s hasta el byte 446 (446 bytes de código + 64 bytes de tabla + 2 de firma)
times 446 - ($ - $$) db 0       ; $ = posición actual, $$ = inicio de sección

; ---- Entrada de Partición #1 (Bootable, FAT32 LBA) ----
; Estructura MBR (16 bytes):
;   BYTE 0: Estado (0x80=bootable, 0x00=no bootable)
;   BYTES 1-3: CHS inicio (Cilindro, Head, Sector)
;   BYTE 4: Tipo de partición (0x0C=FAT32 LBA)
;   BYTES 5-7: CHS fin
;   BYTES 8-11: LBA inicio (little-endian)
;   BYTES 12-15: Tamaño (little-endian)

db 0x80                 ; Bootable flag (0x80 = sí, es el drive de arranque)
db 0x00                 ; CHS head = 0 (LBA 1 → CHS 0,0,1 con 63 secs/track, 255 heads)
db 0x01                 ; CHS sector (bits 5:0 = 1) + cylinder altos (bits 7:6 = 0)
db 0x00                 ; CHS cylinder bajos = 0
db 0x0C                 ; Tipo de partición: 0x0C = FAT32 LBA
db 0xFE, 0xFF, 0xFF     ; CHS fin: head 254, sector 63, cylinder 1023 (máximos válidos)
dd 0x00000001           ; LBA inicio: sector 1 (después del MBR)
dd 0x0001FF00           ; Número de sectores (~128 MB para máxima compatibilidad)

; ---- Entradas 2, 3, 4 vacías (solo usamos partición 1) ----
times 16 * 3 db 0       ; 16 bytes × 3 = 48 bytes de particiones vacías

; ---- Firma MBR (BIOS verification) ----
; Toda entidad de boot legible por BIOS debe terminar con 0xAA55
dw 0xAA55               ; Firma de bootloader (little-endian)