SHELL := /bin/bash

.PHONY: help build test flash list-usb clean

help:
	@echo "Uso:"
	@echo "  make build              # Compila boot.S + juego.c y genera build/uefi_arm.img"
	@echo "  make test               # Compila y ejecuta en QEMU AArch64 UEFI"
	@echo "  make flash USB=/dev/sdX # Compila y graba la imagen al USB"
	@echo "  make list-usb           # Lista dispositivos para elegir USB"
	@echo "  make clean              # Limpia carpeta build"

build:
	bash ./build_c.sh

test:
	bash ./build_c.sh --test

flash:
	@if [[ -z "$(USB)" ]]; then \
		echo "ERROR: Debes indicar el dispositivo USB."; \
		echo "Ejemplo: make flash USB=/dev/sdb"; \
		exit 1; \
	fi
	bash ./build_c.sh --flash $(USB)

list-usb:
	@echo "Dispositivos detectados (RM=1 suele ser removible):"
	@lsblk -o NAME,MODEL,SIZE,RM,RO,TYPE,MOUNTPOINTS

clean:
	rm -rf build
