#!/bin/bash
# Salva el shell que ejecutará este script (Bash)
set -e
# Salir inmediatamente si cualquier comando falla (estatus != 0)

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

# Directorio donde se encuentra este script (ruta absoluta)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Directorio de salida para objetos y binarios
BUILD_DIR="$SCRIPT_DIR/build"
# Ruta del archivo EFI final que se generará
EFI_FILE="$BUILD_DIR/BOOTX64.EFI"
# Ruta del objeto intermedio (.so) creado por el linker
SO_FILE="$BUILD_DIR/bootloader.so"
# Imagen FAT donde se colocará el EFI
IMG_FILE="$BUILD_DIR/uefi.img"
# Tamaño en MB de la imagen FAT que se creará
IMG_MB=64

# Argumento 1 (por ejemplo --test o --flash)
ARG="${1:-}"
# Argumento 2 (dispositivo USB para --flash)
USB_DEV="${2:-}"

# Verifica que las herramientas requeridas estén en PATH
for t in gcc ld objcopy mformat mmd mcopy mdir; do
  if ! command -v "$t" >/dev/null 2>&1; then
    echo "ERROR: falta '$t'."
    exit 1
  fi
done

# Comprueba que las cabeceras de gnu-efi estén instaladas
if [ ! -d /usr/include/efi ]; then
  echo "ERROR: no se encontró /usr/include/efi"
  echo "Instala: sudo apt install gnu-efi"
  exit 1
fi

# Buscar ruta a crt0-efi-x86_64.o en varias ubicaciones comunes
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

# Buscar el script de linking (.lds) usado por gnu-efi
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

# Si no se encontraron los archivos necesarios, aborta
if [ -z "$CRT0" ] || [ -z "$LDS" ]; then
  echo "ERROR: no se encontraron archivos de enlace de gnu-efi."
  echo "Instala/Reinstala: sudo apt install gnu-efi"
  exit 1
fi

# Limpia cualquier build anterior y crea el directorio de salida
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "[1/4] Compilando C..."
# Compila bootloader.c a objeto con opciones adecuadas para UEFI
# Explicación de los parámetros de `gcc` usados abajo:
# -I/usr/include/efi -I/usr/include/efi/x86_64 : rutas de inclusión para headers de gnu-efi
# -fpic                        : generar código independiente de posición (position-independent)
# -ffreestanding               : compilación sin dependencias de la libc (entorno freestanding)
# -fno-stack-protector        : deshabilita protecciones de pila (no usadas en UEFI)
# -fshort-wchar               : `wchar_t` ocupa 2 bytes (requerido por gnu-efi)
# -mno-red-zone               : deshabilita la red zone usada por ABI de SysV (UEFI/firmware)
# -Wall -Wextra               : activar warnings comunes y adicionales
# -O2                         : optimización de nivel 2
# -c                          : compilar a objeto (.o) sin enlazar
# -o <archivo>                : fichero de salida (objeto)
# Las opciones `-I`, `-fshort-wchar` y `-ffreestanding` son importantes para compilar
# código destinado a ejecutarse como aplicación UEFI.
gcc -I/usr/include/efi -I/usr/include/efi/x86_64 \
    -fpic -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone \
    -Wall -Wextra -O2 -c "$SCRIPT_DIR/bootloader.c" -o "$BUILD_DIR/bootloader.o"

# Compila juego.c a objeto con las mismas opciones
gcc -I/usr/include/efi -I/usr/include/efi/x86_64 \
    -fpic -ffreestanding -fno-stack-protector -fshort-wchar -mno-red-zone \
    -Wall -Wextra -O2 -c "$SCRIPT_DIR/juego.c" -o "$BUILD_DIR/juego.o"

echo "[2/4] Enlazando PE intermedio..."
# Enlaza los objetos usando el script LDS y crt0 para producir un .so intermedio
ld -nostdlib -znocombreloc -T "$LDS" -shared -Bsymbolic \
   "$CRT0" "$BUILD_DIR/bootloader.o" "$BUILD_DIR/juego.o" \
   -L/usr/lib -L/usr/lib/x86_64-linux-gnu -L/usr/lib/x86_64-linux-gnu/gnuefi \
   -lefi -lgnuefi \
   -o "$SO_FILE"

# Convierte el .so intermedio a ejecutable PE/EFI extrayendo secciones relevantes
objcopy \
  -j .text -j .sdata -j .data -j .dynamic -j .dynsym \
  -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
  --target=efi-app-x86_64 "$SO_FILE" "$EFI_FILE"

echo "      BOOTX64.EFI = $(wc -c < "$EFI_FILE") bytes"

echo "[3/4] Creando imagen FAT32..."
# Crea un fichero lleno de ceros que actuará como imagen de disco
dd if=/dev/zero of="$IMG_FILE" bs=1M count=$IMG_MB status=none
# Formatea la imagen como FAT32 (mtools)
mformat -i "$IMG_FILE" -h 64 -s 32 -F ::
# Crea los directorios estándar UEFI dentro de la imagen
mmd -i "$IMG_FILE" ::/EFI
mmd -i "$IMG_FILE" ::/EFI/BOOT
# Copia el EFI generado a la ruta de arranque estándar
mcopy -i "$IMG_FILE" "$EFI_FILE" ::/EFI/BOOT/BOOTX64.EFI
# Lista el contenido del directorio para confirmar
mdir -i "$IMG_FILE" ::/EFI/BOOT/

echo
echo "Imagen lista: $IMG_FILE"

if [ "$ARG" = "--test" ]; then
  # Modo prueba: busca OVMF (firmware UEFI para QEMU) y arranca QEMU
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
  # Lanza QEMU usando el firmware OVMF y la imagen creada
  qemu-system-x86_64 \
      -bios "$OVMF" \
      -drive if=virtio,format=raw,file="$IMG_FILE" \
      -m 256M \
      -display sdl \
      -name "UEFI C Bootloader"

elif [ "$ARG" = "--flash" ]; then
  # Modo flash: escribe la imagen directamente a un dispositivo USB
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
  # Mensaje de ayuda si no se pasan argumentos conocidos
  echo "Para probar:  bash build_c.sh --test"
  echo "Para USB:     bash build_c.sh --flash /dev/sdX"
fi
