# RISC-V architectural verification

This directory ports the original Inferno RISC-V architectural test harness to
the Tiny Tapeout CPU RTL. The Verilator testbench loads a test ELF into a
16 MiB memory model at `0x40000000` and starts the CPU there. It also models
the CLINT, PLIC, and test interrupt register. This verifies the CPU and MMU;
`../test/run_rtl_tests.sh` separately checks the SPI flash boot path and PSRAM
interface.
The architectural testbench uses the default `ENABLE_MMU=1` and
`ENABLE_PMP=1` core settings; the Tiny Tapeout top disables both.

Run from the repository root with Verilator, Python 3, `tqdm`, RISC-V GNU
binutils, and a C++ compiler installed:

```sh
make -C verification sim
make -C verification run ELFDIR=/path/to/inferno-rv32imac/elfs
```

The source repository's test generation flow is included. To download its
RISC-V architectural tests, Sail reference simulator, and GNU toolchain,
then generate test ELFs and run them:

```sh
make -C verification all
```

`make -C verification elfs` generates ELFs without running the simulator.
`make -C verification run TESTS='I-add-00 I-srai-00'` runs selected tests.
Set `JOBS=4` to control build and test parallelism; `TIMEOUT` sets each
test's simulated cycle limit. Results and per-test logs are written to
`verification/build/results/`.
