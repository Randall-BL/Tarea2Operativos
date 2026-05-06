/*
 * juego.c
 * -------
 * Implementación del juego que se ejecuta como aplicación UEFI.
 *
 * Contiene:
 * - Definiciones de constantes de configuración y controles.
 * - Estructuras para framebuffer y estado del juego.
 * - Glyphs de 8x8 para dibujar caracteres simples en pantalla.
 * - Funciones auxiliares para entrada, pantalla, y lógica del juego.
 * - `game_run()` que es el punto de entrada llamado desde el bootloader.
 *
 * Diseñado para ejecutarse en un entorno freestanding UEFI usando GOP
 * (Graphics Output Protocol) y las rutinas de entrada estándar UEFI.
 */

#include <efi.h>
#include <efilib.h>

#include "juego.h"

/* Rotaciones posibles del texto/objeto en pantalla.
 * ROT_NORMAL: orientación estándar (0 grados)
 * ROT_LEFT:   rotación 90 grados a la izquierda
 * ROT_180:    rotación 180 grados
 * ROT_RIGHT:  rotación 90 grados a la derecha
 */
#define ROT_NORMAL 0
#define ROT_LEFT   1
#define ROT_180    2
#define ROT_RIGHT  3

/* Constantes de renderizado y temporización */
#define SCALE 4                /* Escala multiplicadora para cada píxel del glyph */
#define CHAR_SIZE (8 * SCALE)  /* Altura/anchura (en px) de un carácter escalado */
#define CHAR_ADV  (9 * SCALE)  /* Espacio ocupado (advance) entre caracteres */
#define MOVE_SPEED 6           /* Velocidad (px por frame) al mover */
#define FRAME_US 16000         /* Microsegundos a esperar por frame (~62.5 FPS) */
#define HOLD_TIMEOUT_FRAMES 24 /* Número de frames para considerar una tecla "mantener" */

/* Identificadores para teclas de movimiento mantenidas por el jugador */
#define MOVE_KEY_NONE  0
#define MOVE_KEY_UP    1
#define MOVE_KEY_DOWN  2
#define MOVE_KEY_LEFT  3
#define MOVE_KEY_RIGHT 4

/* Representa la superficie de dibujo proporcionada por GOP. */
typedef struct {
    UINT32 width;   /* Anchura en píxeles */
    UINT32 height;  /* Altura en píxeles */
    UINT32 ppsl;    /* Pixels per scan line (stride) del framebuffer */
    UINT32 *fb;     /* Puntero al buffer de frame (FB con formato ARGB o similar) */
} Framebuffer;

/* Estado del juego: posición del objeto, rotación y semilla RNG */
typedef struct {
    INT32 x;         /* Coordenada X superior-izquierda del objeto/render */
    INT32 y;         /* Coordenada Y superior-izquierda del objeto/render */
    UINT8 rotation;  /* Una de las ROT_* */
    UINT32 seed;     /* Semilla para generador pseudoaleatorio (LCG) */
} GameState;

/* Textos que se mostrarán en pantalla: dos nombres */
static const CHAR8 NAME1[] = "RANDALL";
static const CHAR8 NAME2[] = "CHRIS";

/*
 * Glyphs de 8x8 para las letras usadas.
 * Cada byte representa una fila de 8 bits; el bit más significativo
 * corresponde al píxel más a la izquierda en la fila.
 * Se usan para renderizar texto escalado y rotado manualmente.
 */
static const UINT8 GLYPH_A[8] = {0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00};
static const UINT8 GLYPH_C[8] = {0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00};
static const UINT8 GLYPH_D[8] = {0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0x00};
static const UINT8 GLYPH_H[8] = {0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00};
static const UINT8 GLYPH_I[8] = {0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00};
static const UINT8 GLYPH_L[8] = {0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00};
static const UINT8 GLYPH_N[8] = {0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00};
static const UINT8 GLYPH_R[8] = {0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00};
static const UINT8 GLYPH_S[8] = {0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00};
static const UINT8 GLYPH_SPACE[8] = {0, 0, 0, 0, 0, 0, 0, 0};

/* Devuelve un puntero al glyph correspondiente al carácter `ch`.
 * Si no hay glyph definido, devuelve el glyph de espacio.
 */
