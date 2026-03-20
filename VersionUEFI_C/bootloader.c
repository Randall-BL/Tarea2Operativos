/* ============================================================
 * bootloader.c - UEFI Bootloader (versión x64)
 * ============================================================
 *
 * Propósito:
 *   Se carga como BOOTX64.EFI desde /EFI/BOOT/ del medio FAT32.
 *   Proporciona menú de inicio y punto de entrada al juego.
 *
 *
 * Flujo principal:
 *   1. efi_main(): punto de entrada UEFI
 *   2. Inicializar biblioteca gnu-efi
 *   3. Mostrar menú de inicio en loop
 *   4. Si usuario presiona ENTER: llamar a game_run()
 *   5. Si usuario presiona ESC: salir del bootloader
 */

#include <efi.h>
#include <efilib.h>

#include "juego.h"

/* ============================================================
 * wait_key()
 * 
 * Lee una tecla del usuario de forma bloqueante.
 *
 * EVENTO UEFI: Este código demuestra el modelo de eventos UEFI.
 * A diferencia de BIOS INT 0x16, UEFI usa WaitForEvent.
 *
 * Parámetros:
 *   st: System Table (acceso a ConIn y BootServices)
 *   key: puntero para devolver la tecla leída
 *
 * Flujo:
 *   1. Llamar WaitForEvent(1, &ConIn->WaitForKey, &index)
 *   2. Si éxito, leer la tecla con ReadKeyStroke
 *
 * Devuelve:
 *   EFI_STATUS: EFI_SUCCESS si se leyó tecla, error en otro caso
 */
static EFI_STATUS wait_key(EFI_SYSTEM_TABLE *st, EFI_INPUT_KEY *key) {
    EFI_STATUS status;
    UINTN index;

    /* EVENTO UEFI: Esperar a que ConIn->WaitForKey sea señalizado */
    status = uefi_call_wrapper(st->BootServices->WaitForEvent, 3,
                               1, &st->ConIn->WaitForKey, &index);
    if (EFI_ERROR(status)) {
        return status;
    }

    /* Leer la tecla que ahora está disponible */
    return uefi_call_wrapper(st->ConIn->ReadKeyStroke, 2, st->ConIn, key);
}

/* ============================================================
 * efi_main()
 * 
 * Punto de entrada del bootloader UEFI.
 *
 * Parámetros UEFI estándar:
 *   - ImageHandle: handle de la imagen ejecutándose
 *   - SystemTable: puntero a System Table (interfaz con UEFI firmware)
 *
 * Flujo:
 *   1. Inicializar biblioteca gnu-efi (InitializeLib)
 *   2. Loop infinito:
 *      a. Limpiar pantalla
 *      b. Mostrar menú
 *      c. Esperar tecla
 *      d. Si ENTER: ejecutar juego (game_run)
 *      e. Si ESC: salir del bootloader
 *   3. Mostrar mensaje de despedida
 *
 * Devuelve:
 *   EFI_STATUS: EFI_SUCCESS si salida normal
 */
EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_INPUT_KEY key;

    /* Inicializar gnu-efi library (obligatorio primero) */
    InitializeLib(ImageHandle, SystemTable);

    /* Loop principal: menú de inicio */
    while (1) {
        /* Limpiar pantalla antes de mostrar menú */
        uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
        
        /* Mostrar instrucciones y opciones en consola UEFI */
        Print(L"==============================\r\n");
        Print(L" UEFI BOOTLOADER EN C\r\n");
        Print(L"==============================\r\n\r\n");
        Print(L"ENTER: Iniciar juego\r\n");
        Print(L"ESC:   Salir\r\n\r\n");

        /* Esperar que usuario presione una tecla */
        status = wait_key(SystemTable, &key);
        if (EFI_ERROR(status)) {
            Print(L"Error leyendo teclado: %r\r\n", status);
            return status;
        }

        /* Procesar tecla presionada */
        if (key.UnicodeChar == CHAR_CARRIAGE_RETURN) {
            /* ENTER: Iniciar juego */
            status = game_run(SystemTable);
            if (EFI_ERROR(status)) {
                Print(L"Error en juego: %r\r\n", status);
                return status;
            }
            /* Después de que el juego retorna, volvemos al menú */
            continue;
        }

        if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
            /* ESC: Salir del bootloader */
            break;
        }
    }

    /* Mostrar mensaje de despedida */
    uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
    Print(L"Hasta luego.\r\n");
    return EFI_SUCCESS;
}
