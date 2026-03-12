#include <efi.h>
#include <efilib.h>

#include "juego.h"

#define ROT_NORMAL 0
#define ROT_LEFT   1
#define ROT_180    2
#define ROT_RIGHT  3

#define SCALE 4
#define CHAR_SIZE (8 * SCALE)
#define CHAR_ADV  (9 * SCALE)

typedef struct {
    UINT32 width;
    UINT32 height;
    UINT32 ppsl;
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
    while (s[len] != '\0') {
        ++len;
    }
    return len;
}

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

static UINT32 lcg_next(UINT32 *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;
    return *seed;
}

static EFI_STATUS confirm_start(EFI_SYSTEM_TABLE *SystemTable) {
    EFI_INPUT_KEY key;
    EFI_STATUS status;

    uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
    Print(L"=========================================\r\n");
    Print(L" JUEGO: CHRIS Y RANDALL\r\n");
    Print(L"=========================================\r\n\r\n");
    Print(L"Controles:\r\n");
    Print(L"  Flecha Izq  : Rotar 90 a la izquierda\r\n");
    Print(L"  Flecha Der  : Rotar 90 a la derecha\r\n");
    Print(L"  Flecha Arr  : Rotar 180\r\n");
    Print(L"  Flecha Abj  : Rotar 180\r\n");
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

static void fb_init(Framebuffer *fb, EFI_GRAPHICS_OUTPUT_PROTOCOL *gop) {
    fb->width = gop->Mode->Info->HorizontalResolution;
    fb->height = gop->Mode->Info->VerticalResolution;
    fb->ppsl = gop->Mode->Info->PixelsPerScanLine;
    fb->fb = (UINT32 *)(UINTN)gop->Mode->FrameBufferBase;
}

static void put_pixel(const Framebuffer *fb, INT32 x, INT32 y, UINT32 color) {
    if (x < 0 || y < 0) {
        return;
    }

    if ((UINT32)x >= fb->width || (UINT32)y >= fb->height) {
        return;
    }

    fb->fb[(UINTN)y * fb->ppsl + (UINTN)x] = color;
}

static void fill_screen(const Framebuffer *fb, UINT32 color) {
    for (UINT32 y = 0; y < fb->height; ++y) {
        for (UINT32 x = 0; x < fb->width; ++x) {
            fb->fb[(UINTN)y * fb->ppsl + x] = color;
        }
    }
}

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

static void draw_scene(const Framebuffer *fb, const GameState *state) {
    const UINT32 black = 0x00000000;
    const UINT32 yellow = 0x0000FFFF;
    const UINT32 magenta = 0x00FF00FF;
    INT32 gap = CHAR_SIZE / 2;

    fill_screen(fb, black);

    if (state->rotation == ROT_NORMAL || state->rotation == ROT_180) {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, yellow);
        draw_string_rotated(fb, state->x, state->y + CHAR_SIZE + gap, NAME2, state->rotation, magenta);
    } else {
        draw_string_rotated(fb, state->x, state->y, NAME1, state->rotation, yellow);
        draw_string_rotated(fb, state->x + CHAR_SIZE + gap, state->y, NAME2, state->rotation, magenta);
    }
}

EFI_STATUS game_run(EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_INPUT_KEY key;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;
    EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
    Framebuffer fb;
    GameState state;

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
    state.seed = 0xA5A5A5A5u ^ fb.width ^ (fb.height << 16);
    randomize_position(&state, &fb);

    while (1) {
        draw_scene(&fb, &state);

        status = wait_key(SystemTable, &key);
        if (EFI_ERROR(status)) {
            return status;
        }

        if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
            return EFI_SUCCESS;
        }

        if (key.ScanCode == SCAN_LEFT) {
            state.rotation = (UINT8)((state.rotation + 3u) & 3u);
            randomize_position(&state, &fb);
            continue;
        }

        if (key.ScanCode == SCAN_RIGHT) {
            state.rotation = (UINT8)((state.rotation + 1u) & 3u);
            randomize_position(&state, &fb);
            continue;
        }

        if (key.ScanCode == SCAN_UP || key.ScanCode == SCAN_DOWN) {
            state.rotation = (UINT8)(state.rotation ^ 2u);
            randomize_position(&state, &fb);
            continue;
        }

        if (key.UnicodeChar == 'r' || key.UnicodeChar == 'R') {
            state.rotation = ROT_NORMAL;
            randomize_position(&state, &fb);
            continue;
        }
    }

    return EFI_SUCCESS;
}
