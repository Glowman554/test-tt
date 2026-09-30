## Inferno RISC-V SPI/PSRAM SoC

This port keeps the original RV32IMAC CPU, CLINT, and one-source PLIC. The
optional Sv32 MMU and PMP remain in the source but are disabled in the Tiny
Tapeout build. Enabling the MMU selects a 32-entry TLB. It removes the FPGA DDR3 controller, DDR cache, and
embedded SRAM. One UART and one software-controlled SPI peripheral remain.

The CPU resets at address zero, which is mapped to the read-only 16 MiB SPI
flash on the Tiny Tapeout QSPI Pmod. Two 8 MiB PSRAM chips form the writable
16 MiB region at `0x40000000`. Memory accesses are single-bit SPI mode 0 and
stall the CPU until complete. The 25 MHz project clock generates a 12.5 MHz
memory SCK. The memory controller holds all chip selects inactive for 4096
clocks after reset, exceeding the PSRAM's 150 us power-up requirement at
25 MHz.

### Physical memory and peripherals

| Address range | Function |
| --- | --- |
| `0x00000000–0x00ffffff` | SPI flash boot ROM, read-only |
| `0x02000000–0x0200ffff` | CLINT |
| `0x0c000000–0x0fffffff` | PLIC, UART interrupt source 1 |
| `0x40000000–0x407fffff` | PSRAM A |
| `0x40800000–0x40ffffff` | PSRAM B |
| `0x80000008–0x80000013` | UART |
| `0x80000040–0x8000004f` | Software SPI peripheral |

The QSPI Pmod uses the recommended Tiny Tapeout pinout: `uio[0]` flash CS,
`uio[1]` MOSI, `uio[2]` MISO, `uio[3]` SCK, `uio[4:5]` held high, and
`uio[6:7]` PSRAM A/B chip selects. The UART uses `ui[1]` RX and `uo[0]`
TX. The separate software SPI peripheral uses `ui[0]` MISO and `uo[1:3]`
SCK/MOSI/CS.

### Flash image

`boot/start.S` is a minimal reset stage. It reads a 16-byte header at flash
offset `0x10000`, copies the following payload into PSRAM at `0x40000000`,
then jumps to the header entry point. The header contains four little-endian
words: magic `0x52464e49` (`INFR`), payload byte count, entry point, and
reserved zero. The payload must be a flat binary linked at `0x40000000`.

Build the boot stage with `make -C boot`, then create a flash image with
`python3 boot/make_image.py boot/build/boot.bin payload.bin flash.bin`.
Program `flash.bin` into the QSPI Pmod flash before releasing reset.

### Verification and status

`test/run_rtl_tests.sh` runs the serial memory transaction tests, a reset
fetch test, and a flash-to-PSRAM boot test. The tests use Icarus Verilog and
a RISC-V cross toolchain. The current `8x2` tile setting needs a new GDS run
with the MMU and PMP disabled. The original 128 MiB
DDR software image and 32 KiB SRAM firmware need relinking and memory-size
changes before they can run on this 16 MiB port.
