# ============================================================
# Makefile - UEFI x64 (gnu-efi + gcc)
# ============================================================
#
# Propósito:
#   Interfaz conveniente para compilar, probar y grabar 
#   la versión x64 UEFI del juego.
#
# Diferencias UEFI vs. BIOS Legacy:
#   - gnu-efi: biblioteca que proporciona headers UEFI
#   - objcopy -O efi-app-x86_64: convierte ELF → binario PE/EFI
#   - FAT32 image: requiere estructura de directorios /EFI/BOOT/
#   - Archivo: BOOTX64.EFI (nombre estándar para boot UEFI x86-64)
#
# Uso:
#   make              : muestra ayuda
#   make build        : compila → build/uefi.img
#   make test         : compila y prueba en QEMU
#   make flash USB=/dev/sdX : graba en USB
#   make list-usb     : lista dispositivos
#   make clean        : elimina build/

SHELL := /bin/bash

.PHONY: help build test flash list-usb clean

# ----Target: help (muestra uso)----
help:
	@echo "Uso:"
	@echo "  make build              # Compila y genera build/uefi.img"
	@echo "  make test               # Compila y prueba en QEMU"
	@echo "  make flash USB=/dev/sdX # Compila y graba directo al USB"
	@echo "  make list-usb           # Lista discos/USB para elegir destino"
	@echo "  make clean              # Limpia carpeta build"

# ---- Target: build ----
build:
	bash ./build_c.sh

# ---- Target: test ----
test:
	bash ./build_c.sh --test

# ---- Target: flash ----
flash:
	@if [[ -z "$(USB)" ]]; then \
		echo "ERROR: Debes indicar el dispositivo USB."; \
		echo "Ejemplo: make flash USB=/dev/sdb"; \
		exit 1; \
	fi
	bash ./build_c.sh --flash $(USB)

# ---- Target: list-usb ----
list-usb:
	@echo "Dispositivos de bloque detectados (revisa RM=1 para removibles):"
	@lsblk -o NAME,MODEL,SIZE,RM,RO,TYPE,MOUNTPOINTS
	@echo
	@echo "Ejemplo de uso: make flash USB=/dev/sdb"

# ---- Target: clean ----
clean:
	rm -rf build