static const UINT8 *glyph_for_char(CHAR8 ch) {
    switch (ch) {
        case 'A': return GLYPH_A;
        case 'C': return GLYPH_C;
        case 'D': return GLYPH_D;
        case 'H': return GLYPH_H;
        case 'I': return GLYPH_I;
        case 'L': return GLYPH_L;
        case 'N': return GLYPH_N;
        case 'R': return GLYPH_R;
        case 'S': return GLYPH_S;
        case ' ': return GLYPH_SPACE;
        default: return GLYPH_SPACE;
    }
}

/* Calcula la longitud de una cadena de `CHAR8` (ASCII), equivalente a strlen.
 * Se usa strings cortas y predecibles; devuelve UINTN.
 */
static UINTN str_len8(const CHAR8 *s) {
    UINTN len = 0;
    while (s[len] != '\0') {
        ++len;
    }
    return len;
}

/* EVENTO UEFI (teclado, no bloqueante):
 * Intenta consumir una tecla pendiente con `ReadKeyStroke`.
 * Si no hay tecla en cola, devuelve FALSE.
 */
static BOOLEAN poll_key(EFI_SYSTEM_TABLE *st, EFI_INPUT_KEY *key) {
    EFI_STATUS status = uefi_call_wrapper(st->ConIn->ReadKeyStroke, 2, st->ConIn, key);
    return (BOOLEAN)(!EFI_ERROR(status));
}

/* EVENTO UEFI (teclado, bloqueante):
 * Espera señal en `ConIn->WaitForKey` usando `WaitForEvent`
 * y luego obtiene la tecla con `ReadKeyStroke`.
 */
static EFI_STATUS wait_key(EFI_SYSTEM_TABLE *st, EFI_INPUT_KEY *key) {
    EFI_STATUS status;
    UINTN index;

    status = uefi_call_wrapper(st->BootServices->WaitForEvent, 3,
                               1, &st->ConIn->WaitForKey, &index);
    if (EFI_ERROR(status)) {
        return status;
    }

    return uefi_call_wrapper(st->ConIn->ReadKeyStroke, 2, st->ConIn, key);
}

/* Generador congruencial lineal simple (LCG) para pseudoaleatoriedad.
 * Actualiza la semilla y devuelve el nuevo valor.
 */
static UINT32 lcg_next(UINT32 *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;
    return *seed;
}

/* Muestra instrucciones y espera a que el usuario pulse ENTER para iniciar
 * o ESC para cancelar. Devuelve EFI_SUCCESS si se aceptó, EFI_ABORTED si
 * el usuario canceló y otro código de error si falló la lectura de teclado.
 */
static EFI_STATUS confirm_start(EFI_SYSTEM_TABLE *SystemTable) {
    EFI_INPUT_KEY key;
    EFI_STATUS status;

    uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
    Print(L"=========================================\r\n");
    Print(L" JUEGO: CHRIS Y RANDALL Version UEFI/C\r\n");
    Print(L"=========================================\r\n\r\n");
    Print(L"Controles:\r\n");
    Print(L"  Flecha Izq  : Rotar 90 a la izquierda\r\n");
    Print(L"  Flecha Der  : Rotar 90 a la derecha\r\n");
    Print(L"  Flecha Arr  : Rotar 180\r\n");
    Print(L"  Flecha Abj  : Rotar 180\r\n");
    Print(L"  W           : Mover arriba\r\n");
    Print(L"  S           : Mover abajo\r\n");
    Print(L"  A           : Mover izquierda\r\n");
    Print(L"  D           : Mover derecha\r\n");
    Print(L"  R           : Reiniciar posicion random\r\n");
    Print(L"  ESC         : Salir del juego\r\n\r\n");
    Print(L"Presiona ENTER para comenzar o ESC para cancelar...\r\n");

    while (1) {
        status = wait_key(SystemTable, &key);
        if (EFI_ERROR(status)) {
            return status;
        }

        if (key.UnicodeChar == CHAR_CARRIAGE_RETURN) {
            return EFI_SUCCESS;
        }

        if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
            return EFI_ABORTED;
        }
    }
}

