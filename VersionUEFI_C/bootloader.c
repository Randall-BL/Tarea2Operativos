#include <efi.h>
#include <efilib.h>

#include "juego.h"

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

EFI_STATUS efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_INPUT_KEY key;

    InitializeLib(ImageHandle, SystemTable);

    while (1) {
        uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
        Print(L"==============================\r\n");
        Print(L" UEFI BOOTLOADER EN C\r\n");
        Print(L"==============================\r\n\r\n");
        Print(L"ENTER: Iniciar juego\r\n");
        Print(L"ESC:   Salir\r\n\r\n");

        status = wait_key(SystemTable, &key);
        if (EFI_ERROR(status)) {
            Print(L"Error leyendo teclado: %r\r\n", status);
            return status;
        }

        if (key.UnicodeChar == CHAR_CARRIAGE_RETURN) {
            status = game_run(SystemTable);
            if (EFI_ERROR(status)) {
                Print(L"Error en juego: %r\r\n", status);
                return status;
            }
            continue;
        }

        if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
            break;
        }
    }

    uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
    Print(L"Hasta luego.\r\n");
    return EFI_SUCCESS;
}
