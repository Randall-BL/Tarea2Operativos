SHELL := /bin/bash

.PHONY: help build test flash list-usb clean

help:
	@echo "Uso:"
	@echo "  make build              # Compila y genera build/uefi.img"
	@echo "  make test               # Compila y prueba en QEMU"
	@echo "  make flash USB=/dev/sdX # Compila y graba directo al USB"
	@echo "  make list-usb           # Lista discos/USB para elegir destino"
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
	@echo "Dispositivos de bloque detectados (revisa RM=1 para removibles):"
	@lsblk -o NAME,MODEL,SIZE,RM,RO,TYPE,MOUNTPOINTS
	@echo
	@echo "Ejemplo de uso: make flash USB=/dev/sdb"

clean:
	rm -rf build