/* Inicializa la estructura Framebuffer a partir del GOP encontrado.
 * Extrae resolución, stride y puntero al framebuffer físico.
 */
static void fb_init(Framebuffer *fb, EFI_GRAPHICS_OUTPUT_PROTOCOL *gop) {
    fb->width = gop->Mode->Info->HorizontalResolution;
    fb->height = gop->Mode->Info->VerticalResolution;
    fb->ppsl = gop->Mode->Info->PixelsPerScanLine;
    fb->fb = (UINT32 *)(UINTN)gop->Mode->FrameBufferBase;
}

/* Escribe un píxel en la posición (x,y) si está dentro de los límites.
 * `color` se interpreta según el formato del framebuffer (habitualmente BGR/ARGB).
 */
static void put_pixel(const Framebuffer *fb, INT32 x, INT32 y, UINT32 color) {
    if (x < 0 || y < 0) {
        return;
    }

    if ((UINT32)x >= fb->width || (UINT32)y >= fb->height) {
        return;
    }

    fb->fb[(UINTN)y * fb->ppsl + (UINTN)x] = color;
}

/* Rellena toda la pantalla con un color. Operación O(width*height). */
static void fill_screen(const Framebuffer *fb, UINT32 color) {
    for (UINT32 y = 0; y < fb->height; ++y) {
        for (UINT32 x = 0; x < fb->width; ++x) {
            fb->fb[(UINTN)y * fb->ppsl + x] = color;
        }
    }
}

/* Dibuja un glyph 8x8 escalado y rotado en la posición base_x, base_y.
 * - `glyph` es una tabla de 8 bytes (cada byte una fila).
 * - `rotation` determina cómo rotar los bits antes de escalar.
 * - Se aplica `SCALE` para dibujar un bloque por cada bit activo.
 */
static void draw_glyph_rotated(const Framebuffer *fb,
                               INT32 base_x,
                               INT32 base_y,
                               const UINT8 glyph[8],
                               UINT8 rotation,
                               UINT32 color) {
    for (INT32 row = 0; row < 8; ++row) {
        UINT8 bits = glyph[row];
        for (INT32 col = 0; col < 8; ++col) {
            if (((bits >> (7 - col)) & 1u) == 0u) {
                continue;
            }

            INT32 px = col;
            INT32 py = row;

            if (rotation == ROT_LEFT) {
                px = row;
                py = 7 - col;
            } else if (rotation == ROT_RIGHT) {
                px = 7 - row;
                py = col;
            } else if (rotation == ROT_180) {
                px = 7 - col;
                py = 7 - row;
            }

            INT32 draw_x = base_x + px * SCALE;
            INT32 draw_y = base_y + py * SCALE;

            for (INT32 dy = 0; dy < SCALE; ++dy) {
                for (INT32 dx = 0; dx < SCALE; ++dx) {
                    put_pixel(fb, draw_x + dx, draw_y + dy, color);
                }
            }
        }
    }
}

/* Dibuja una cadena `text` aplicada la rotación especificada.
 * El texto puede dibujarse horizontalmente (ROT_NORMAL/ROT_180)
 * o verticalmente (ROT_LEFT/ROT_RIGHT) usando `CHAR_ADV` como avance.
 */
static void draw_string_rotated(const Framebuffer *fb,
                                INT32 x,
                                INT32 y,
                                const CHAR8 *text,
                                UINT8 rotation,
                                UINT32 color) {
    UINTN len = str_len8(text);

    for (UINTN i = 0; i < len; ++i) {
        UINTN idx = i;
        if (rotation == ROT_180) {
            idx = len - 1 - i;
        }

        const UINT8 *glyph = glyph_for_char(text[idx]);
        INT32 gx = x;
        INT32 gy = y;

        if (rotation == ROT_NORMAL || rotation == ROT_180) {
            gx = x + (INT32)i * CHAR_ADV;
        } else {
            gy = y + (INT32)i * CHAR_ADV;
        }

        draw_glyph_rotated(fb, gx, gy, glyph, rotation, color);
    }
}

/* Calcula el rectángulo en píxeles ocupado por las dos cadenas (NAME1, NAME2)
 * dependiendo de la rotación. Devuelve anchura y altura en `out_w/out_h`.
 */
