/* juego.c (UEFI ARM64)
 * ------------------------------------------------------------
 * Versión del juego para entorno UEFI AArch64 (sin BIOS legacy).
 *
 * Aquí NO existen interrupciones BIOS tipo `INT 0x10/0x16`.
 * El equivalente en UEFI es el modelo de eventos del firmware:
 * - Evento de teclado: `ConIn->WaitForKey` + `ReadKeyStroke`
 * - Evento de timer: `CreateEvent(EVT_TIMER)` + `SetTimer(TimerPeriodic)`
 * - Multiplexado: `WaitForEvent(...)`
 *
 * Busca comentarios con "EVENTO UEFI" en funciones clave.
 */

#include "efi_min.h"

#define ROT_NORMAL 0
#define ROT_LEFT   1
#define ROT_180    2
#define ROT_RIGHT  3

#define MOVE_KEY_NONE  0
#define MOVE_KEY_UP    1
#define MOVE_KEY_DOWN  2
#define MOVE_KEY_LEFT  3
#define MOVE_KEY_RIGHT 4

#define SCALE 4
#define CHAR_SIZE (8 * SCALE)
#define CHAR_ADV  (9 * SCALE)
#define MOVE_SPEED 6
#define FRAME_US 16000
#define HOLD_TIMEOUT_FRAMES 24

#define COL_BG 0
#define COL_T1 11
#define COL_T2 13

typedef struct {
    UINT32 width;
    UINT32 height;
    UINT32 ppsl;
    UINT32 pixel_format;
    UINT32 *fb;
} Framebuffer;

typedef struct {
    INT32 x;
    INT32 y;
    UINT8 rotation;
    UINT32 seed;
} GameState;

static const CHAR8 NAME1[] = {'R','A','N','D','A','L','L',0};
static const CHAR8 NAME2[] = {'C','H','R','I','S',0};

static CHAR16 MSG_TITLE1[] = L"=========================================\r\n";
static CHAR16 MSG_TITLE2[] = L" JUEGO: CHRIS Y RANDALL VersionARM\r\n";
static CHAR16 MSG_TITLE3[] = L"=========================================\r\n\r\n";
static CHAR16 MSG_C1[] = L"Controles:\r\n";
static CHAR16 MSG_C2[] = L"  Flecha Izq  : Rotar 90 a la izquierda\r\n";
static CHAR16 MSG_C3[] = L"  Flecha Der  : Rotar 90 a la derecha\r\n";
static CHAR16 MSG_C4[] = L"  Flecha Arr  : Rotar 180\r\n";
static CHAR16 MSG_C5[] = L"  Flecha Abj  : Rotar 180\r\n";
static CHAR16 MSG_C6[] = L"  W           : Mover arriba\r\n";
static CHAR16 MSG_C7[] = L"  S           : Mover abajo\r\n";
static CHAR16 MSG_C8[] = L"  A           : Mover izquierda\r\n";
static CHAR16 MSG_C9[] = L"  D           : Mover derecha\r\n";
static CHAR16 MSG_C10[] = L"  R           : Reiniciar posicion random\r\n";
static CHAR16 MSG_C11[] = L"  ESC         : Salir del juego\r\n\r\n";
static CHAR16 MSG_C12[] = L"ENTER para comenzar o ESC para cancelar...\r\n";
static CHAR16 MSG_GOP[] = L"No se pudo iniciar GOP. Presiona una tecla...\r\n";

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

/* Borra pantalla de texto usando servicio de consola UEFI. */
static void text_clear(EFI_SYSTEM_TABLE *st) {
    st->ConOut->ClearScreen(st->ConOut);
}

/* Imprime cadena UTF-16 en consola UEFI. */
static void text_print(EFI_SYSTEM_TABLE *st, CHAR16 *msg) {
    st->ConOut->OutputString(st->ConOut, msg);
}

/* EVENTO UEFI (teclado): espera bloqueante.
 * - Espera señal de `ConIn->WaitForKey` con `WaitForEvent`
 * - Luego consume la tecla con `ReadKeyStroke`
 */
