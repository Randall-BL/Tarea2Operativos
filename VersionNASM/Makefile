# ============================================================
# Makefile - BIOS Legacy x86 (NASM + GCC)
# ============================================================
#
# Propósito:
#   Proporciona interfaz conveniente con targets para compilar,
#   probar en QEMU, grabar en USB, y limpiar la compilación.
#
# Dependencias:
#   - nasm : ensamblador (para boot.asm)
#   - gcc : compilador C (compilador de juego.c en -m16)
#   - binutils (ld, objcopy) : herramientas de enlazamiento
#   - qemu-system-x86 : emulador x86 para testing
#   - mtools : utilidades para manipular imágenes FAT
#
# Uso:
#   make              : muestra ayuda (target help)
#   make build        : compila boot.asm + juego.c → build/bios.img
#   make test         : compila y ejecuta en QEMU (BIOS legacy)
#   make flash USB=/dev/sdX : graba build/bios.img en USB
#   make list-usb     : lista dispositivos de bloque (para elegir USB)
#   make clean        : elimina carpeta build/

SHELL := /bin/bash

.PHONY: help build test flash list-usb clean

# ---- Target: help (default, muestra instrucciones de uso) ----
help:
	@echo "Uso:"
	@echo "  make build              # Compila boot.asm + juego.c y genera build/bios.img"
	@echo "  make test               # Compila y ejecuta en QEMU (BIOS legacy)"
	@echo "  make flash USB=/dev/sdX # Compila y graba la imagen al USB"
	@echo "  make list-usb           # Lista dispositivos para elegir USB"
	@echo "  make clean              # Limpia carpeta build"

# ---- Target: build (compilación sin test/flash) ----
build:
	bash ./build_c.sh

# ---- Target: test (compilación + ejecución en QEMU) ----
test:
	bash ./build_c.sh --test

# ---- Target: flash (compilación + grabación en USB) ----
flash:
	@if [[ -z "$(USB)" ]]; then \
		echo "ERROR: Debes indicar el dispositivo USB."; \
		echo "Ejemplo: make flash USB=/dev/sdb"; \
		exit 1; \
	fi
	bash ./build_c.sh --flash $(USB)

# ---- Target: list-usb (enumera dispositivos de bloque) ----
list-usb:
	@echo "Dispositivos detectados (RM=1 suele ser removible):"
	@lsblk -o NAME,MODEL,SIZE,RM,RO,TYPE,MOUNTPOINTS

# ---- Target: clean (elimina build artifacts) ----
clean:
	rm -rf build
