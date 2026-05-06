/* ============================================================
 * linker.ld - Linker Script para UEFI AArch64
 * ============================================================
 *
 * Propósito:
 *   Define la disposición en memoria de secciones (code, data, BSS)
 *   después de compilar juego.c para AArch64.
 *
 * Características:
 *   - Entrada directa en efi_main_c
 *   - Inicia en dirección 0 (UEFI reloca dinámicamente)
 *   - Incluye secciones de linkage dinámico (.reloc para UEFI)
 *
 * Diferencias vs. x86_64:
 *   - ARM64 usa relocaciones .rela* en lugar de .rel*
 *   - Sección .reloc especial para compatible con PE/COFF
 *   - Tamaño de pointer: 64-bit (vs. 32-bit en i386)
 */

ENTRY(efi_main_c)  /* Símbolo de entrada (punto de inicio) */

SECTIONS {
    /* Dirección de carga = 0 (UEFI se encarga de reubicación) */
    . = 0;

    /* Sección .text: código ejecutable */
    .text : {
        *(.text*)       /* Incluir todo código de todos los .o */
        *(.rodata*)     /* Datos de solo lectura (strings, constantes) */
    }

    /* Sección .data: datos inicializados globales */
    .data : {
        *(.data*)           /* Variables globales inicializadas */
    }

    /* Secciones dinámicas requeridas por UEFI/PE */
    .dynamic : {
        *(.dynamic)     /* Tabla de símbolos dinámicos */
    }

    .dynsym : {
        *(.dynsym)      /* Tabla de símbolos dinámicos */
    }

    .dynstr : {
        *(.dynstr)      /* String pool dinámico */
    }

    /* Secciones de relocalización (NEEDED para PE format) */
    .rela : {
        *(.rela*)       /* Entradas de relocalización ARM64 (.rela.* sections) */
    }

    .reloc : {
        *(.reloc)       /* Tabla de relocalización PE (generada por objcopy) */
    }

    /* Sección .bss: datos no inicializados (no ocupa espacio en archivo) */
    .bss : {
        *(.bss*)        /* Variables sin inicializar */
        *(COMMON)       /* Símbolos globales no inicializados */
    }
}

/* Fin del script */