static void calc_bounds(UINT8 rotation, UINTN len1, UINTN len2, INT32 *out_w, INT32 *out_h) {
    INT32 gap = CHAR_SIZE / 2;
    INT32 max_len = (len1 > len2) ? (INT32)len1 : (INT32)len2;

    if (rotation == ROT_NORMAL || rotation == ROT_180) {
        *out_w = max_len * CHAR_ADV;
        *out_h = (CHAR_SIZE * 2) + gap;
    } else {
        *out_w = (CHAR_SIZE * 2) + gap;
        *out_h = max_len * CHAR_ADV;
    }
}

/* Coloca el objeto en una posición pseudoaleatoria válida dentro de la pantalla
 * utilizando la semilla del estado y asegurando que el objeto no salga
 * fuera de los límites (se ajusta si la resolución es menor que el objeto).
 */
static void randomize_position(GameState *state, const Framebuffer *fb) {
    INT32 obj_w;
    INT32 obj_h;
    INT32 max_x;
    INT32 max_y;

    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    max_x = (INT32)fb->width - obj_w;
    max_y = (INT32)fb->height - obj_h;

    if (max_x < 0) {
        max_x = 0;
    }
    if (max_y < 0) {
        max_y = 0;
    }

    state->x = (INT32)(lcg_next(&state->seed) % (UINT32)(max_x + 1));
    state->y = (INT32)(lcg_next(&state->seed) % (UINT32)(max_y + 1));
}

/* Mueve el objeto según el vector (vx,vy) y rebota en los bordes.
 * Si la nueva posición sale fuera, se clampa y se invierte el componente
 * de velocidad correspondiente (efecto rebote).
 */
static void move_with_bounce(GameState *state, const Framebuffer *fb, INT32 *vx, INT32 *vy) {
    INT32 obj_w;
    INT32 obj_h;
    INT32 max_x;
    INT32 max_y;
    INT32 nx;
    INT32 ny;

    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    max_x = (INT32)fb->width - obj_w;
    max_y = (INT32)fb->height - obj_h;

    if (max_x < 0) {
        max_x = 0;
    }
    if (max_y < 0) {
        max_y = 0;
    }

    nx = state->x + *vx;
    ny = state->y + *vy;

    if (nx < 0) {
        nx = 0;
        *vx = (*vx < 0) ? -*vx : *vx;
    } else if (nx > max_x) {
        nx = max_x;
        *vx = (*vx > 0) ? -*vx : *vx;
    }

    if (ny < 0) {
        ny = 0;
        *vy = (*vy < 0) ? -*vy : *vy;
    } else if (ny > max_y) {
        ny = max_y;
        *vy = (*vy > 0) ? -*vy : *vy;
    }

    state->x = nx;
    state->y = ny;
}

/* Limpia (rellena de `color`) el rectángulo [x,x+w) x [y,y+h) con clipping.
 * Usado para borrar la región anterior del objeto antes de redibujar.
 */
static void clear_rect(const Framebuffer *fb, INT32 x, INT32 y, INT32 w, INT32 h, UINT32 color) {
    INT32 yy;
    INT32 xx;
    INT32 x0 = x;
    INT32 y0 = y;
    INT32 x1 = x + w;
    INT32 y1 = y + h;

    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > (INT32)fb->width) x1 = (INT32)fb->width;
    if (y1 > (INT32)fb->height) y1 = (INT32)fb->height;

    for (yy = y0; yy < y1; ++yy) {
        for (xx = x0; xx < x1; ++xx) {
            put_pixel(fb, xx, yy, color);
        }
    }
}

/* Dibuja únicamente los dos nombres (NAME1, NAME2) usando colores
 * fijos (amarillo y magenta). La disposición depende de la rotación.
 */
static void draw_names_only(const Framebuffer *fb, const GameState *state) {
    const UINT32 yellow = 0x0000FFFF;
    const UINT32 magenta = 0x00FF00FF;
    INT32 gap = CHAR_SIZE / 2;

    if (state->rotation == ROT_NORMAL || state->rotation == ROT_180) {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, yellow);
        draw_string_rotated(fb, state->x, state->y + CHAR_SIZE + gap, NAME2, state->rotation, magenta);
    } else {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, yellow);
        draw_string_rotated(fb, state->x + CHAR_SIZE + gap, state->y, NAME2, state->rotation, magenta);
    }
}

