#!/bin/bash
set -e

# ============================================================
# build_c.sh  –  Compila UEFI en C (bootloader + juego)
#
# Dependencias (Ubuntu/Debian):
#   sudo apt install gcc gnu-efi binutils mtools
#   sudo apt install ovmf qemu-system-x86_64   # opcional para --test
#
# Uso:
#   bash build_c.sh
#   bash build_c.sh --test
#   bash build_c.sh --flash /dev/sdX
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
EFI_FILE="$BUILD_DIR/BOOTX64.EFI"
SO_FILE="$BUILD_DIR/bootloader.so"
IMG_FILE="$BUILD_DIR/uefi.img"
IMG_MB=64

ARG="${1:-}"
USB_DEV="${2:-}"

for t in gcc ld objcopy mformat mmd mcopy mdir; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ERROR: falta '$t'."
    exit 1
  fi
done

if [ ! -d /usr/include/efi ]; then
  echo "ERROR: no se encontró /usr/include/efi"
  echo "Instala: sudo apt install gnu-efi"
  exit 1
fi

CRT0=""
for p in \
  /usr/lib/crt0-efi-x86_64.o \
  /usr/lib/x86_64-linux-gnu/crt0-efi-x86_64.o \
  /usr/lib64/crt0-efi-x86_64.o; do
  if [ -f "$p" ]; then
    CRT0="$p"
    break
  fi
done

LDS=""
for p in \
  /usr/lib/elf_x86_64_efi.lds \
  /usr/lib/x86_64-linux-gnu/gnuefi/elf_x86_64_efi.lds \
  /usr/lib64/elf_x86_64_efi.lds; do
  if [ -f "$p" ]; then
    LDS="$p"
    break
  fi
done

if [ -z "$CRT0" ] || [ -z "$LDS" ]; then
  echo "ERROR: no se encontraron archivos de enlace de gnu-efi."
  echo "Instala/Reinstala: sudo apt install gnu-efi"
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/4] Compilando C..."
gcc -I/usr/include/efi -I/usr/include/efi/x86_64 \
    -fpic -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone \
    -Wall -Wextra -O2 -c "$SCRIPT_DIR/bootloader.c" -o "$BUILD_DIR/bootloader.o"

gcc -I/usr/include/efi -I/usr/include/efi/x86_64 \
    -fpic -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone \
    -Wall -Wextra -O2 -c "$SCRIPT_DIR/juego.c" -o "$BUILD_DIR/juego.o"

echo "[2/4] Enlazando PE intermedio..."
ld -nostdlib -znocombreloc -T "$LDS" -shared -Bsymbolic \
   "$CRT0" "$BUILD_DIR/bootloader.o" "$BUILD_DIR/juego.o" \
   -L/usr/lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib/x86_64-linux-gnu/gnuefi \
   -lefi -lgnuefi \
   -o "$SO_FILE"

objcopy \
  -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
  -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
  --target=efi-app-x86_64 "$SO_FILE" "$EFI_FILE"

echo "      BOOTX64.EFI = $(wc -c < "$EFI_FILE") bytes"

echo "[3/4] Creando imagen FAT32..."
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none
mformat -i "$IMG_FILE" -h 64 -s 32 -F ::
mmd -i "$IMG_FILE" ::/EFI
mmd -i "$IMG_FILE" ::/EFI/BOOT
mcopy -i "$IMG_FILE" "$EFI_FILE" ::/EFI/BOOT/BOOTX64.EFI
mdir -i "$IMG_FILE" ::/EFI/BOOT/

echo
echo "Imagen lista: $IMG_FILE"

if [ "$ARG" = "--test" ]; then
  OVMF=""
  for CANDIDATE in \
      /usr/share/ovmf/OVMF.fd \
      /usr/share/OVMF/OVMF_CODE.fd \
      /usr/share/qemu/OVMF.fd \
      /usr/lib/ovmf/OVMF.fd; do
      if [ -f "$CANDIDATE" ]; then
          OVMF="$CANDIDATE"
          break
      fi
  done

  if [ -z "$OVMF" ]; then
      echo "No se encontró OVMF. Instala: sudo apt install ovmf"
      exit 1
  fi

  echo "[4/4] Ejecutando QEMU..."
  qemu-system-x86_64 \
      -bios "$OVMF" \
      -drive if=virtio,format=raw,file="$IMG_FILE" \
      -m 256M \
      -display sdl \
      -name "UEFI C Bootloader"

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