static EFI_STATUS wait_key(EFI_SYSTEM_TABLE *st, EFI_INPUT_KEY *key) {
    EFI_STATUS status;
    EFI_EVENT ev;
    UINTN index;

    ev = st->ConIn->WaitForKey;
    status = st->BootServices->WaitForEvent(1, &ev, &index);
    if (EFI_ERROR(status)) {
        return status;
    }
    return st->ConIn->ReadKeyStroke(st->ConIn, key);
}

/* EVENTO UEFI (teclado): lectura no bloqueante.
 * Si no hay tecla, `ReadKeyStroke` devuelve error/not-ready.
 */
static BOOLEAN poll_key(EFI_SYSTEM_TABLE *st, EFI_INPUT_KEY *key) {
    EFI_STATUS status = st->ConIn->ReadKeyStroke(st->ConIn, key);
    return (BOOLEAN)(status == EFI_SUCCESS);
}

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

static UINTN str_len8(const CHAR8 *s) {
    UINTN len = 0;
    while (s[len] != 0) {
        ++len;
    }
    return len;
}

static EFI_STATUS confirm_start(EFI_SYSTEM_TABLE *st) {
    EFI_INPUT_KEY key;
    EFI_STATUS status;

    text_clear(st);
    text_print(st, MSG_TITLE1);
    text_print(st, MSG_TITLE2);
    text_print(st, MSG_TITLE3);
    text_print(st, MSG_C1);
    text_print(st, MSG_C2);
    text_print(st, MSG_C3);
    text_print(st, MSG_C4);
    text_print(st, MSG_C5);
    text_print(st, MSG_C6);
    text_print(st, MSG_C7);
    text_print(st, MSG_C8);
    text_print(st, MSG_C9);
    text_print(st, MSG_C10);
    text_print(st, MSG_C11);
    text_print(st, MSG_C12);

    for (;;) {
        status = wait_key(st, &key);
        if (EFI_ERROR(status)) {
            return status;
        }
        if (key.UnicodeChar == 13) {
            return EFI_SUCCESS;
        }
        if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
            return EFI_ABORTED;
        }
    }
}

static EFI_STATUS fb_init(EFI_SYSTEM_TABLE *st, Framebuffer *fb) {
    EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = (EFI_GRAPHICS_OUTPUT_PROTOCOL *)0;
    EFI_STATUS status;

    status = st->BootServices->LocateProtocol(&gop_guid, 0, (VOID **)&gop);
    if (EFI_ERROR(status) || !gop || !gop->Mode || !gop->Mode->Info) {
        return EFI_ABORTED;
    }

    fb->width = gop->Mode->Info->HorizontalResolution;
    fb->height = gop->Mode->Info->VerticalResolution;
    fb->ppsl = gop->Mode->Info->PixelsPerScanLine;
    fb->pixel_format = gop->Mode->Info->PixelFormat;
    fb->fb = (UINT32 *)(UINTN)gop->Mode->FrameBufferBase;
    return EFI_SUCCESS;
}

static UINT32 color_to_pixel(const Framebuffer *fb, UINT32 idx) {
    static const UINT8 table[3 * 3] = {
        0, 0, 0,
        0, 255, 255,
        255, 0, 255
    };
    UINT32 base;
    UINT32 r;
    UINT32 g;
    UINT32 b;

    if (idx > 2) {
        idx = 0;
    }

    base = idx * 3;
    r = table[base + 0];
    g = table[base + 1];
    b = table[base + 2];

    if (fb->pixel_format == 0) {
        return r | (g << 8) | (b << 16);
    }
    return b | (g << 8) | (r << 16);
}

static void put_pixel(const Framebuffer *fb, INT32 x, INT32 y, UINT32 color_idx) {
    if (x < 0 || y < 0) {
        return;
    }
    if ((UINT32)x >= fb->width || (UINT32)y >= fb->height) {
        return;
    }
    fb->fb[(UINTN)y * fb->ppsl + (UINTN)x] = color_to_pixel(fb, color_idx);
}

