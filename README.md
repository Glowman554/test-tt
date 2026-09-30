# Inferno RISC-V for Tiny Tapeout

This repository is a port of the Inferno RV32IMAC SoC to the official
Tiny Tapeout SKY Verilog template. SPI flash is the read-only boot ROM at
address zero; two SPI PSRAMs replace DDR3 and embedded SRAM at
`0x40000000–0x40ffffff`. The SoC exposes one UART
and one software SPI peripheral in addition to its dedicated memory SPI bus.

See [docs/info.md](docs/info.md) for the address map, pinout, and flash format.

Run the RTL and boot tests with:

```sh
./test/run_rtl_tests.sh
```

The tests require Icarus Verilog, Python 3, and a
`riscv64-unknown-elf-` cross toolchain. The standard Tiny Tapeout cocotb
smoke test remains in `test/` for its CI flow.

The RISC-V architectural verification harness is in
[verification/](verification/README.md). It runs generated ISA tests against
the ported CPU with a 16 MiB PSRAM model. That harness enables the optional
MMU and PMP. The Tiny Tapeout top module sets `ENABLE_MMU=0` and
`ENABLE_PMP=0`; the enabled MMU uses 32 TLB entries.

The `8x2` tile selection is the largest allowed by the SKY template. No ASIC
placement or GDS result has established whether the full CPU fits or meets
25 MHz timing with MMU and PMP disabled.

The CPU sources come from the adjacent `inferno-riscv-rtl` repository. The
template was cloned from
[TinyTapeout/ttsky-verilog-template](https://github.com/TinyTapeout/ttsky-verilog-template).
