#!/bin/bash
# ============================================================
# build.sh - Compila y une bootloader + juego
# Uso: bash build.sh
# Requiere: nasm, qemu-system-x86_64
# ============================================================

set -e  # detener si hay error

# ---- Limpiar y crear carpeta build -------------------------
rm -rf build
mkdir build

echo "[1/3] Compilando bootloader..."
nasm -f bin boot.asm -o build/boot.bin

# Verificar que el bootloader sea exactamente 512 bytes
BOOT_SIZE=$(wc -c < build/boot.bin)
if [ "$BOOT_SIZE" -ne 512 ]; then
    echo "ERROR: boot.bin debe ser 512 bytes, tiene $BOOT_SIZE"
    exit 1
fi
echo "      boot.bin = $BOOT_SIZE bytes (OK)"

echo "[2/3] Compilando juego..."
nasm -f bin juego.asm -o build/juego.bin

GAME_SIZE=$(wc -c < build/juego.bin)
GAME_SECTS=$(( (GAME_SIZE + 511) / 512 ))  # redondear hacia arriba
echo "      juego.bin = $GAME_SIZE bytes = $GAME_SECTS sectores"

# Advertir si el juego es mas grande que lo declarado en boot.asm
MAX_SECTS=20
if [ "$GAME_SECTS" -gt "$MAX_SECTS" ]; then
    echo "ADVERTENCIA: El juego necesita $GAME_SECTS sectores pero"
    echo "             GAME_SECTS en boot.asm dice $MAX_SECTS"
    echo "             Actualiza GAME_SECTS en src/boot.asm y recompila"
fi

echo "[3/3] Uniendo en game.bin..."
cat build/boot.bin build/juego.bin > build/game.bin

TOTAL=$(wc -c < build/game.bin)
echo "      game.bin = $TOTAL bytes total"
echo ""
echo "Listo! Para ejecutar:"
echo "  qemu-system-x86_64 -fda build/game.bin -display sdl"
echo ""
echo "Ejecutando en QEMU..."
qemu-system-x86_64 -fda build/game.bin
