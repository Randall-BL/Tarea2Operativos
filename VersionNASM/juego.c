typedef unsigned char  u8;
typedef unsigned short u16;
typedef unsigned int   u32;
typedef signed short   s16;
typedef signed int     s32;

enum {
    ROT_NORMAL = 0,
    ROT_LEFT   = 1,
    ROT_180    = 2,
    ROT_RIGHT  = 3
};

enum {
    MOVE_KEY_NONE  = 0,
    MOVE_KEY_UP    = 1,
    MOVE_KEY_DOWN  = 2,
    MOVE_KEY_LEFT  = 3,
    MOVE_KEY_RIGHT = 4
};

#define SCALE 1
#define CHAR_SIZE (8 * SCALE)
#define CHAR_ADV  (9 * SCALE)
#define MOVE_SPEED 4
#define HOLD_TIMEOUT_FRAMES 14

#define VGA_W 320
#define VGA_H 200

#define COL_BG 0
#define COL_T1 11
#define COL_T2 13

typedef struct {
    s32 x;
    s32 y;
    u8 rotation;
    u32 seed;
} GameState;

typedef struct {
    u8 ascii;
    u8 scan;
} KeyEvent;

static const char NAME1[] = "RANDALL";
static const char NAME2[] = "CHRIS";

static const u8 GLYPH_A[8] = {0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00};
static const u8 GLYPH_C[8] = {0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0x00};
static const u8 GLYPH_D[8] = {0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0x00};
static const u8 GLYPH_H[8] = {0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0x00};
static const u8 GLYPH_I[8] = {0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x7E, 0x00};
static const u8 GLYPH_L[8] = {0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0x00};
static const u8 GLYPH_N[8] = {0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0x00};
static const u8 GLYPH_R[8] = {0x7C, 0x66, 0x66, 0x7C, 0x6C, 0x66, 0x66, 0x00};
static const u8 GLYPH_S[8] = {0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0x00};
static const u8 GLYPH_SPACE[8] = {0, 0, 0, 0, 0, 0, 0, 0};

static void bios_set_mode(u8 mode) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)mode)
        : "cc", "memory"
    );
}

static void bios_set_cursor(u8 row, u8 col) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)0x0200), "b"((u16)0x0000), "d"((u16)(((u16)row << 8) | col))
        : "cc", "memory"
    );
}

static void bios_putc_teletype(char c) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)(0x0E00 | (u8)c)), "b"((u16)0x0000)
        : "cc", "memory"
    );
}

static void bios_print_at(u8 row, u8 col, const char *s) {
    bios_set_cursor(row, col);
    while (*s) {
        bios_putc_teletype(*s++);
    }
}

static u16 bios_get_ticks(void) {
    u16 ticks;
    __asm__ __volatile__(
        "int $0x1A"
        : "=d"(ticks)
        : "a"((u16)0x0000)
        : "cc", "memory"
    );
    return ticks;
}

static void bios_stall_us(u16 us) {
    __asm__ __volatile__(
        "int $0x15"
        :
        : "a"((u16)0x8600), "c"((u16)0x0000), "d"(us)
        : "cc", "memory"
    );
}

static int bios_poll_key(KeyEvent *ev) {
    u16 ax;
    u16 flags;

    __asm__ __volatile__(
        "pushf\n\t"
        "mov $0x0100, %%ax\n\t"
        "int $0x16\n\t"
        "pushf\n\t"
        "pop %%bx\n\t"
        "popf"
        : "=a"(ax), "=b"(flags)
        :
        : "cc", "memory"
    );

    if (flags & 0x0040) {
        return 0;
    }

    __asm__ __volatile__(
        "int $0x16"
        : "=a"(ax)
        : "a"((u16)0x0000)
        : "cc", "memory"
    );

    ev->ascii = (u8)(ax & 0xFF);
    ev->scan = (u8)(ax >> 8);
    return 1;
}

static u16 bios_wait_key(void) {
    u16 ax;
    __asm__ __volatile__(
        "int $0x16"
        : "=a"(ax)
        : "a"((u16)0x0000)
        : "cc", "memory"
    );
    return ax;
}

static u8 *vga_mem(void) {
    return (u8 *)(0xA0000UL);
}

static void put_pixel(s32 x, s32 y, u8 color) {
    u8 *vga;
    u32 off;

    if (x < 0 || y < 0 || x >= VGA_W || y >= VGA_H) {
        return;
    }

    vga = vga_mem();
    off = (u32)y * VGA_W + (u32)x;
    vga[off] = color;
}

