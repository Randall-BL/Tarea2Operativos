/* juego.c (BIOS/NASM)
 * ---------------------------------
 * Versión para BIOS real (arranca desde un MBR/boot sector).
 * Este archivo usa interrupciones BIOS clásicas (x86 INT):
 * - INT 0x10 : servicios de video (AH=0x0E teletipo, AH=0x0C poner píxel)
 * - INT 0x16 : teclado (servicios de teclado, espera o sondeo)
 * - INT 0x1A : reloj/ticks del BIOS
 * - INT 0x15 : utilidades (ej. stall/us)
 *
 * Las funciones `bios_*` encapsulan las llamadas a `int`.
 * Busca los comentarios marcados "INTERRUPCION" para ver
 * en qué puntos del código se usan.
 */

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
#define MOVE_SPEED 6
#define HOLD_TIMEOUT_FRAMES 24

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

/* INTERRUPCION BIOS (video): INT 0x10 AH=0x00
 * Cambia de modo de video.
 * - 0x03: texto 80x25
 * - 0x13: gráfico 320x200x256
 */
static void bios_set_mode(u8 mode) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)mode)
        : "cc", "memory"
    );
}

/* INTERRUPCION BIOS (video): INT 0x10 AH=0x02
 * Posiciona el cursor en modo texto.
 */
static void bios_set_cursor(u8 row, u8 col) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)0x0200), "b"((u16)0x0000), "d"((u16)(((u16)row << 8) | col))
        : "cc", "memory"
    );
}

/* INTERRUPCION BIOS (video): INT 0x10 AH=0x0E
 * Imprime un carácter por teletipo en modo texto.
 */
static void bios_putc_teletype(char c) {
    __asm__ __volatile__(
        "int $0x10"
        :
        : "a"((u16)(0x0E00 | (u8)c)), "b"((u16)0x0000)
        : "cc", "memory"
    );
}

/* Imprime una cadena en una posición de pantalla en modo texto usando
 * `bios_set_cursor` + `bios_putc_teletype`.
 */
static void bios_print_at(u8 row, u8 col, const char *s) {
    bios_set_cursor(row, col);
    while (*s) {
        bios_putc_teletype(*s++);
    }
}

/* INTERRUPCION BIOS (tiempo): INT 0x1A AH=0x00
 * Lee ticks del reloj BIOS (contador de tiempo desde medianoche).
 * Se usa para construir la semilla pseudoaleatoria del juego.
 */
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

/* INTERRUPCION BIOS (servicio de espera): INT 0x15 AH=0x86
 * Espera aproximada en microsegundos.
 * Se usa para limitar la velocidad del bucle principal.
 */
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

/* En modo 13h, el framebuffer lineal está mapeado en 0xA0000.
 * Para rendimiento, el render del juego escribe directamente aquí.
 *
 * Nota: seguimos usando interrupciones de video BIOS para:
 * - cambiar modo (INT 0x10 AH=0x00)
 * - salida de texto del menú (INT 0x10 AH=0x0E)
 */
static u8 *vga_mem(void) {
    return (u8 *)(0xA0000UL);
}

/* Dibujo seguro de píxel con clipping por límites de pantalla.
 * En vez de INT por píxel (muy lento), escribe directamente en VRAM.
 */
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

/* Limpieza completa de pantalla en VRAM lineal.
 * Esto evita la pausa larga de pantalla negra al iniciar el juego.
 */
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

/* Draw_Glyph_Rotated
 * Dibuja un carácter (glyph) de 8x8 píxeles escalado y rotado.
 *
 * Parámetros:
 *   base_x, base_y: posición de esquina superior-izquierda en pantalla
 *   glyph: puntero a tabla de 8 bytes (cada byte = una fila)
 *   rotation: ROT_NORMAL, ROT_LEFT, ROT_180, o ROT_RIGHT
 *   color: índice de color del paleta VGA de 256 colores
 *
 * Funcionamiento:
 *   1. Itera cada fila del glyph (8 filas)
 *   2. Extrae cada bit de la fila (8 bits = 8 columnas)
 *   3. Si el bit está activado, escala y rota el píxel correspondiente
 *   4. Escribe en VRAM directamente (0xA0000) sin INT 0x10
 *
 * Rotaciones:
 *   ROT_NORMAL: sin rotación (px=col, py=row)
 *   ROT_LEFT:   rotación 90° CCW (px=row, py=7-col)
 *   ROT_RIGHT:  rotación 90° CW (px=7-row, py=col)
 *   ROT_180:    180° (px=7-col, py=7-row)
 */
