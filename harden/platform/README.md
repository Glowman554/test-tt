# Standalone platform hardening

This LibreLane configuration hardens `TinyPlatform` in a 682.64 × 225.76 µm
die. It includes the serial memory controllers, UART, SPI, CLINT, and PLIC.
It is a standalone block experiment; the CPU and Tiny Tapeout wrapper are
not in this GDS.

With LibreLane and the SKY130A PDK installed, run from the repository root:

```sh
export PDK_ROOT=/path/to/pdk-root
./harden/platform/build.sh
```

Follow progress with `tail -f harden/platform/build.log`. The GDS is written
to `harden/platform/runs/platform/final/gds/TinyPlatform.gds`. Open it with
KLayout:

```sh
klayout harden/platform/runs/platform/final/gds/TinyPlatform.gds
```

The initial local run with LibreLane 3.0.14 and SKY130A completed with zero
antenna, LVS, and DRC violations. Its final metrics are in
`harden/platform/runs/platform/final/metrics.json`.