static void fill_screen(const Framebuffer *fb, UINT32 color_idx) {
    UINT32 pixel = color_to_pixel(fb, color_idx);
    UINTN total = (UINTN)fb->ppsl * (UINTN)fb->height;
    UINTN i;
    for (i = 0; i < total; ++i) {
        fb->fb[i] = pixel;
    }
}

static void draw_glyph_rotated(const Framebuffer *fb, INT32 base_x, INT32 base_y, const UINT8 glyph[8], UINT8 rotation, UINT32 color) {
    INT32 row;
    INT32 col;

    for (row = 0; row < 8; ++row) {
        UINT8 bits = glyph[row];
        for (col = 0; col < 8; ++col) {
            INT32 px = col;
            INT32 py = row;
            INT32 draw_x;
            INT32 draw_y;
            INT32 dy;
            INT32 dx;

            if (((bits >> (7 - col)) & 1u) == 0u) {
                continue;
            }

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

            draw_x = base_x + px * SCALE;
            draw_y = base_y + py * SCALE;

            for (dy = 0; dy < SCALE; ++dy) {
                for (dx = 0; dx < SCALE; ++dx) {
                    put_pixel(fb, draw_x + dx, draw_y + dy, color);
                }
            }
        }
    }
}

static void draw_string_rotated(const Framebuffer *fb, INT32 x, INT32 y, const CHAR8 *text, UINT8 rotation, UINT32 color) {
    UINTN len = str_len8(text);
    UINTN i;

    for (i = 0; i < len; ++i) {
        UINTN idx = i;
        INT32 gx = x;
        INT32 gy = y;
        const UINT8 *glyph;

        if (rotation == ROT_180) {
            idx = len - 1 - i;
        }

        glyph = glyph_for_char(text[idx]);

        if (rotation == ROT_NORMAL || rotation == ROT_180) {
            gx = x + (INT32)i * CHAR_ADV;
        } else {
            gy = y + (INT32)i * CHAR_ADV;
        }

        draw_glyph_rotated(fb, gx, gy, glyph, rotation, color);
    }
}

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

static UINT32 lcg_next(UINT32 *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;
    return *seed;
}

static UINT32 make_seed(EFI_SYSTEM_TABLE *st, const Framebuffer *fb) {
    UINT32 seed = 0xA5A5A5A5u ^ fb->width ^ (fb->height << 16);
    EFI_TIME now;
    EFI_STATUS status;

    status = st->RuntimeServices->GetTime(&now, 0);
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

static void randomize_position(GameState *state, const Framebuffer *fb) {
    INT32 obj_w;
    INT32 obj_h;
    INT32 max_x;
    INT32 max_y;

    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);
    max_x = (INT32)fb->width - obj_w;
    max_y = (INT32)fb->height - obj_h;

    if (max_x < 0) max_x = 0;
    if (max_y < 0) max_y = 0;

    state->x = (INT32)(lcg_next(&state->seed) % (UINT32)(max_x + 1));
    state->y = (INT32)(lcg_next(&state->seed) % (UINT32)(max_y + 1));
}

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

    if (max_x < 0) max_x = 0;
    if (max_y < 0) max_y = 0;

    nx = state->x + *vx;
    ny = state->y + *vy;

    if (nx < 0) {
        nx = 0;
        if (*vx < 0) *vx = -*vx;
    } else if (nx > max_x) {
        nx = max_x;
        if (*vx > 0) *vx = -*vx;
    }

    if (ny < 0) {
        ny = 0;
        if (*vy < 0) *vy = -*vy;
    } else if (ny > max_y) {
        ny = max_y;
        if (*vy > 0) *vy = -*vy;
    }

    state->x = nx;
    state->y = ny;
}

static void clear_rect(const Framebuffer *fb, INT32 x, INT32 y, INT32 w, INT32 h, UINT32 color_idx) {
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
            put_pixel(fb, xx, yy, color_idx);
        }
    }
}

