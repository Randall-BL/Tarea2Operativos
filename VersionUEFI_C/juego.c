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

static void put_pixel(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop, UINT32 x, UINT32 y, UINT32 color) {
    UINT32 width = gop->Mode->Info->HorizontalResolution;
    UINT32 height = gop->Mode->Info->VerticalResolution;
    UINT32 ppsl = gop->Mode->Info->PixelsPerScanLine;
    UINT32 *fb = (UINT32 *)(UINTN)gop->Mode->FrameBufferBase;

    if (x >= width || y >= height) {
        return;
    }

    fb[(UINTN)y * ppsl + x] = color;
}

static void fill_screen(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop, UINT32 color) {
    UINT32 width = gop->Mode->Info->HorizontalResolution;
    UINT32 height = gop->Mode->Info->VerticalResolution;
    UINT32 ppsl = gop->Mode->Info->PixelsPerScanLine;
    UINT32 *fb = (UINT32 *)(UINTN)gop->Mode->FrameBufferBase;

    for (UINT32 y = 0; y < height; ++y) {
        for (UINT32 x = 0; x < width; ++x) {
            fb[(UINTN)y * ppsl + x] = color;
        }
    }
}

static void draw_glyph_5x7(EFI_GRAPHICS_OUTPUT_PROTOCOL *gop,
                           UINT32 x, UINT32 y,
                           const UINT8 rows[7], UINT32 scale,
                           UINT32 color) {
    for (UINT32 row = 0; row < 7; ++row) {
        UINT8 bits = rows[row];
        for (UINT32 col = 0; col < 5; ++col) {
            if ((bits >> (4 - col)) & 1) {
                for (UINT32 dy = 0; dy < scale; ++dy) {
                    for (UINT32 dx = 0; dx < scale; ++dx) {
                        put_pixel(gop,
                                  x + col * scale + dx,
                                  y + row * scale + dy,
                                  color);
                    }
                }
            }
        }
    }
}

EFI_STATUS game_run(EFI_SYSTEM_TABLE *SystemTable) {
    EFI_STATUS status;
    EFI_INPUT_KEY key;
    EFI_GRAPHICS_OUTPUT_PROTOCOL *gop = NULL;
    EFI_GUID gop_guid = EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;

    static const UINT8 H[7] = {0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11};
    static const UINT8 O[7] = {0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E};
    static const UINT8 L[7] = {0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F};
    static const UINT8 A[7] = {0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11};

    status = uefi_call_wrapper(SystemTable->BootServices->LocateProtocol, 3,
                               &gop_guid, NULL, (void **)&gop);
    if (EFI_ERROR(status) || gop == NULL) {
        uefi_call_wrapper(SystemTable->ConOut->ClearScreen, 1, SystemTable->ConOut);
        Print(L"No se pudo iniciar GOP. Presiona una tecla...\r\n");
        wait_key(SystemTable, &key);
        return EFI_SUCCESS;
    }

    UINT32 width = gop->Mode->Info->HorizontalResolution;
    UINT32 height = gop->Mode->Info->VerticalResolution;

    UINT32 black = 0x00000000;
    UINT32 white = 0x00FFFFFF;

    fill_screen(gop, black);

    UINT32 scale = 8;
    UINT32 char_w = 5 * scale;
    UINT32 char_h = 7 * scale;
    UINT32 spacing = 1 * scale;
    UINT32 total_w = char_w * 4 + spacing * 3;
    UINT32 start_x = (width > total_w) ? (width - total_w) / 2 : 0;
    UINT32 start_y = (height > char_h) ? (height - char_h) / 2 : 0;

    draw_glyph_5x7(gop, start_x + (char_w + spacing) * 0, start_y, H, scale, white);
    draw_glyph_5x7(gop, start_x + (char_w + spacing) * 1, start_y, O, scale, white);
    draw_glyph_5x7(gop, start_x + (char_w + spacing) * 2, start_y, L, scale, white);
    draw_glyph_5x7(gop, start_x + (char_w + spacing) * 3, start_y, A, scale, white);

    wait_key(SystemTable, &key);
    return EFI_SUCCESS;
}
