/*============================================================
 * boot.S - Punto de Entrada UEFI ARM64 (AArch64)
 * ============================================================
 *
 * Propósito:
 *   Archivo de ensamblador que define el punto de entrada (_start)
 *   para la aplicación UEFI ejecutándose en procesador ARM64/AArch64.
 *
 * Diferencias vs. x86-64:
 *   - Arquitectura: ARM64 (64-bit RISC) en lugar de x86-64 (CISC)
 *   - ISA: Conjunto diferente de instrucciones ARM
 *   - Registros: x0-x31 (registros de propósito general de 64-bit)
 *   - Calling Convention: ARM64 EABI (AArch64 UEFI Calling Convention)
 *   - No hay modo real: siempre 64-bit, protegido
 *
 * Punto de Entrada:
 *   UEFI carga esta imagen en memoria y salta a _start.
 *   Stack ya está inicializado por el firmware.
 *   Bootloader UEFI asegura que x0 = ImageHandle, x1 = SystemTable.
 *
 * Inicialización:
 *   1. Establecer frame pointer (x29) = 0 (sin stack frame padre)
 *   2. Saltar a efi_main_c (la función principal en C)
 *   3. (efi_main_c nunca retorna; si lo hace, CPU se queda en bucle)
 */

.section .text
.align 4
.global _start

_start:
    /* Establecer frame pointer x29 = 0 (sin frame padre) */
    mov x29, xzr        /* xzr = registro zero (siempre 0 en ARM64) */
    
    /* Saltar a efi_main_c (función principal del juego en C) */
    /* ARM64: equivalente a "jmp efi_main_c" en x86 */
    b efi_main_c
    
    /* Nunca llegamos aquí si efi_main_c se ejecuta correctamente */
    /* Si efi_main_c retorna, el flujo vuelve aquí y se queda indefinidamente */
