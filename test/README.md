# Tests

Run `./test/run_rtl_tests.sh` from the repository root for the Icarus Verilog
tests. They cover boot ROM write protection, SPI flash reads, both PSRAM banks,
partial writes, CPU reset fetch, and execution of a flash-loaded PSRAM payload.
The runner also builds the small RISC-V test payload and flash image.

`make` in this directory runs the standard Tiny Tapeout cocotb smoke test.
It checks the pin directions and the reset fetch transaction. Install the
packages in `requirements.txt` before running it.
