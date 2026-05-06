#ifndef JUEGO_H
#define JUEGO_H

/* ============================================================
 * juego.h - Interfaz pública del módulo de juego
 * ============================================================
 *
 * Propósito:
 *   Define la interfaz entre bootloader.c (programa principal UEFI)
 *   y juego.c (lógica del juego).
 *
 * Depend encias:
 *   - #include <efi.h> : tipos UEFI estándar
 */

#include <efi.h>

/* ============================================================
 * game_run()
 * ============================================================
 *
 * Propósito:
 *   Ejecuta el juego en el entorno UEFI x64.
 *   Punto de entrada desde el bootloader cuando usuario presiona ENTER.
 *
 * Parámetros:
 *   SystemTable: tabla de servicios UEFI (acceso a ConIn, ConOut, BootServices, etc.)
 *
 * Devuelve:
 *   EFI_STATUS:
 *   - EFI_SUCCESS: juego ejecutado correctamente, usuario presionó ESC para salir
 *   - Otros códigos: error (ej. GOP no disponible, fallo de eventos, etc.)
 *
 * Interacciones UEFI:
 *   - ConIn->WaitForKey: evento de teclado
 *   - BootServices->CreateEvent: crear evento de timer periódico
 *   - BootServices->SetTimer: configurar timer
 *   - BootServices->WaitForEvent: multiplexar eventos (teclado + timer)
 *   - Graphics Output Protocol (GOP): acceso a framebuffer gráfico
 */
EFI_STATUS game_run(EFI_SYSTEM_TABLE *SystemTable);

#endif
