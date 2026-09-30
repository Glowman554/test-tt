CROSS_COMPILE ?= riscv64-unknown-elf-
CC = $(CROSS_COMPILE)gcc
OBJCOPY = $(CROSS_COMPILE)objcopy
CFLAGS = -march=rv32imac_zicsr_zifencei -mabi=ilp32 -nostdlib -ffreestanding -Wl,-T,link.ld -Wl,--no-relax

all: build/boot.bin

build/boot.elf: start.S link.ld
	mkdir -p build
	$(CC) $(CFLAGS) -o $@ start.S

build/boot.bin: build/boot.elf
	$(OBJCOPY) -O binary $< $@

.PHONY: all