/* Construye una semilla pseudoaleatoria mezclando:
 * - dimensiones de pantalla
 * - tiempo (si está disponible vía RuntimeServices->GetTime)
 * - la dirección del framebuffer
 *
 * Se aplica una mezcla adicional tipo xorshift para mejorar distribución.
 * Si el resultado es 0, se fuerza a 1 (evitar semilla cero en LCG).
 */
static UINT32 make_seed(EFI_SYSTEM_TABLE *SystemTable, const Framebuffer *fb) {
    UINT32 seed = 0xA5A5A5A5u ^ fb->width ^ (fb->height << 16);
    EFI_TIME now;
    EFI_STATUS status;

    status = uefi_call_wrapper(SystemTable->RuntimeServices->GetTime, 2, &now, NULL);
    if (!EFI_ERROR(status)) {
        seed ^= now.Nanosecond;
        seed ^= ((UINT32)now.Second << 24);
        seed ^= ((UINT32)now.Minute << 16);
        seed ^= ((UINT32)now.Hour << 8);
        seed ^= ((UINT32)now.Day << 20);
        seed ^= ((UINT32)now.Month << 12);
        seed ^= (UINT32)now.Year;
    }

    seed ^= (UINT32)(UINTN)fb->fb;

    seed ^= (seed << 13);
    seed ^= (seed >> 17);
    seed ^= (seed << 5);

    if (seed == 0) {
        seed = 1;
    }

    return seed;
}