static void fill_screen(u8 color) {
    u8 *vga = vga_mem();
    u32 i;
    for (i = 0; i < (u32)(VGA_W * VGA_H); ++i) {
        vga[i] = color;
    }
}

static const u8 *glyph_for_char(char ch) {
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

static u16 str_len8(const char *s) {
    u16 len = 0;
    while (s[len] != 0) {
        ++len;
    }
    return len;
}

static void draw_glyph_rotated(s32 base_x, s32 base_y, const u8 glyph[8], u8 rotation, u8 color) {
    s32 row;
    s32 col;

    for (row = 0; row < 8; ++row) {
        u8 bits = glyph[row];
        for (col = 0; col < 8; ++col) {
            s32 px;
            s32 py;
            s32 draw_x;
            s32 draw_y;
            s32 dy;
            s32 dx;

            if (((bits >> (7 - col)) & 1u) == 0u) {
                continue;
            }

            px = col;
            py = row;

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
                    put_pixel(draw_x + dx, draw_y + dy, color);
                }
            }
        }
    }
}

static void draw_string_rotated(s32 x, s32 y, const char *text, u8 rotation, u8 color) {
    u16 len = str_len8(text);
    u16 i;

    for (i = 0; i < len; ++i) {
        u16 idx = i;
        const u8 *glyph;
        s32 gx = x;
        s32 gy = y;

        if (rotation == ROT_180) {
            idx = (u16)(len - 1 - i);
        }

        glyph = glyph_for_char(text[idx]);

        if (rotation == ROT_NORMAL || rotation == ROT_180) {
            gx = x + (s32)i * CHAR_ADV;
        } else {
            gy = y + (s32)i * CHAR_ADV;
        }

        draw_glyph_rotated(gx, gy, glyph, rotation, color);
    }
}

static void calc_bounds(u8 rotation, u16 len1, u16 len2, s32 *out_w, s32 *out_h) {
    s32 gap = CHAR_SIZE / 2;
    s32 max_len = (len1 > len2) ? (s32)len1 : (s32)len2;

    if (rotation == ROT_NORMAL || rotation == ROT_180) {
        *out_w = max_len * CHAR_ADV;
        *out_h = (CHAR_SIZE * 2) + gap;
    } else {
        *out_w = (CHAR_SIZE * 2) + gap;
        *out_h = max_len * CHAR_ADV;
    }
}

static u32 lcg_next(u32 *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;
    return *seed;
}

static u32 make_seed(void) {
    u32 seed = 0xA5A5A5A5u;
    u16 ticks = bios_get_ticks();
    u8 pit_low;

    __asm__ __volatile__("inb $0x40, %0" : "=a"(pit_low));

    seed ^= (u32)ticks;
    seed ^= ((u32)ticks << 16);
    seed ^= ((u32)pit_low << 24);
    seed ^= 0x1234ABCDu;

    seed ^= (seed << 13);
    seed ^= (seed >> 17);
    seed ^= (seed << 5);

    if (seed == 0) {
        seed = 1;
    }

    return seed;
}

static void randomize_position(GameState *state) {
    s32 obj_w;
    s32 obj_h;
    s32 max_x;
    s32 max_y;

    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    max_x = VGA_W - obj_w;
    max_y = VGA_H - obj_h;

    if (max_x < 0) max_x = 0;
    if (max_y < 0) max_y = 0;

    state->x = (s32)(lcg_next(&state->seed) % (u32)(max_x + 1));
    state->y = (s32)(lcg_next(&state->seed) % (u32)(max_y + 1));
}

