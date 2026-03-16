#!/bin/bash
set -e

# ============================================================
# build_c.sh - BIOS legacy (boot.asm + juego.c)
#
# Dependencias:
#   sudo apt install nasm gcc binutils qemu-system-x86 mtools
#
# Uso:
#   bash build_c.sh
#   bash build_c.sh --test
#   bash build_c.sh --flash /dev/sdX
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
BOOT_BIN="$BUILD_DIR/boot.bin"
GAME_O="$BUILD_DIR/juego.o"
GAME_ELF="$BUILD_DIR/juego.elf"
GAME_BIN="$BUILD_DIR/juego.bin"
DISK_BIN="$BUILD_DIR/game.bin"
IMG_FILE="$BUILD_DIR/bios.img"
IMG_MB=64

ARG="${1:-}"
USB_DEV="${2:-}"

for t in nasm gcc ld objcopy dd; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ERROR: falta '$t'"
    exit 1
  fi
done

if [ "$ARG" = "--test" ] && ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: falta qemu-system-x86_64"
  exit 1
fi

if [ "$ARG" = "--flash" ] && [ -z "$USB_DEV" ]; then
  echo "Uso: bash build_c.sh --flash /dev/sdX"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/5] Compilando juego.c (16-bit real mode)..."
gcc -m16 -ffreestanding -fno-pic -fno-stack-protector -fno-builtin \
    -fno-asynchronous-unwind-tables -fno-unwind-tables -fno-omit-frame-pointer \
    -Os -Wall -Wextra -nostdlib -c "$SCRIPT_DIR/juego.c" -o "$GAME_O"

ld -m elf_i386 -T "$SCRIPT_DIR/linker_game.ld" -nostdlib "$GAME_O" -o "$GAME_ELF"
objcopy -O binary "$GAME_ELF" "$GAME_BIN"

GAME_SIZE=$(wc -c < "$GAME_BIN")
GAME_SECTS=$(( (GAME_SIZE + 511) / 512 ))

if [ "$GAME_SECTS" -gt 17 ]; then
  echo "ERROR: juego.bin ocupa $GAME_SECTS sectores (>17)."
  echo "       El bootloader CHS actual lee desde sector 2 en cilindro 0/cabeza 0."
  echo "       Reduce el tamaño del juego para BIOS legacy."
  exit 1
fi

echo "      juego.bin = $GAME_SIZE bytes ($GAME_SECTS sectores)"

echo "[2/5] Compilando bootloader (boot.asm) con GAME_SECTS=$GAME_SECTS ..."
nasm -f bin -D GAME_SECTS=$GAME_SECTS "$SCRIPT_DIR/boot.asm" -o "$BOOT_BIN"
BOOT_SIZE=$(wc -c < "$BOOT_BIN")
if [ "$BOOT_SIZE" -ne 512 ]; then
  echo "ERROR: boot.bin debe ser 512 bytes y tiene $BOOT_SIZE"
  exit 1
fi

echo "[3/5] Uniendo boot + juego ..."
cat "$BOOT_BIN" "$GAME_BIN" > "$DISK_BIN"
DISK_SIZE=$(wc -c < "$DISK_BIN")
echo "      game.bin = $DISK_SIZE bytes"

echo "[4/5] Creando imagen raw ${IMG_MB}MB para USB ..."
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none
dd if="$DISK_BIN" of="$IMG_FILE" conv=notrunc status=none

echo "      Imagen lista: $IMG_FILE"

if [ "$ARG" = "--test" ]; then
  echo "[5/5] Ejecutando en QEMU (BIOS legacy) ..."
  qemu-system-x86_64 -drive file="$IMG_FILE",format=raw,if=floppy -m 256M -display sdl
elif [ "$ARG" = "--flash" ]; then
  if [ ! -b "$USB_DEV" ]; then
    echo "ERROR: '$USB_DEV' no es un dispositivo de bloque válido"
    exit 1
  fi

  echo "ADVERTENCIA: se borrará TODO en $USB_DEV"
  echo "Presiona Enter para continuar o Ctrl+C para cancelar"
  read -r
  dd if="$IMG_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync
  echo "Listo."
else
  echo "Para probar en QEMU: bash build_c.sh --test"
  echo "Para grabar USB:     bash build_c.sh --flash /dev/sdX"
fi
