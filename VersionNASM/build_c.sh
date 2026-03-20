#!/bin/bash
# ============================================================
# build_c.sh - Script de BUILD para BIOS Legacy x86 (VersionNASM)
# ============================================================
#
# Propósito:
#   Automatizar la compilación completa de:
#   - boot.asm (bootloader en NASM → 512 bytes)
#   - juego.c (programa principal en C de 16-bit → juego.bin)
#   - Genera imagen de disco (image.bin o bios.img) para USB/QEMU
#
# Dependencias de sistema:
#   - nasm : ensamblador x86 (para boot.asm)
#   - gcc : compilador C (para juego.c con opción -m16)
#   - ld : linker GNU (enlazador de objetos)
#   - objcopy : utilidad de GNU binutils (conversión de formatos)
#   - dd : herramienta de copia de datos en imagen binaria
#   - qemu-system-x86_64 : emulador x86 (opcional para --test)
#   - sudo : elevación de privilegios (opcional para --flash)
#
# Flujo de compilación:
#   1. Compilar juego.c → juego.o (gcc -m16)
#   2. Enlazar juego.o → juego.elf (ld con ruta linker_game.ld)
#   3. Convertir a binario → juego.bin (objcopy -O binary)
#   4. Calcular sectores necesarios (GAME_SECTS = ceil(size/512))
#   5. Compilar boot.asm → boot.bin con GAME_SECTS (nasm -D)
#   6. Concatenar: boot.bin + juego.bin → game.bin (cat)
#   7. Crear imagen de disco de 64MB (dd)
#   8. Grabar game.bin en la imagen en offset 0 (dd conv=notrunc)
#   9. Si --test, ejecutar en QEMU
#   10. Si --flash /dev/sdX, grabar en USB
#
# Mapa de memoria final:
#   Sector 0 (byte 0-511):     Bootloader (boot.bin)
#   Sector 1 (byte 512-...):   Juego (juego.bin) hasta GAME_SECTS
#   Resto:                     Espacio libre en imagen

set -e  # Salir si cualquier comando falla (exit status != 0)

set -e  # Salir si cualquier comando falla (exit status != 0)

# ---- Definir rutas de archivos y directorios ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Directorio donde está este script
BUILD_DIR="$SCRIPT_DIR/build"                               # Directorio de compilación
BOOT_BIN="$BUILD_DIR/boot.bin"                              # Bootloader compilado (512 bytes)
GAME_O="$BUILD_DIR/juego.o"                                 # Objeto juego.c
GAME_ELF="$BUILD_DIR/juego.elf"                             # ELF intermedio
GAME_BIN="$BUILD_DIR/juego.bin"                             # Binario del juego (puro)
DISK_BIN="$BUILD_DIR/game.bin"                              # boot + juego concatenados
IMG_FILE="$BUILD_DIR/bios.img"                              # Imagen final (64 MB)
IMG_MB=64                                                   # Tamaño de imagen en MB

# ---- ArgumentosOpción de línea de comandos ----
ARG="${1:-}"         # Argumento 1: "" (build), "--test" (ejecutar), o "--flash" (grabar USB)
USB_DEV="${2:-}"     # Argumento 2: /dev/sdX si ARG="--flash"

# ---- Verificar que las herramientas requeridas existan ----
for t in nasm gcc ld objcopy dd; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ERROR: falta '$t'"
    exit 1
  fi
done

# ---- Si se solicita --test, verificar qemu ----
if [ "$ARG" = "--test" ] && ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: falta qemu-system-x86_64"
  exit 1
fi

# ---- Si se solicita --flash, verificar que se pasó dispositivo ----
if [ "$ARG" = "--flash" ] && [ -z "$USB_DEV" ]; then
  echo "Uso: bash build_c.sh --flash /dev/sdX"
  exit 1
fi

# ---- Limpiar compilación anterior ----
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/5] Compilando juego.c (16-bit real mode)..."
# ---- Compilar juego.c a objeto (.o) con flags específicos para modo real ----
# Explicación de flags de gcc:
#   -m16                : compilar como código x86 de 16-bit (modo real)
#   -ffreestanding      : No asumir disponibilidad de libc (entorno freestanding)
#   -fno-pic            : No generar código independiente de posición (necesario para BIOS real)
#   -fno-stack-protector: Desactivar protecciones de buffer (no disponibles en modo real)
#   -fno-builtin        : No usar funciones built-in de gcc (ej. memcpy optimizado)
#   -fno-asynchronous-unwind-tables : Sin tablas de desenredo de pila
#   -fno-unwind-tables  : Sin tablas de dinámica
#   -fno-omit-frame-pointer : Mantener frame pointer (depuración)
#   -Os                 : Optimizar para tamaño (importan BIOS legacy, max ~8.5KB)
#   -Wall -Wextra       : Warnings estrictos
#   -nostdlib           : No enlazar contra libc
#   -c                  : Compilar, no enlazar
#   -o                  : Archivo de salida
gcc -m16 -ffreestanding -fno-pic -fno-stack-protector -fno-builtin \
    -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-omit-frame-pointer \
    -Os -Wall -Wextra -nostdlib -c "$SCRIPT_DIR/juego.c" -o "$GAME_O"

