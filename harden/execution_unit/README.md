# Standalone execution unit hardening

This configuration hardens `ExecutionUnit` and its `MulDiv` and `Decompress`
submodules in a 1378.16 × 511.36 µm die (the 8×4 tile size). It uses a 40 ns
clock target and routes through metal 3, matching the platform experiment.

With LibreLane and the SKY130A PDK installed, run from the repository root:

```sh
export PDK_ROOT=/path/to/pdk-root
./harden/execution_unit/build.sh
```

Follow progress with `tail -f harden/execution_unit/build.log`. After a
successful run, open the GDS with KLayout:

```sh
klayout harden/execution_unit/runs/execution_unit/final/gds/ExecutionUnit.gds
```

The final metrics are written to
`harden/execution_unit/runs/execution_unit/final/metrics.json`.

The initial local run used LibreLane 3.0.14 and SKY130A. Antenna, LVS, and
both Magic and KLayout DRC passed with zero violations. The 40 ns timing
target did not pass at the slow corner: worst setup slack was -4.19 ns.
An 8×2 floorplan passed placement but failed global routing because of
congestion, so this configuration uses 8×4.