static void draw_glyph_rotated(s32 base_x, s32 base_y, const u8 glyph[8], u8 rotation, u8 color) {
    s32 row;
    s32 col;

    for (row = 0; row < 8; ++row) {
        u8 bits = glyph[row];  /* Byte de fila: 8 bits = 8 columnas del glyph */
        for (col = 0; col < 8; ++col) {
            s32 px;
            s32 py;
            s32 draw_x;
            s32 draw_y;
            s32 dy;
            s32 dx;

            /* Si el bit está a 0, saltar (píxel desactivado) */
            if (((bits >> (7 - col)) & 1u) == 0u) {
                continue;
            }

            px = col;       /* Posición X dentro del glyph 8x8 */
            py = row;       /* Posición Y dentro del glyph 8x8 */

            /* Aplicar rotación a (px, py) */
            if (rotation == ROT_LEFT) {
                px = row;       /* Rotar 90° izquierda */
                py = 7 - col;
            } else if (rotation == ROT_RIGHT) {
                px = 7 - row;   /* Rotar 90° derecha */
                py = col;
            } else if (rotation == ROT_180) {
                px = 7 - col;   /* Rotar 180° */
                py = 7 - row;
            }
            /* else: ROT_NORMAL mantiene px, py sin cambios */

            /* Escalar los píxeles: cada píxel del glyph ocupa SCALE×SCALE píxeles en pantalla */
            draw_x = base_x + px * SCALE;
            draw_y = base_y + py * SCALE;

            /* Dibujar bloque SCALE×SCALE en VRAM */
            for (dy = 0; dy < SCALE; ++dy) {
                for (dx = 0; dx < SCALE; ++dx) {
                    put_pixel(draw_x + dx, draw_y + dy, color);  /* Escribe directamente en 0xA0000 */
                }
            }
        }
    }
}

/* Draw_String_Rotated
 * Dibuja una cadena de texto escalada y rotada en pantalla.
 *
 * Parámetros:
 *   x, y: posición de inicio
 *   text: cadena terminada en 0
 *   rotation: dirección (ROT_NORMAL, ROT_LEFT, ROT_180, ROT_RIGHT)
 *   color: color de los caracteres
 *
 * Lógica:
 *   - Calcula longitud de la cadena
 *   - Para cada carácter, obtiene su glyph
 *   - Calcula posición dependiendo de rotación
 *   - Llama a draw_glyph_rotated para renderizar cada carácter
 */
static void draw_string_rotated(s32 x, s32 y, const char *text, u8 rotation, u8 color) {
    u16 len = str_len8(text);  /* Contar caracteres (longitud de cadena) */
    u16 i;

    for (i = 0; i < len; ++i) {
        u16 idx = i;            /* Índice en la cadena */
        const u8 *glyph;
        s32 gx = x;             /* Coordenada X del carácter */
        s32 gy = y;             /* Coordenada Y del carácter */

        /* Para ROT_180, invertir orden de caracteres (leer de derecha a izquierda) */
        if (rotation == ROT_180) {
            idx = (u16)(len - 1 - i);
        }

        glyph = glyph_for_char(text[idx]);  /* Obtener tabla de píxeles del carácter */

        /* Calcular posición: horizontal (NORMAL/180) o vertical (LEFT/RIGHT) */
        if (rotation == ROT_NORMAL || rotation == ROT_180) {
            gx = x + (s32)i * CHAR_ADV;  /* Avance horizontal: cada carácter sumamos CHAR_ADV */
        } else {
            gy = y + (s32)i * CHAR_ADV;  /* Avance vertical */
        }

        draw_glyph_rotated(gx, gy, glyph, rotation, color);  /* Dibujar carácter individual */
    }
}

/* Calc_Bounds
 * Calcula el área rectangular (W×H) ocupada por dos cadenas superpuestas.
 *
 * Parámetros:
 *   rotation: dirección de las cadenas
 *   len1, len2: longitud de cadena 1 (NAME1) y cadena 2 (NAME2)
 *   out_w, out_h: punteros para devolver ancho y alto
 *
 * Lógica:
 *   - Cálcula espacio máximo ocupado según rotación
 *   - Suma espacio entre cadenas (gap = CHAR_SIZE / 2)
 */
