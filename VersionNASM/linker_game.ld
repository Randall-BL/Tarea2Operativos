/* ============================================================
 * linker_game.ld - Linker Script (GNU LD) para juego.c en modo real 16-bit
 * ============================================================
 *
 * Propósito:
 *   Define cómo organizar secciones de código, datos y BSS en la memoria
 *   final después de compilar juego.c (16-bit) con gcc -m16.
 *
 * Entrada: juego.o (objeto compilado de juego.c)
 * Salida: juego.elf (intermedio) → objcopy → juego.bin (binario puro)
 *
 * Modelo de Memoria (basado en este script):
 *   . = 0x8000 : inicio de carga (dirección 0x8000 = 32KB)
 *   .start : código de arranque (si existe)
 *   .text : código del programa
 *   .rodata : datos de solo lectura (strings, constantes)
 *   .data : datos inicializados
 *   .bss : datos sin inicializar (se rellenan con 0s en runtime)
 *
 * Ejecución:
 *   Cuando el bootloader salta a 0x8000, comienza a ejecutar este programa.
 *   El programa tiene acceso a video (0xA0000), disco (INT 0x13),
 *   teclado (INT 0x16), y otros servicios BIOS.
 */

ENTRY(_start)  /* Símbolo de entrada (punto de inicio si es EXEUTABLE) */

SECTIONS {
  /* Dirección de carga: 0x8000 (32 KB en memoria) */
  . = 0x8000;

  /* Sección .start: código de inicialización (si existe) */
  .start : {
    *(.start)               /* Incluir .start de todos los archivos objeto */
  }

  /* Sección de código: contiene instrucciones ejecutables */
  .text : {
    *(.text*)               /* Incluir todas las secciones .text* */
    *(.rodata*)             /* Incluir datos de solo lectura (strings, constantes) */
  }

  /* Sección .data: datos inicializados */
  .data : {
    *(.data*)               /* Incluir todas las secciones .data* */
  }

  /* Sección .bss: datos sin inicializar (no ocupa espacio en archivo binario) */
  .bss : {
    *(.bss*)                /* Incluir todas las secciones .bss* */
    *(COMMON)               /* Incluir símbolos globales no inicializados */
  }
}

/* Fin del script de linking */
