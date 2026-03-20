#ifndef EFI_MIN_H
#define EFI_MIN_H

/* ============================================================
 * efi_min.h - UEFI Type Definitions (Minimal)
 * ============================================================
 *
 * Propósito:
 *   Define los tipos UEFI fundamentales necesarios para compilar
 *   aplicaciones UEFI que no pueden usar gnu-efi.
 *   
 *   Útil para:
 *   - Compilación cross-compile de AArch64 sin librerías estándar
 *   - Sistemas embebidos o ROMs que requieren maximal portabilidad
 *   - Educación: entender la estructura UEFI desde cero
 *
 * Contenido:
 *   1. Tipos UEFI base (BOOLEAN, UINT*, INT*, VOID, etc.)
 *   2. Estructuras de interfaz (protocolo de teclado, video, etc.)
 *   3. Constantes (chequeo de errores, event types, etc.)
 *   4. Callbacks y function pointers
 *   5. GUIDs y descriptores de protocolo
 *
 * Nota: Esta es una implementación SIMPLIFICADA. 
 *       La especificación UEFI publica tipos más complejos.
 */

/* ============================================================
 * Tipos Base UEFI
 * 
 * Equivalentes a tipos C estándar pero con nombres UEFI:
 * - UINT8, UINT16, UINT32, UINT64: enteros sin signo
 * - INT16, INT32, INT64: enteros con signo
 * - UINTN: entero sin signo del tamaño de un pointer (32 o 64 bit)
 * - VOID *: puntero genérico
 * - BOOLEAN: tipo booleano (0 = FALSE, 1 = TRUE)
 */
typedef unsigned char       BOOLEAN;
typedef unsigned char       UINT8;
typedef unsigned short      UINT16;
typedef unsigned int        UINT32;
typedef unsigned long long  UINT64;
typedef __UINTPTR_TYPE__    UINTN;       /* Tamaño = sizeof(void*) */
typedef signed short        INT16;
typedef signed int          INT32;
typedef long long           INT64;
typedef void                VOID;
typedef void               *EFI_HANDLE;  /* Identificador opaco de entidad UEFI */
typedef UINT16              CHAR16;      /* Carácter Unicode de 16-bit */
typedef char                CHAR8;       /* Carácter ASCII de 8-bit */

/* ============================================================
 * Tipos de Retorno y Eventos
 */
typedef UINT64              EFI_STATUS;  /* Tipo de retorno UEFI (64-bit) */
typedef VOID               *EFI_EVENT;   /* Identificador de evento UEFI */
typedef UINTN               EFI_TPL;     /* Task Priority Level */

/* ============================================================
 * Macros Convención de Llamada, Statusy Eventos
 */

#define EFIAPI  /* Empty macro: AArch64 EABI no requiere decoración como __stdcall */

/* Puntero a función callback para eventos UEFI */
typedef void (EFIAPI *EFI_EVENT_NOTIFY)(EFI_EVENT Event, VOID *Context);

/* Códigos de retorno EFI_STATUS más comunes */
#define EFI_SUCCESS ((EFI_STATUS)0)                         /* Operación exitosa */
#define EFI_ABORTED ((EFI_STATUS)0x8000000000000005ULL)     /* Operación abortada */
#define EFI_NOT_READY ((EFI_STATUS)0x8000000000000006ULL)   /* Dispositivo no listo (ej. no hay tecla) */
#define EFI_ERROR(Status) (((INT64)(Status)) < 0)           /* Macro: devuelve TRUE si Status es error */

/* Constantes para CreatEvent() */
#define EVT_TIMER         0x80000000U    /* Evento de timer (periódico o one-shot) */
#define EVT_NOTIFY_SIGNAL 0x00000200U    /* Event incluye callback de señalización */

/* Task Priority Level para CreateEvent */
#define TPL_CALLBACK 8                   /* Level para callbacks de eventos */

/* Constantes para SetTimer() */
#define TimerCancel   0                  /* Detener/cancelar timer */
#define TimerPeriodic 1                  /* Timer periódico (se repite) */
#define TimerRelative 2                  /* Timer relativo (one-shot) */

typedef struct {
    UINT64 Signature;       /* Firma de la tabla (ej. 0x5652974541424955) */
    UINT32 Revision;        /* Versión de especificación */
    UINT32 HeaderSize;      /* Tamaño del header */
    UINT32 CRC32;           /* CRC32 para validación */
    UINT32 Reserved;        /* Reservado */
} EFI_TABLE_HEADER;

typedef struct {
    UINT16 Year;            /* 1900...9999 */
    UINT8 Month;            /* 1...12 */
    UINT8 Day;              /* 1...31 */
    UINT8 Hour;             /* 0...23 */
    UINT8 Minute;           /* 0...59 */
    UINT8 Second;           /* 0...59 */
    UINT8 Pad1;
    UINT32 Nanosecond;      /* 0...999,999,999 */
    INT16 TimeZone;         /* Offset de UTC en minutos */
    UINT8 Daylight;
    UINT8 Pad2;
} EFI_TIME;

typedef struct {
    UINT32 Data1;
    UINT16 Data2;
    UINT16 Data3;
    UINT8 Data4[8];
} EFI_GUID;

typedef struct {
    UINT16 ScanCode;        /* Código para flechas, ESC, etc. */
    CHAR16 UnicodeChar;     /* Carácter Unicode o ASCII */
} EFI_INPUT_KEY;

enum {
    SCAN_UP    = 1,         /* Flecha arriba */
    SCAN_DOWN  = 2,         /* Flecha abajo */
    SCAN_RIGHT = 3,         /* Flecha derecha */
    SCAN_LEFT  = 4,         /* Flecha izquierda */
    SCAN_ESC   = 23         /* Tecla ESC */
};

