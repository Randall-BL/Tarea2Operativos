#!/bin/bash
# ============================================================
# build_uefi.sh  –  Compila el bootloader UEFI y crea imagen
#
# Dependencias:
#   sudo apt install nasm mtools                (compilar + imagen)
#   sudo apt install ovmf qemu-system-x86_64    (probar en QEMU)
#
# Uso:
#   bash build_uefi.sh             → compila y crea uefi.img
#   bash build_uefi.sh --test      → además lanza QEMU
#   bash build_uefi.sh --flash /dev/sdX → graba en USB (¡cuidado!)
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
EFI_FILE="$BUILD_DIR/BOOTX64.EFI"
IMG_FILE="$BUILD_DIR/uefi.img"
IMG_MB=64       # tamaño de la imagen en MB

# ── Argumento opcional ───────────────────────────────────────
ARG="${1:-}"
USB_DEV="${2:-}"

# ============================================================
# 0. Preparar directorio build
# ============================================================
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ============================================================
# 1. Compilar con NASM  →  BOOTX64.EFI  (binario PE32+)
# ============================================================
echo "[1/4] Compilando boot_uefi.asm  →  BOOTX64.EFI ..."
nasm -f bin "$SCRIPT_DIR/boot_uefi.asm" -o "$EFI_FILE"

EFI_SIZE=$(wc -c < "$EFI_FILE")
echo "      BOOTX64.EFI = $EFI_SIZE bytes"

# Verificar firma MZ
MAGIC=$(xxd -p -l 2 "$EFI_FILE")
if [ "$MAGIC" != "4d5a" ]; then
    echo "ERROR: el archivo no tiene firma MZ. Revisa boot_uefi.asm"
    exit 1
fi

# Verificar firma PE
PE_OFF=$(python3 -c "import struct,sys; d=open('$EFI_FILE','rb').read(); print(struct.unpack_from('<I',d,0x3C)[0])")
PE_SIG=$(xxd -p -l 4 -s "$PE_OFF" "$EFI_FILE")
if [ "$PE_SIG" != "50450000" ]; then
    echo "ERROR: firma PE no encontrada en offset 0x$PE_OFF (encontré: $PE_SIG)"
    exit 1
fi

echo "      Firmas MZ+PE verificadas ✓"

# ============================================================
# 2. Crear imagen FAT32  (sin necesitar root, usando mtools)
# ============================================================
echo "[2/4] Creando imagen FAT32 de ${IMG_MB}MB  →  uefi.img ..."

if ! command -v mformat &> /dev/null; then
    echo ""
    echo "ERROR: mtools no está instalado."
    echo "       Instala con:  sudo apt install mtools"
    exit 1
fi

# Imagen raw vacía
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none

# Formatear como FAT32 (mtools no requiere root ni loop device)
# -h 64 -s 32: geometría compatible con firmware UEFI en medios extraíbles
mformat -i "$IMG_FILE" -h 64 -s 32 -F ::

# ============================================================
# 3. Crear estructura de directorios EFI y copiar el archivo
# ============================================================
echo "[3/4] Copiando BOOTX64.EFI  →  /EFI/BOOT/BOOTX64.EFI ..."

mmd    -i "$IMG_FILE" ::/EFI
mmd    -i "$IMG_FILE" ::/EFI/BOOT
mcopy  -i "$IMG_FILE" "$EFI_FILE" ::/EFI/BOOT/BOOTX64.EFI

# Verificar que quedó bien
echo "      Contenido de /EFI/BOOT/ dentro de uefi.img:"
mdir -i "$IMG_FILE" ::/EFI/BOOT/

echo ""
echo "======================================================="
echo " Imagen lista:  $IMG_FILE"
echo "======================================================="

# ============================================================
# 4a. Lanzar QEMU si se pidió --test
# ============================================================
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
        echo ""
        echo "AVISO: no se encontró firmware OVMF."
        echo "       Instala con:  sudo apt install ovmf"
    else
        echo "[4/4] Lanzando QEMU con UEFI firmware ..."
        qemu-system-x86_64 \
            -bios "$OVMF" \
            -drive if=virtio,format=raw,file="$IMG_FILE" \
            -m 256M \
            -display sdl \
            -name "UEFI Bootloader"
    fi

# ============================================================
# 4b. Grabar en USB si se pidió --flash /dev/sdX
# ============================================================
elif [ "$ARG" = "--flash" ]; then
    if [ -z "$USB_DEV" ]; then
        echo "Uso: bash build_uefi.sh --flash /dev/sdX"
        exit 1
    fi
    if [ ! -b "$USB_DEV" ]; then
        echo "ERROR: '$USB_DEV' no es un dispositivo de bloque."
        exit 1
    fi
    echo ""
    echo "  ADVERTENCIA: Se borrará TODO el contenido de $USB_DEV"
    echo "  Presiona Ctrl+C para cancelar, o Enter para continuar..."
    read -r
    echo "[4/4] Grabando en $USB_DEV ..."
    sudo dd if="$IMG_FILE" of="$USB_DEV" bs=4M status=progress conv=fsync
    echo "      Listo. Expulsa el USB con:  sudo eject $USB_DEV"

# ============================================================
# Sin argumentos: sólo mostrar instrucciones
# ============================================================
else
    echo ""
    echo "  Para probar en QEMU (requiere ovmf):"
    echo "    bash build_uefi.sh --test"
    echo ""
    echo "  Para grabar en USB y arrancar en tu PC real:"
    echo "    bash build_uefi.sh --flash /dev/sdX"
    echo "    (reemplaza sdX con tu USB, usa 'lsblk' para encontrarlo)"
    echo ""
    echo "  Para arrancar en tu PC:"
    echo "    1. Graba la imagen en un USB"
    echo "    2. Entra al BIOS/UEFI y desactiva Secure Boot"
    echo "    3. Elige el USB como dispositivo de arranque"
    echo "    4. Tu PC buscará /EFI/BOOT/BOOTX64.EFI automáticamente"
fi