static void calc_bounds(u8 rotation, u16 len1, u16 len2, s32 *out_w, s32 *out_h) {
    s32 gap = CHAR_SIZE / 2;   /* Separación entre las dos cadenas */
    s32 max_len = (len1 > len2) ? (s32)len1 : (s32)len2;  /* Cadena más larga */

    if (rotation == ROT_NORMAL || rotation == ROT_180) {
        /* Cadenas dispuestas horizontalmente (una encima de otra) */
        *out_w = max_len * CHAR_ADV;           /* Ancho = máxima longitud × avance por carácter */
        *out_h = (CHAR_SIZE * 2) + gap;        /* Altura = dos cadenas + gap */
    } else {
        /* Cadenas dispuestas verticalmente (una al lado de la otra) */
        *out_w = (CHAR_SIZE * 2) + gap;        /* Ancho = dos cadenas + gap */
        *out_h = max_len * CHAR_ADV;           /* Altura = máxima longitud × avance */
    }
}

/* LCG_Next
 * Generador Congruencial Lineal (Linear Congruential Generator) simple.
 * Usado para pseudoaleatoriedad reproducible.
 *
 * Fórmula: seed_{n+1} = (seed_n * a) + c
 * Parámetros: a=1664525, c=1013904223 (valores MINSTD estándar)
 */
static u32 lcg_next(u32 *seed) {
    *seed = (*seed * 1664525u) + 1013904223u;  /* Actualizar semilla */
    return *seed;  /* Devolver nueva semilla (también es el número aleatorio) */
}

/* Make_Seed
 * Genera semilla inicial pseudoaleatoria usando fuentes del BIOS y hardware.
 *
 * Fuentes de entropía:
 *   1. Ticks del reloj BIOS (INT 0x1A) - cambia continuamente
 *   2. PIT (Programmable Interval Timer) puerto 0x40 - contador de hardware
 *   3. Valor inicial fijo (0xA5A5A5A5) - mezcla garantizada
 *   4. Transformaciones XOR/shift - difusión de bits
 *
 * Precaución: En un emulador, las fuentes de entropía pueden ser predecibles.
 */
static u32 make_seed(void) {
    u32 seed = 0xA5A5A5A5u;  /* Valor inicial */
    u16 ticks = bios_get_ticks();  /* INTERRUPCION: INT 0x1A - obtener ticks del BIOS */
    u8 pit_low;

    /* Leer puerto de hardware PIT (no INT, acceso directo) */
    /* Puerto 0x40 = Contador de canal 0 del PIT */
    __asm__ __volatile__("inb $0x40, %0" : "=a"(pit_low));  /* IN AL, 0x40 */

    /* Mezclar ticks (16-bit) en la semilla (32-bit) */
    seed ^= (u32)ticks;             /* bytesbajos */
    seed ^= ((u32)ticks << 16);     /* bytes altos */
    seed ^= ((u32)pit_low << 24);   /* byte del PIT */
    seed ^= 0x1234ABCDu;            /* constante adicional */

    /* Transformaciones para difundir bits (mezcla chaotic) */
    seed ^= (seed << 13);
    seed ^= (seed >> 17);
    seed ^= (seed << 5);

    /* Garantizar que seed no sea 0 (LCG necesita seed != 0) */
    if (seed == 0) {
        seed = 1;
    }

    return seed;
}

/* Randomize_Position
 * Asigna una posición aleatoria al objeto dentro de los límites de pantalla.
 * Se llama al iniciar juego y también con la tecla R.
 */
static void randomize_position(GameState *state) {
    s32 obj_w;   /* Ancho del objeto (ambas cadenas) */
    s32 obj_h;   /* Alto del objeto */
    s32 max_x;   /* Máximo valor válido para X */
    s32 max_y;   /* Máximo valor válido para Y */

    /* Calcular bounding box del objeto en su rotación actual */
    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    /* Máximo X = pantalla_ancho - objeto_ancho (para no salir por derecha) */
    max_x = VGA_W - obj_w;
    max_y = VGA_H - obj_h;

    /* Si objeto es más grande que pantalla, ajustar a 0 */
    if (max_x < 0) max_x = 0;
    if (max_y < 0) max_y = 0;

    /* Generar posición aleatoria usando LCG con módulo */
    state->x = (s32)(lcg_next(&state->seed) % (u32)(max_x + 1));  /* 0 ≤ x ≤ max_x */
    state->y = (s32)(lcg_next(&state->seed) % (u32)(max_y + 1));  /* 0 ≤ y ≤ max_y */
}