typedef struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL EFI_SIMPLE_TEXT_INPUT_PROTOCOL;
typedef struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
typedef struct _EFI_BOOT_SERVICES EFI_BOOT_SERVICES;
typedef struct _EFI_RUNTIME_SERVICES EFI_RUNTIME_SERVICES;
typedef struct _EFI_GRAPHICS_OUTPUT_PROTOCOL EFI_GRAPHICS_OUTPUT_PROTOCOL;

typedef EFI_STATUS (EFIAPI *EFI_INPUT_READ_KEY)(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *, EFI_INPUT_KEY *);
typedef EFI_STATUS (EFIAPI *EFI_TEXT_STRING)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *, CHAR16 *);
typedef EFI_STATUS (EFIAPI *EFI_TEXT_CLEAR_SCREEN)(EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *);
typedef EFI_STATUS (EFIAPI *EFI_WAIT_FOR_EVENT)(UINTN, EFI_EVENT *, UINTN *);
typedef EFI_STATUS (EFIAPI *EFI_STALL)(UINTN);
typedef EFI_STATUS (EFIAPI *EFI_LOCATE_PROTOCOL)(EFI_GUID *, VOID *, VOID **);
typedef EFI_STATUS (EFIAPI *EFI_GET_TIME)(EFI_TIME *, VOID *);
typedef EFI_STATUS (EFIAPI *EFI_CREATE_EVENT)(UINT32, EFI_TPL, EFI_EVENT_NOTIFY, VOID *, EFI_EVENT *);
typedef EFI_STATUS (EFIAPI *EFI_SET_TIMER)(EFI_EVENT, UINT32, UINT64);
typedef EFI_STATUS (EFIAPI *EFI_CLOSE_EVENT)(EFI_EVENT);

struct _EFI_SIMPLE_TEXT_INPUT_PROTOCOL {
    VOID *Reset;
    EFI_INPUT_READ_KEY ReadKeyStroke;
    EFI_EVENT WaitForKey;
};

struct _EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    VOID *Reset;
    EFI_TEXT_STRING OutputString;
    VOID *TestString;
    VOID *QueryMode;
    VOID *SetMode;
    VOID *SetAttribute;
    EFI_TEXT_CLEAR_SCREEN ClearScreen;
    VOID *SetCursorPosition;
    VOID *EnableCursor;
    VOID *Mode;
};

struct _EFI_RUNTIME_SERVICES {
    EFI_TABLE_HEADER Hdr;
    EFI_GET_TIME GetTime;
};

struct _EFI_BOOT_SERVICES {
    EFI_TABLE_HEADER Hdr;
    VOID *RaiseTPL;
    VOID *RestoreTPL;
    VOID *AllocatePages;
    VOID *FreePages;
    VOID *GetMemoryMap;
    VOID *AllocatePool;
    VOID *FreePool;
    EFI_CREATE_EVENT CreateEvent;
    EFI_SET_TIMER SetTimer;
    EFI_WAIT_FOR_EVENT WaitForEvent;
    VOID *SignalEvent;
    EFI_CLOSE_EVENT CloseEvent;
    VOID *CheckEvent;
    VOID *InstallProtocolInterface;
    VOID *ReinstallProtocolInterface;
    VOID *UninstallProtocolInterface;
    VOID *HandleProtocol;
    VOID *Reserved;
    VOID *RegisterProtocolNotify;
    VOID *LocateHandle;
    VOID *LocateDevicePath;
    VOID *InstallConfigurationTable;
    VOID *LoadImage;
    VOID *StartImage;
    VOID *Exit;
    VOID *UnloadImage;
    VOID *ExitBootServices;
    VOID *GetNextMonotonicCount;
    EFI_STALL Stall;
    VOID *SetWatchdogTimer;
    VOID *ConnectController;
    VOID *DisconnectController;
    VOID *OpenProtocol;
    VOID *CloseProtocol;
    VOID *OpenProtocolInformation;
    VOID *ProtocolsPerHandle;
    VOID *LocateHandleBuffer;
    EFI_LOCATE_PROTOCOL LocateProtocol;
};

typedef struct {
    UINT32 Version;
    UINT32 HorizontalResolution;
    UINT32 VerticalResolution;
    UINT32 PixelFormat;
    UINT32 PixelInformation[4];
    UINT32 PixelsPerScanLine;
} EFI_GRAPHICS_OUTPUT_MODE_INFORMATION;

typedef struct {
    UINT32 MaxMode;
    UINT32 Mode;
    EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *Info;
    UINTN SizeOfInfo;
    UINT64 FrameBufferBase;
    UINTN FrameBufferSize;
} EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE;

struct _EFI_GRAPHICS_OUTPUT_PROTOCOL {
    VOID *QueryMode;
    VOID *SetMode;
    VOID *Blt;
    EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE *Mode;
};

typedef struct {
    EFI_TABLE_HEADER Hdr;
    CHAR16 *FirmwareVendor;
    UINT32 FirmwareRevision;
    EFI_HANDLE ConsoleInHandle;
    EFI_SIMPLE_TEXT_INPUT_PROTOCOL *ConIn;
    EFI_HANDLE ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;
    EFI_HANDLE StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;
    EFI_RUNTIME_SERVICES *RuntimeServices;
    EFI_BOOT_SERVICES *BootServices;
    UINTN NumberOfTableEntries;
    VOID *ConfigurationTable;
} EFI_SYSTEM_TABLE;

#define EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID \
    {0x9042A9DE, 0x23DC, 0x4A38, {0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A}}

#endif