static void move_with_bounce(GameState *state, s32 *vx, s32 *vy) {
    s32 obj_w;
    s32 obj_h;
    s32 max_x;
    s32 max_y;
    s32 nx;
    s32 ny;

    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    max_x = VGA_W - obj_w;
    max_y = VGA_H - obj_h;

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

static void draw_scene(const GameState *state) {
    s32 gap = CHAR_SIZE / 2;

    fill_screen(COL_BG);

    if (state->rotation == ROT_NORMAL || state->rotation == ROT_180) {
        draw_string_rotated(state->x, state->y, NAME1, state->rotation, COL_T1);
        draw_string_rotated(state->x, state->y + CHAR_SIZE + gap, NAME2, state->rotation, COL_T2);
    } else {
        draw_string_rotated(state->x, state->y, NAME1, state->rotation, COL_T1);
        draw_string_rotated(state->x + CHAR_SIZE + gap, state->y, NAME2, state->rotation, COL_T2);
    }
}

static int confirm_start(void) {
    u16 key;

    bios_set_mode(0x03);
    bios_print_at(2, 2,  "=========================================");
    bios_print_at(3, 2,  " JUEGO: CHRIS Y RANDALL");
    bios_print_at(4, 2,  "=========================================");
    bios_print_at(6, 2,  "Controles:");
    bios_print_at(7, 2,  " Flecha Izq  : Rotar 90 a la izquierda");
    bios_print_at(8, 2,  " Flecha Der  : Rotar 90 a la derecha");
    bios_print_at(9, 2,  " Flecha Arr  : Rotar 180");
    bios_print_at(10, 2, " Flecha Abj  : Rotar 180");
    bios_print_at(11, 2, " W/S/A/D     : Mover con rebote");
    bios_print_at(12, 2, " R           : Reiniciar posicion random");
    bios_print_at(13, 2, " ESC         : Salir del juego");
    bios_print_at(15, 2, "ENTER para comenzar o ESC para cancelar...");

    for (;;) {
        key = bios_wait_key();
        if ((u8)(key & 0xFF) == 0x0D) {
            return 1;
        }
        if ((u8)(key >> 8) == 0x01 || (u8)(key & 0xFF) == 27) {
            return 0;
        }
    }
}

void juego_main(void) __attribute__((used));
void juego_main(void) {
    GameState state;
    u32 frame = 0;
    u32 last_move_input_frame = 0;
    u8 active_move_key = MOVE_KEY_NONE;
    s32 vx = 0;
    s32 vy = 0;

    if (!confirm_start()) {
        return;
    }

    bios_set_mode(0x13);

    state.rotation = ROT_NORMAL;
    state.seed = make_seed();
    randomize_position(&state);

    for (;;) {
        KeyEvent key;
        ++frame;

        while (bios_poll_key(&key)) {
            if (key.scan == 0x01 || key.ascii == 27) {
                bios_set_mode(0x03);
                return;
            }

            if (key.scan == 0x4B) {
                state.rotation = (u8)((state.rotation + 3u) & 3u);
                continue;
            }

            if (key.scan == 0x4D) {
                state.rotation = (u8)((state.rotation + 1u) & 3u);
                continue;
            }

            if (key.scan == 0x48 || key.scan == 0x50) {
                state.rotation = (u8)(state.rotation ^ 2u);
                continue;
            }

            if (key.ascii == 'r' || key.ascii == 'R') {
                state.rotation = ROT_NORMAL;
                state.seed = make_seed();
                randomize_position(&state);
                continue;
            }

            if (key.ascii == 'w' || key.ascii == 'W') {
                if (!(active_move_key == MOVE_KEY_UP && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_UP;
                    vx = 0;
                    vy = -MOVE_SPEED;
                }
                last_move_input_frame = frame;
                continue;
            }

            if (key.ascii == 's' || key.ascii == 'S') {
                if (!(active_move_key == MOVE_KEY_DOWN && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_DOWN;
                    vx = 0;
                    vy = MOVE_SPEED;
                }
                last_move_input_frame = frame;
                continue;
            }

            if (key.ascii == 'a' || key.ascii == 'A') {
                if (!(active_move_key == MOVE_KEY_LEFT && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_LEFT;
                    vx = -MOVE_SPEED;
                    vy = 0;
                }
                last_move_input_frame = frame;
                continue;
            }

            if (key.ascii == 'd' || key.ascii == 'D') {
                if (!(active_move_key == MOVE_KEY_RIGHT && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_RIGHT;
                    vx = MOVE_SPEED;
                    vy = 0;
                }
                last_move_input_frame = frame;
                continue;
            }
        }

        if (active_move_key != MOVE_KEY_NONE) {
            if ((frame - last_move_input_frame) > HOLD_TIMEOUT_FRAMES) {
                active_move_key = MOVE_KEY_NONE;
                vx = 0;
                vy = 0;
            } else {
                move_with_bounce(&state, &vx, &vy);
            }
        }

        draw_scene(&state);
        bios_stall_us(16000);
    }
}

void _start(void) __attribute__((naked, used, section(".start")));
void _start(void) {
    __asm__ __volatile__ (
        "cli\n\t"
        "xor %%ax, %%ax\n\t"
        "mov %%ax, %%ds\n\t"
        "mov %%ax, %%es\n\t"
        "mov %%ax, %%ss\n\t"
        "mov $0x00007C00, %%esp\n\t"
        "sti\n\t"
        "cld\n\t"
        "call juego_main\n\t"
        "1:\n\t"
        "hlt\n\t"
        "jmp 1b\n\t"
        :
        :
        : "ax", "memory"
    );
}