/* Move_With_Bounce
 * Actualiza posición del objeto aplicando velocidad (vx, vy).
 * Si toca límite de pantalla, rebota (invierte la componente de velocidad).
 *
 * Parámetros:
 *   state: posición y rotación actual del objeto
 *   vx, vy: velocidades en píxeles (se modifican si hay rebote)
 */
static void move_with_bounce(GameState *state, s32 *vx, s32 *vy) {
    s32 obj_w;   /* Ancho del objeto */
    s32 obj_h;   /* Alto del objeto */
    s32 max_x;   /* Límite derecho (x máximo) */
    s32 max_y;   /* Límite inferior (y máximo) */
    s32 nx;      /* Nueva posición X (con velocidad aplicada) */
    s32 ny;      /* Nueva posición Y (con velocidad aplicada) */

    /* Obtener dimensiones del bounding box */
    calc_bounds(state->rotation, str_len8(NAME1), str_len8(NAME2), &obj_w, &obj_h);

    /* Calcular límites de pantalla */
    max_x = VGA_W - obj_w;  /* x + obj_w <= VGA_W → x <= max_x */
    max_y = VGA_H - obj_h;

    if (max_x < 0) max_x = 0;
    if (max_y < 0) max_y = 0;

    /* Aplicar velocidad para obtener nueva posición */
    nx = state->x + *vx;
    ny = state->y + *vy;

    /* Chequeo de límites y rebote en eje X */
    if (nx < 0) {
        nx = 0;                      /* Clampear a 0 */
        if (*vx < 0) *vx = -*vx;     /* Rebotar (invertir dirección) */
    } else if (nx > max_x) {
        nx = max_x;                  /* Clampear a máximo */
        if (*vx > 0) *vx = -*vx;     /* Rebotar */
    }

    /* Chequeo de límites y rebote en eje Y */
    if (ny < 0) {
        ny = 0;
        if (*vy < 0) *vy = -*vy;
    } else if (ny > max_y) {
        ny = max_y;
        if (*vy > 0) *vy = -*vy;
    }

    /* Actualizar posición */
    state->x = nx;
    state->y = ny;
}

/* Clear_Rect
 * Rellena un rectángulo con un color.
 * Usado para borrar la posición anterior del objeto.
 *
 * Parámetros:
 *   x, y: esquina superior-izquierda
 *   w, h: ancho y alto del rectángulo
 *   color: color de relleno (índice de color del paleta VGA)
 */
static void clear_rect(s32 x, s32 y, s32 w, s32 h, u8 color) {
    s32 yy;
    s32 xx;
    s32 x0 = x;         /* Esquina izquierda */
    s32 y0 = y;         /* Esquina superior */
    s32 x1 = x + w;     /* Esquina derecha (exclusiva) */
    s32 y1 = y + h;     /* Esquina inferior (exclusiva) */

    /* Clampear a limites de pantalla */
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > VGA_W) x1 = VGA_W;
    if (y1 > VGA_H) y1 = VGA_H;

    /* Llenar todos los píxeles del rectángulo */
    for (yy = y0; yy < y1; ++yy) {
        for (xx = x0; xx < x1; ++xx) {
            put_pixel(xx, yy, color);  /* Escribir en VRAM */
        }
    }
}

/* Draw_Names_Only
 * Dibuja las dos cadenas NAME1 y NAME2 en la posición y rotación actuales.
 * Llama a draw_string_rotated dos veces con colores distintos (COL_T1, COL_T2).
 */