static void draw_names_only(const Framebuffer *fb, const GameState *state) {
    INT32 gap = CHAR_SIZE / 2;

    if (state->rotation == ROT_NORMAL || state->rotation == ROT_180) {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, 1);
        draw_string_rotated(fb, state->x, state->y + CHAR_SIZE + gap, NAME2, state->rotation, 2);
    } else {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, 1);
        draw_string_rotated(fb, state->x + CHAR_SIZE + gap, state->y, NAME2, state->rotation, 2);
    }
}

EFI_STATUS efi_main_c(EFI_HANDLE image, EFI_SYSTEM_TABLE *st) {
    Framebuffer fb;
    GameState state;
    EFI_INPUT_KEY key;
    EFI_STATUS status;
    EFI_EVENT events[2];
    UINTN event_index = 0;
    BOOLEAN timer_created = 0;
    UINT64 frame_tick_100ns = (UINT64)FRAME_US * 10ULL;
    UINT32 frame = 0;
    UINT32 last_move_input_frame = 0;
    UINT8 active_move_key = MOVE_KEY_NONE;
    INT32 vx = 0;
    INT32 vy = 0;
    INT32 prev_x = 0;
    INT32 prev_y = 0;
    UINT8 prev_rotation = 0xFF;
    (void)image;

    status = confirm_start(st);
    if (status == EFI_ABORTED) {
        return EFI_SUCCESS;
    }
    if (EFI_ERROR(status)) {
        return status;
    }

    status = fb_init(st, &fb);
    if (EFI_ERROR(status)) {
        text_clear(st);
        text_print(st, MSG_GOP);
        wait_key(st, &key);
        return EFI_SUCCESS;
    }

    state.rotation = ROT_NORMAL;
    state.seed = make_seed(st, &fb);
    randomize_position(&state, &fb);

    fill_screen(&fb, COL_BG);
    prev_x = state.x;
    prev_y = state.y;

    /* INTERRUPCIONES/EVENTOS (UEFI AArch64):
     * - `events[0]` es el evento de teclado: `ConIn->WaitForKey`.
     * - `events[1]` se crea como un evento timer periódico (CreateEvent + SetTimer).
     * - El bucle principal espera ambos con `WaitForEvent(2, events, &event_index)`;
     *   cuando `event_index==0` se procesan teclas, cuando `==1` avanza el frame.
     *
     * Esto reemplaza el polling + Stall y equivale a usar "interrupciones"
     * proporcionadas por el firmware UEFI.
     */
    events[0] = st->ConIn->WaitForKey;
    events[1] = (EFI_EVENT)0;

    status = st->BootServices->CreateEvent(EVT_TIMER, TPL_CALLBACK, (EFI_EVENT_NOTIFY)0, 0, &events[1]);
    if (EFI_ERROR(status)) {
        return status;
    }
    timer_created = 1;

    status = st->BootServices->SetTimer(events[1], TimerPeriodic, frame_tick_100ns);
    if (EFI_ERROR(status)) {
        goto cleanup;
    }

    for (;;) {
        BOOLEAN needs_redraw = 0;

        /* EVENTO UEFI: aquí el firmware despierta cuando ocurre teclado o tick.
         * event_index == 0 => entrada de teclado
         * event_index == 1 => tick del timer de frame
         */
        status = st->BootServices->WaitForEvent(2, events, &event_index);
        if (EFI_ERROR(status)) {
            goto cleanup;
        }

        if (event_index == 0) {
            /* Consumimos todas las teclas pendientes para reducir latencia de input. */
            while (poll_key(st, &key)) {
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
                    state.seed = make_seed(st, &fb);
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

        /* Tick de frame: actualiza física y dibujado */
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
            needs_redraw = 1;
        }

        if (needs_redraw) {
            if (prev_rotation != 0xFF) {
                INT32 old_w;
                INT32 old_h;
                calc_bounds(prev_rotation, str_len8(NAME1), str_len8(NAME2), &old_w, &old_h);
                clear_rect(&fb, prev_x, prev_y, old_w, old_h, COL_BG);
            }

            draw_names_only(&fb, &state);
            prev_x = state.x;
            prev_y = state.y;
            prev_rotation = state.rotation;
        }
    }

cleanup:
    if (timer_created) {
        st->BootServices->CloseEvent(events[1]);
    }
    return status;
}