EFI_STATUS game_run(EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_INPUT_KEY key;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;
    EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    EFI_EVENT events[2];
    UINTN event_index = 0;
    BOOLEAN timer_created = FALSE;
    const UINT64 frame_tick_100ns = (UINT64)FRAME_US * 10ULL;
    Framebuffer fb;
    GameState state;
    UINT32 frame = 0;
    UINT32 last_move_input_frame = 0;
    UINT8 active_move_key = MOVE_KEY_NONE;
    INT32 vx = 0;
    INT32 vy = 0;
    INT32 prev_x = 0;
    INT32 prev_y = 0;
    UINT8 prev_rotation = 0xFF;

    status = confirm_start(SystemTable);
    if (status == EFI_ABORTED) {
        return EFI_SUCCESS;
    }
    if (EFI_ERROR(status)) {
        return status;
    }

    status = uefi_call_wrapper(SystemTable->BootServices->LocateProtocol, 3,
                               &gop_guid, NULL, (void **)&gop);
    if (EFI_ERROR(status) || gop == NULL) {
        uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
        Print(L"No se pudo iniciar GOP. Presiona una tecla...\r\n");
        wait_key(SystemTable, &key);
        return EFI_SUCCESS;
    }

    fb_init(&fb, gop);

    state.rotation = ROT_NORMAL;
    state.seed = make_seed(SystemTable, &fb);
    randomize_position(&state, &fb);

    /* Limpiamos una sola vez y luego usamos redibujado parcial para mejorar FPS. */
    fill_screen(&fb, 0x00000000);

    prev_x = state.x;
    prev_y = state.y;

    /* INTERRUPCIONES/EVENTOS (UEFI):
     * - `events[0]` apunta al evento de teclado proporcionado por `ConIn->WaitForKey`.
     * - `events[1]` se crea como un evento timer periódico mediante
     *     CreateEvent(EVT_TIMER) + SetTimer(TimerPeriodic).
     * - Ambos eventos se esperan con `WaitForEvent(2, events, &event_index)`.
     *
     * Nota: en UEFI no hay `int 0x10/0x16` — el firmware provee eventos/timers
     * que son el equivalente para manejar entrada y temporización.
     */
    events[0] = SystemTable->ConIn->WaitForKey;
    events[1] = NULL;

    status = uefi_call_wrapper(SystemTable->BootServices->CreateEvent, 5,
                               EVT_TIMER, TPL_CALLBACK, NULL, NULL, &events[1]);
    if (EFI_ERROR(status)) {
        return status;
    }
    timer_created = TRUE;

    status = uefi_call_wrapper(SystemTable->BootServices->SetTimer, 3,
                               events[1], TimerPeriodic, frame_tick_100ns);
    if (EFI_ERROR(status)) {
        goto cleanup;
    }

    while (1) {
        BOOLEAN needs_redraw = FALSE;

        /* EVENTO UEFI central: el bucle duerme hasta que llegue teclado
         * o el tick periódico del timer de frame.
         */
        status = uefi_call_wrapper(SystemTable->BootServices->WaitForEvent, 3,
                                   2, events, &event_index);
        if (EFI_ERROR(status)) {
            goto cleanup;
        }

        if (event_index == 0) {
            /* Si despertó por teclado, vaciamos cola de teclas pendientes. */
            while (poll_key(SystemTable, &key)) {
                if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
                    status = EFI_SUCCESS;
                    goto cleanup;
                }

                if (key.ScanCode == SCAN_LEFT) {
                    state.rotation = (UINT8)((state.rotation + 3u) & 3u);
                    continue;
                }

                if (key.ScanCode == SCAN_RIGHT) {
                    state.rotation = (UINT8)((state.rotation + 1u) & 3u);
                    continue;
                }

                if (key.ScanCode == SCAN_UP || key.ScanCode == SCAN_DOWN) {
                    state.rotation = (UINT8)(state.rotation ^ 2u);
                    continue;
                }

                if (key.UnicodeChar == 'r' || key.UnicodeChar == 'R') {
                    state.rotation = ROT_NORMAL;
                    state.seed = make_seed(SystemTable, &fb);
                    randomize_position(&state, &fb);
                    continue;
                }

                if (key.UnicodeChar == 'w' || key.UnicodeChar == 'W') {
                    if (!(active_move_key == MOVE_KEY_UP && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                        active_move_key = MOVE_KEY_UP;
                        vx = 0;
                        vy = -MOVE_SPEED;
                    }
                    last_move_input_frame = frame;
                    continue;
                }

                if (key.UnicodeChar == 's' || key.UnicodeChar == 'S') {
                    if (!(active_move_key == MOVE_KEY_DOWN && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                        active_move_key = MOVE_KEY_DOWN;
                        vx = 0;
                        vy = MOVE_SPEED;
                    }
                    last_move_input_frame = frame;
                    continue;
                }

                if (key.UnicodeChar == 'a' || key.UnicodeChar == 'A') {
                    if (!(active_move_key == MOVE_KEY_LEFT && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                        active_move_key = MOVE_KEY_LEFT;
                        vx = -MOVE_SPEED;
                        vy = 0;
                    }
                    last_move_input_frame = frame;
                    continue;
                }

                if (key.UnicodeChar == 'd' || key.UnicodeChar == 'D') {
                    if (!(active_move_key == MOVE_KEY_RIGHT && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                        active_move_key = MOVE_KEY_RIGHT;
                        vx = MOVE_SPEED;
                        vy = 0;
                    }
                    last_move_input_frame = frame;
                    continue;
                }
            }
            continue;
        }

        /* Si despertó por timer, avanzamos un frame de simulación/render. */
        ++frame;

        if (active_move_key != MOVE_KEY_NONE) {
            if ((frame - last_move_input_frame) > HOLD_TIMEOUT_FRAMES) {
                active_move_key = MOVE_KEY_NONE;
                vx = 0;
                vy = 0;
            } else {
                move_with_bounce(&state, &fb, &vx, &vy);
            }
        }

        if (state.x != prev_x || state.y != prev_y || state.rotation != prev_rotation) {
            needs_redraw = TRUE;
        }

        if (needs_redraw) {
            if (prev_rotation != 0xFF) {
                INT32 old_w;
                INT32 old_h;
                calc_bounds(prev_rotation, str_len8(NAME1), str_len8(NAME2), &old_w, &old_h);
                clear_rect(&fb, prev_x, prev_y, old_w, old_h, 0);
            }

            draw_names_only(&fb, &state);
            prev_x = state.x;
            prev_y = state.y;
            prev_rotation = state.rotation;
        }

    }

cleanup:
    if (timer_created) {
        uefi_call_wrapper(SystemTable->BootServices->CloseEvent, 1, events[1]);
    }
    return status;
}