static void draw_names_only(const GameState *state) {
    s32 gap = CHAR_SIZE / 2;  /* Separación entre las dos cadenas */

    if (state->rotation == ROT_NORMAL || state->rotation == ROT_180) {
        /* Cadenas dispuestas verticalmente (NAME1 arriba, NAME2 abajo) */
        draw_string_rotated(state->x, state->y, NAME1, state->rotation, COL_T1);
        draw_string_rotated(state->x, state->y + CHAR_SIZE + gap, NAME2, state->rotation, COL_T2);
    } else {
        /* Cadenas dispuestas horizontalmente (NAME1 izquierda, NAME2 derecha) */
        draw_string_rotated(state->x, state->y, NAME1, state->rotation, COL_T1);
        draw_string_rotated(state->x + CHAR_SIZE + gap, state->y, NAME2, state->rotation, COL_T2);
    }
}

/* Confirm_Start
 * Muestra menú de inicio y espera a que el usuario confirme.
 * Devuelve 1 si usuario presionó ENTER, 0 si presionó ESC.
 *
 * Interacciones BIOS:
 *   - INT 0x10 AH=0x00 para cambiar a modo texto
 *   - INT 0x10 AH=0x02 para posicionar cursor
 *   - INT 0x10 AH=0x0E para imprimir cada carácter
 *   - INT 0x16 AH=0x00 para esperar teclada
 */
static int confirm_start(void) {
    u16 key;

    /* INTERRUPCION: INT 0x10 AH=0x00 - cambiar modo a texto 80x25 */
    bios_set_mode(0x03);
    
    /* INTERRUPCION: INT 0x10 (mediante bios_print_at = set_cursor + putc_teletype) */
    bios_print_at(2, 2,  "=========================================");
    bios_print_at(3, 2,  " JUEGO: CHRIS Y RANDALL Version BIOS/NASM");
    bios_print_at(4, 2,  "=========================================");
    bios_print_at(6, 2,  "Controles:");
    bios_print_at(7, 2,  " Flecha Izq  : Rotar 90 a la izquierda");
    bios_print_at(8, 2,  " Flecha Der  : Rotar 90 a la derecha");
    bios_print_at(9, 2,  " Flecha Arr  : Rotar 180");
    bios_print_at(10, 2, " Flecha Abj  : Rotar 180");
    bios_print_at(11, 2, " W           : Mover arriba");
    bios_print_at(12, 2, " S           : Mover abajo");
    bios_print_at(13, 2, " A           : Mover izquierda");
    bios_print_at(14, 2, " D           : Mover derecha");
    bios_print_at(15, 2, " R           : Reiniciar posicion random");
    bios_print_at(16, 2, " ESC         : Salir del juego");
    bios_print_at(18, 2, "ENTER para comenzar o ESC para cancelar...");

    /* INTERRUPCION: INT 0x16 AH=0x00 - esperar y leer tecla */
    for (;;) {
        key = bios_wait_key();  /* Bloqueante: espera que usuario presione algo */
        
        /* key = (scan_code << 8) | ascii_code */
        if ((u8)(key & 0xFF) == 0x0D) {  /* ENTER = ASCII 13 */
            return 1;  /* Iniciar juego */
        }
        if ((u8)(key >> 8) == 0x01 || (u8)(key & 0xFF) == 27) {  /* ESC = scan 1 o ASCII 27 */
            return 0;  /* Cancelar */
        }
    }
}

/* Juego_Main
 * Función principal del juego - loop de animación y lógica.
 *
 * Flujo:
 *   1. Mostrar menú de confirmación (INT 0x10, INT 0x16)
 *   2. Si usuario cancela, retornar
 *   3. Cambiar a modo gráfico VGA 320x200x256 (INT 0x10)
 *   4. Loop infinito:
 *      a. Leer teclado no-bloqueante (INT 0x16)
 *      b. Procesar rotaciones, movimiento, reinicio random
 *      c. Aplicar física (rebotes)
 *      d. Re-renderizar si hay cambios (escritura directa a VRAM)
 *      e. Esperar por duración constante de frame (INT 0x15)
 *   5. Si ESC, retornar a modo texto (INT 0x10) y salir
 *
 * INTERRUPCIONES BIOS usadas:
 *   - INT 0x10: Cambio de modo de video
 *   - INT 0x16: Lectura de teclado (poll y wait)
 *   - INT 0x1A: Obtener ticks para seed de RNG
 *   - INT 0x15: Espera en microsegundos (temporización de frame)
 */
