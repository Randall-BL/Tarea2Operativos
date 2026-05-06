# ============================================================
# Makefile - UEFI AArch64 (ARM64 cross-compile)
# ============================================================
#
# Propósito:
#   Interfaz para compilar, probar y grabar la versión AArch64 UEFI.
#   Diferente de x86-64: usa toolchain cross-compiler aarch64-linux-gnu
#
# Características únicas ARM:
#   - Toolchain: aarch64-linux-gnu-gcc (GNU) o clang (LLVM)
#   - Nombre de boot EFI: BOOTAA64.EFI (AArch64 standard name)
#   - Emulador: qemu-system-aarch64 (no qemu-system-x86_64)
#   - Firmware UEFI: UEFI Specification para ARM (eARM)
#
# Dependencias:
#   - aarch64-linux-gnu-gcc, aarch64-linux-gnu-ld, aarch64-linux-gnu-objcopy
#   - O alternativamente: clang + lld + llvm
#   - qemu-system-aarch64 (opcional para --test)
#   - mtools (para manipular imágenes FAT32)
#
# Uso:
#   make              : muestra ayuda
#   make build        : compila → build/uefi_arm.img
#   make test         : compila y ejecuta en QEMU ARM64
#   make flash USB=/dev/sdX : graba en USB
#   make list-usb     : lista dispositivos
#   make clean        : limpia build/

SHELL := /bin/bash

.PHONY: help build test flash list-usb clean

# ---- Target: help ----
help:
	@echo "Uso:"
	@echo "  make build              # Compila boot.S + juego.c y genera build/uefi_arm.img"
	@echo "  make test               # Compila y ejecuta en QEMU AArch64 UEFI"
	@echo "  make flash USB=/dev/sdX # Compila y graba la imagen al USB"
	@echo "  make list-usb           # Lista dispositivos para elegir USB"
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
	@echo "Dispositivos detectados (RM=1 suele ser removible):"
	@lsblk -o NAME,MODEL,SIZE,RM,RO,TYPE,MOUNTPOINTS

# ---- Target: clean ----
clean:
	rm -rf build