# ---- Enlazar objeto → ELF con linker script ----
ld -m elf_i386 -T "$SCRIPT_DIR/linker_game.ld" -nostdlib "$GAME_O" -o "$GAME_ELF"

# ---- Convertir ELF → binario puro ----
objcopy -O binary "$GAME_ELF" "$GAME_BIN"

# ---- Calcular número de sectores necesarios (512 bytes/sector) ----
GAME_SIZE=$(wc -c < "$GAME_BIN")                        # Tamaño en bytes
GAME_SECTS=$(( (GAME_SIZE + 511) / 512 ))              # Redondear hacia arriba

# ---- Validar tamaño (máx 17 sectores para BIOS legacy CHS) ----
if [ "$GAME_SECTS" -gt 17 ]; then
  echo "ERROR: juego.bin ocupa $GAME_SECTS sectores (>17)."
  echo "       El bootloader CHS actual lee desde sector 2 en cilindro 0/cabeza 0."
  echo "       Reduce el tamaño del juego para BIOS legacy."
  exit 1
fi

echo "      juego.bin = $GAME_SIZE bytes ($GAME_SECTS sectores)"

echo "[2/5] Compilando bootloader (boot.asm) con GAME_SECTS=$GAME_SECTS ..."
# ---- Compilar boot.asm con NASM pasando GAME_SECTS como constante ----
# -f bin       : Generar archivo binario puro (sin headers ELF/COFF)
# -D GAME_SECTS=N : Pasar macro NASM con número de sectores
# -o           : Archivo de salida
nasm -f bin -D GAME_SECTS=$GAME_SECTS "$SCRIPT_DIR/boot.asm" -o "$BOOT_BIN"
BOOT_SIZE=$(wc -c < "$BOOT_BIN")
if [ "$BOOT_SIZE" -ne 512 ]; then
  echo "ERROR: boot.bin debe ser 512 bytes y tiene $BOOT_SIZE"
  exit 1
fi

echo "[3/5] Uniendo boot + juego ..."
# ---- Concatenar bootloader + juego en un archivo ----
# Este archivo será escrito en los primeros sectores de la imagen
cat "$BOOT_BIN" "$GAME_BIN" > "$DISK_BIN"
DISK_SIZE=$(wc -c < "$DISK_BIN")
echo "      game.bin = $DISK_SIZE bytes"

echo "[4/5] Creando imagen raw ${IMG_MB}MB para USB ..."
# ---- Crear imagen en blanco de 64 MB (llenar con 0s) ----
# if=/dev/zero : lectura desde generador de ceros del kernel
# of=...       : archivo de salida (imagen)
# bs=1M        : tamaño de bloque = 1 MB
# count=...    : número de bloques (64)
# status=none  : sin mostrar progreso
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none

# ---- Escribir boot + juego en la imagen en offset 0 ----
# conv=notrunc : No truncar archivo de salida (preservar resto)
dd if="$DISK_BIN" of="$IMG_FILE" conv=notrunc status=none

echo "      Imagen lista: $IMG_FILE"

if [ "$ARG" = "--test" ]; then
  # ---- Opción --test: ejecutar en QEMU (emulador x86) ----
  # Parámetros de QEMU:
  #   -drive file=...,format=raw,if=ide,index=0,media=disk : usar imagen como disco IDE
  #   -m 256M : memoria RAM
  #   -display sdl : ventana gráfica SDL (no requiere X11 en algunos sistemas)
  echo "[5/5] Ejecutando en QEMU (BIOS legacy) ..."
  qemu-system-x86_64 -drive file="$IMG_FILE",format=raw,if=ide,index=0,media=disk -m 256M -display sdl
elif [ "$ARG" = "--flash" ]; then
  # ---- Opción --flash: grabar imagen en USB real ----
  # Validar que el dispositivo existe y es de bloque
  if [ ! -b "$USB_DEV" ]; then
    echo "ERROR: '$USB_DEV' no es un dispositivo de bloque válido"
    exit 1
  fi

  # Advertencia al usuario
  echo "ADVERTENCIA: se borrará TODO en $USB_DEV"
  echo "Presiona Enter para continuar o Ctrl+C para cancelar"
  read -r

  # Grabar imagen con privilegios root (si es necesario)
  if [ "$EUID" -eq 0 ]; then
    # Ya somos root
    dd if="$IMG_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync
  else
    # Necesitamos sudo
    if ! command -v sudo >/dev/null 2>&1; then
      echo "ERROR: se requieren permisos de administrador para escribir en $USB_DEV"
      echo "       Instala sudo o ejecuta este comando como root."
      exit 1
    fi
    sudo dd if="$IMG_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync
  fi
  echo "Listo."
else
  # ---- Sin argumento o argumento desconocido: mostrar uso ----
  echo "Para probar en QEMU: bash build_c.sh --test"
  echo "Para grabar USB:     bash build_c.sh --flash /dev/sdX"
fi
