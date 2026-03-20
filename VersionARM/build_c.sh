#!/bin/bash
set -e

# ============================================================
# build_c.sh - ARM64 UEFI (entrada directa en C)
#
# Nota: en ARM no existe BIOS legacy x86, así que esta versión
# genera una aplicación UEFI AArch64: /EFI/BOOT/BOOTAA64.EFI
#
# Toolchains soportados:
#   1) clang + ld.lld + llvm-objcopy
#   2) aarch64-linux-gnu-gcc + aarch64-linux-gnu-ld + aarch64-linux-gnu-objcopy
#
# Uso:
#   bash build_c.sh
#   bash build_c.sh --test
#   bash build_c.sh --flash /dev/sdX
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
ELF_FILE="$BUILD_DIR/BOOTAA64.elf"
EFI_FILE="$BUILD_DIR/BOOTAA64.EFI"
IMG_FILE="$BUILD_DIR/uefi_arm.img"
IMG_MB=64
ARG="${1:-}"
USB_DEV="${2:-}"

CC=""
LD=""
OBJCOPY=""
TARGET_FLAG=""
LINK_MODE=""

if command -v clang >/dev/null 2>&1 && command -v lld-link >/dev/null 2>&1; then
  CC="clang"
  LD="lld-link"
  TARGET_FLAG="--target=aarch64-unknown-windows"
  LINK_MODE="lld-link"
elif command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 && command -v aarch64-linux-gnu-ld >/dev/null 2>&1 && command -v aarch64-linux-gnu-objcopy >/dev/null 2>&1; then
  CC="aarch64-linux-gnu-gcc"
  LD="aarch64-linux-gnu-ld"
  OBJCOPY="aarch64-linux-gnu-objcopy"
  TARGET_FLAG=""
  LINK_MODE="gnu-elf"
else
  echo "ERROR: no se encontró toolchain AArch64 compatible."
  echo "Instala una de estas opciones:"
  echo "  sudo apt install clang lld llvm"
  echo "  o"
  echo "  sudo apt install gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu"
  exit 1
fi

for t in mformat mmd mcopy mdir; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ERROR: falta '$t' (instala mtools)"
    exit 1
  fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/4] Compilando ARM64 UEFI ..."
$CC $TARGET_FLAG -ffreestanding -fshort-wchar -fno-stack-protector -fno-pic -nostdlib -O2 -Wall -Wextra -c "$SCRIPT_DIR/juego.c" -o "$BUILD_DIR/juego.o"

if [ "$LINK_MODE" = "lld-link" ]; then
  $LD /nodefaultlib /entry:efi_main_c /subsystem:efi_application /machine:arm64 \
      /out:"$EFI_FILE" "$BUILD_DIR/juego.o"
else
  $LD -nostdlib -T "$SCRIPT_DIR/linker.ld" "$BUILD_DIR/juego.o" -o "$ELF_FILE"
  $OBJCOPY -O efi-app-aarch64 "$ELF_FILE" "$EFI_FILE"
fi

echo "      BOOTAA64.EFI = $(wc -c < "$EFI_FILE") bytes"

echo "[2/4] Creando imagen FAT32 ..."
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none
mformat -i "$IMG_FILE" -h 64 -s 32 -F ::

echo "[3/4] Copiando /EFI/BOOT/BOOTAA64.EFI ..."
mmd -i "$IMG_FILE" ::/EFI
mmd -i "$IMG_FILE" ::/EFI/BOOT
mcopy -i "$IMG_FILE" "$EFI_FILE" ::/EFI/BOOT/BOOTAA64.EFI
mdir -i "$IMG_FILE" ::/EFI/BOOT/

echo
echo "Imagen lista: $IMG_FILE"

if [ "$ARG" = "--test" ]; then
  if ! command -v qemu-system-aarch64 >/dev/null 2>&1; then
    echo "ERROR: falta qemu-system-aarch64"
    exit 1
  fi

  FIRMWARE_CODE=""
  FIRMWARE_VARS=""
  FIRMWARE_SINGLE=""

  for CANDIDATE in \
    /usr/share/AAVMF/AAVMF_CODE.fd \
    /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw; do
    if [ -f "$CANDIDATE" ]; then
      FIRMWARE_CODE="$CANDIDATE"
      break
    fi
  done

  for CANDIDATE in \
    /usr/share/AAVMF/AAVMF_VARS.fd \
    /usr/share/edk2/aarch64/vars-template-pflash.raw; do
    if [ -f "$CANDIDATE" ]; then
      FIRMWARE_VARS="$CANDIDATE"
      break
    fi
  done

  for CANDIDATE in \
    /usr/share/qemu-efi-aarch64/QEMU_EFI.fd \
    /usr/share/edk2/aarch64/QEMU_EFI.fd; do
    if [ -f "$CANDIDATE" ]; then
      FIRMWARE_SINGLE="$CANDIDATE"
      break
    fi
  done

  if [ -z "$FIRMWARE_CODE" ] && [ -z "$FIRMWARE_SINGLE" ]; then
      echo "ERROR: no se encontró firmware UEFI AArch64 (AAVMF/QEMU_EFI)."
      echo "Instala por ejemplo: qemu-efi-aarch64 o aavmf"
      exit 1
  fi

  echo "[4/4] Ejecutando en QEMU AArch64 ..."
  if [ -n "$FIRMWARE_CODE" ] && [ -n "$FIRMWARE_VARS" ]; then
    cp "$FIRMWARE_VARS" "$BUILD_DIR/AAVMF_VARS.fd"
    qemu-system-aarch64 \
      -M virt \
      -cpu cortex-a72 \
      -m 512 \
      -drive if=pflash,format=raw,readonly=on,file="$FIRMWARE_CODE" \
      -drive if=pflash,format=raw,file="$BUILD_DIR/AAVMF_VARS.fd" \
      -device ramfb \
      -device qemu-xhci \
      -device usb-kbd \
      -drive if=none,file="$IMG_FILE",format=raw,id=hd \
      -device virtio-blk-pci,drive=hd \
      -net none \
      -display sdl
  else
    qemu-system-aarch64 \
      -M virt \
      -cpu cortex-a72 \
      -m 512 \
      -bios "$FIRMWARE_SINGLE" \
      -device ramfb \
      -device qemu-xhci \
      -device usb-kbd \
      -drive if=none,file="$IMG_FILE",format=raw,id=hd \
      -device virtio-blk-pci,drive=hd \
      -net none \
      -display sdl
  fi
elif [ "$ARG" = "--flash" ]; then
  if [ -z "$USB_DEV" ] || [ ! -b "$USB_DEV" ]; then
    echo "Uso: bash build_c.sh --flash /dev/sdX"
    exit 1
  fi
  echo "ADVERTENCIA: se borrará TODO en $USB_DEV"
  echo "Enter para continuar, Ctrl+C para cancelar"
  read -r
  sudo dd if="$IMG_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync
  echo "Listo."
else
  echo "Para probar:  bash build_c.sh --test"
  echo "Para USB:     bash build_c.sh --flash /dev/sdX"
fi
