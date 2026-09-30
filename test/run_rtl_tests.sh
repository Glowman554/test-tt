#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p test/build
make -C boot
cross_prefix=${CROSS_COMPILE:-riscv64-unknown-elf-}
"${cross_prefix}gcc" -march=rv32ima_zicsr_zifencei -mabi=ilp32 \
    -nostdlib -ffreestanding -Wl,-T,test/payload.ld -Wl,--no-relax \
    -o test/build/payload.elf test/payload.S
"${cross_prefix}objcopy" -O binary test/build/payload.elf test/build/payload.bin
python3 boot/make_image.py boot/build/boot.bin test/build/payload.bin \
    test/build/flash.bin --hex-output test/build/flash.hex
iverilog -g2012 -s serial_memory_tb -o test/build/serial_memory_tb.vvp \
    test/serial_memory_tb.v src/modules/serial_memory.v
vvp test/build/serial_memory_tb.vvp
iverilog -g2012 -s mmu_tlb_tb -o test/build/mmu_tlb_tb.vvp \
    test/mmu_tlb_tb.v src/core/mmu.v src/core/pmp.v
vvp test/build/mmu_tlb_tb.vvp
for test_name in platform_tb boot_tb boot_loader_tb; do
    iverilog -g2012 -s "$test_name" -o "test/build/$test_name.vvp" \
        "test/$test_name.v" src/project.v src/core/*.v src/modules/*.v
    vvp "test/build/$test_name.vvp"
done