void juego_main(void) __attribute__((used));
void juego_main(void) {
    /* ---- Variables de estado ---- */
    GameState state;             /* Posición, rotación, semilla RNG */
    u32 frame = 0;               /* Contador de frames */
    u32 last_move_input_frame = 0; /* Frame en el que se presionó última tecla de movimiento */
    u8 active_move_key = MOVE_KEY_NONE;  /* Tecla de movimiento activa (para hold/repeat) */
    s32 vx = 0;                  /* Velocidad X */
    s32 vy = 0;                  /* Velocidad Y */
    s32 prev_x = 0;              /* Posición anterior (para detección de cambios) */
    s32 prev_y = 0;
    u8 prev_rotation = 0xFF;     /* Rotación anterior (0xFF = no dibujado aún) */

    /* Mostrar menú y esperar confirmación del usuario */
    if (!confirm_start()) {
        return;  /* Usuario presionó ESC */
    }

    /* INTERRUPCION: INT 0x10 AH=0x00 - cambiar a modo gráfico 320x200x256 */
    bios_set_mode(0x13);

    /* Inicializar estado del juego */
    state.rotation = ROT_NORMAL;
    state.seed = make_seed();  /* Usar INT 0x1A y PIT 0x40 para entropía */
    randomize_position(&state);  /* Generar posición aleatoria inicial */

    /* RENDER INICIAL: llenar pantalla con color de fondo */
    fill_screen(COL_BG);  /* Escribe directamente a VRAM 0xA0000 */
    prev_x = state.x;
    prev_y = state.y;

    /* ---- LOOP PRINCIPAL DEL JUEGO ---- */
    for (;;) {
        KeyEvent key;                /* Tecla leída */
        int needs_redraw = 0;        /* Flag: ¿hay cambios visuales? */
        ++frame;                     /* Incrementar contador de frames */

        /* ---- ENTRADA: Lectura de teclado con INT 0x16 (no-bloqueante polling) ---- */
        /* bios_poll_key intenta leer sin esperar (AH=0x01) */
        while (bios_poll_key(&key)) {
            /* ESC: salir del juego */
            if (key.scan == 0x01 || key.ascii == 27) {
                bios_set_mode(0x03);  /* INTERRUPCION: INT 0x10 - volver a modo texto */
                return;  /* Salir de juego_main */
            }

            /* Flecha Izquierda: rotar 90° a la izquierda (ROT_LEFT) */
            if (key.scan == 0x4B) {
                state.rotation = (u8)((state.rotation + 3u) & 3u);  /* (rot - 1) & 3 */
                continue;
            }

            /* Flecha Derecha: rotar 90° a la derecha (ROT_RIGHT) */
            if (key.scan == 0x4D) {
                state.rotation = (u8)((state.rotation + 1u) & 3u);
                continue;
            }

            /* Flecha Arriba/Abajo: rotar 180° */
            if (key.scan == 0x48 || key.scan == 0x50) {
                state.rotation = (u8)(state.rotation ^ 2u);  /* XOR con 2 invierte bits ROT_180 */
                continue;
            }

            /* R: reinicializar posición aleatoria */
            if (key.ascii == 'r' || key.ascii == 'R') {
                state.rotation = ROT_NORMAL;
                state.seed = make_seed();  /* Nueva semilla usando INT 0x1A, y puerto PIT */
                randomize_position(&state);
                continue;
            }

            /* W: mover hacia arriba */
            if (key.ascii == 'w' || key.ascii == 'W') {
                if (!(active_move_key == MOVE_KEY_UP && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_UP;
                    vx = 0;
                    vy = -MOVE_SPEED;
                }
                last_move_input_frame = frame;
                continue;
            }

            /* S: mover hacia abajo */
            if (key.ascii == 's' || key.ascii == 'S') {
                if (!(active_move_key == MOVE_KEY_DOWN && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_DOWN;
                    vx = 0;
                    vy = MOVE_SPEED;
                }
                last_move_input_frame = frame;
                continue;
            }

            /* A: mover hacia la izquierda */
            if (key.ascii == 'a' || key.ascii == 'A') {
                if (!(active_move_key == MOVE_KEY_LEFT && (frame - last_move_input_frame) <= HOLD_TIMEOUT_FRAMES)) {
                    active_move_key = MOVE_KEY_LEFT;
                    vx = -MOVE_SPEED;
                    vy = 0;
                }
                last_move_input_frame = frame;
                continue;
            }

            /* D: mover hacia la derecha */
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

        /* ---- LÓGICA: Detección de tecla "held" y evaluación de movimiento ---- */
        if (active_move_key != MOVE_KEY_NONE) {
            /* Si pasaron demasiados frames sin input, cancelar movimiento */
            if ((frame - last_move_input_frame) > HOLD_TIMEOUT_FRAMES) {
                active_move_key = MOVE_KEY_NONE;
                vx = 0;
                vy = 0;
            } else {
                /* Aplicar velocidad, rebotes contra bordes */
                move_with_bounce(&state, &vx, &vy);
            }
        }

        /* ---- RENDERIZADO: Actualizar pantalla si hay cambios ---- */
        /* Detectar si la posición o rotación cambió */
        if (state.x != prev_x || state.y != prev_y || state.rotation != prev_rotation) {
            needs_redraw = 1;
        }

        if (needs_redraw) {
            /* Si no es el primer frame, borrar la posición anterior del objeto */
            if (prev_rotation != 0xFF) {
                s32 old_w;
                s32 old_h;
                calc_bounds(prev_rotation, str_len8(NAME1), str_len8(NAME2), &old_w, &old_h);
                clear_rect(prev_x, prev_y, old_w, old_h, COL_BG);  /* Escribir directamente a VRAM */
            }

            /* Dibujar las dos cadenas en nueva posición */
            draw_names_only(&state);  /* Llama a draw_string_rotated 2 veces */
            
            /* Actualizar posición anterior para próximo frame */
            prev_x = state.x;
            prev_y = state.y;
            prev_rotation = state.rotation;
        }

        /* ---- TEMPORIZACIÓN: INT 0x15 AH=0x86 para esperar microsegundos ---- */
        /* Esto limita la velocidad del juego a ~16ms por frame (~62.5 FPS) */
        bios_stall_us(16000);  /* INTERRUPCION: esperar 16000 microsegundos */
    }
}

/* _Start
 * Punto de entrada del programa ejecutable (punto de entrada real).
 *
 * Atributos especiales:
 *   - naked: el compilador no genera prólogo/epílogo de función
 *   - used: no optimizar como función no utilizada
 *   - section(".start"): colocar esta función en sección .start (definida en linker_game.ld)
 *
 * Responsabilidades:
 *   1. Inicializar registros de segmento (DS, ES, SS)
 *   2. Configurar stack pointer (ESP)
 *   3. Deshabilitar interrupciones durante setup (cli)
 *   4. Re-habilitar interrupciones cuando esté listo (sti)
 *   5. Llamar a juego_main()
 *   6. Si juego_main retorna, entrar en bucle infinite (hlt)
 *
 * Nota: Esta función es llamada directamente desde el bootloader en 0x8000.
 *       el bootloader salta a este punto con: jmp 0x0000:0x8000
 */
void _start(void) __attribute__((naked, used, section(".start")));
void _start(void) {
    __asm__ __volatile__ (
        /* Deshabilitar interrupciones durante inicialización */
        "cli\n\t"
        
        /* Inicializar registros de segmento */
        "xor %%ax, %%ax\n\t"      /* ax = 0 */
        "mov %%ax, %%ds\n\t"      /* ds (Data Segment) = 0 */
        "mov %%ax, %%es\n\t"      /* es (Extra Segment) = 0 */
        "mov %%ax, %%ss\n\t"      /* ss (Stack Segment) = 0 */
        
        /* Configurar stack pointer ESP = 0x7C00 (justo debajo del bootloader) */
        "mov $0x00007C00, %%esp\n\t"
        
        /* Re-habilitar interrupciones */
        "sti\n\t"
        
        /* Limpiar direction flag (CLD) para que las operaciones de string avanzen hacia adelante */
        "cld\n\t"
        
        /* Llamar a juego_main() */
        "call juego_main\n\t"
        
        /* Si juego_main retorna, entrar en bucle infinito (halt) */
        "1:\n\t"       /* Etiqueta para el bucle */
        "hlt\n\t"      /* Detener el CPU (esperando interrupción) */
        "jmp 1b\n\t"   /* Saltar de vuelta a hlt (bucle infinito) */
        
        /* Operandos (no hay) */
        :
        :
        : "ax", "memory"  /* Registros clobbered: AX y memoria */
    );
}

