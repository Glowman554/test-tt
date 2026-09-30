#!/usr/bin/env python3
"""Pack a 32-bit little-endian, 0x40000000-linked payload for flash boot."""

import argparse
from pathlib import Path
import struct

FLASH_BYTES = 16 * 1024 * 1024
PAYLOAD_OFFSET = 0x10010
RAM_BASE = 0x40000000
RAM_BYTES = 16 * 1024 * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("boot", type=Path, help="boot/build/boot.bin")
    parser.add_argument("payload", type=Path, help="flat binary linked at 0x40000000")
    parser.add_argument("output", type=Path, help="flash image")
    parser.add_argument("--entry", type=lambda x: int(x, 0), default=RAM_BASE)
    parser.add_argument("--hex-output", type=Path, help="byte-wise hex for Verilog simulation")
    args = parser.parse_args()
    boot = args.boot.read_bytes()
    payload = args.payload.read_bytes()
    if len(boot) > 0x10000:
        parser.error("boot stage exceeds 64 KiB")
    if not payload or len(payload) % 4:
        parser.error("payload must be nonempty and a multiple of four bytes")
    if len(payload) > min(FLASH_BYTES - PAYLOAD_OFFSET, RAM_BYTES):
        parser.error("payload exceeds flash or PSRAM capacity")
    if not RAM_BASE <= args.entry < RAM_BASE + len(payload):
        parser.error("entry must point inside the copied payload")
    image = bytearray(b"\xff" * PAYLOAD_OFFSET)
    image[:len(boot)] = boot
    struct.pack_into("<4I", image, 0x10000, 0x52464E49, len(payload), args.entry, 0)
    image.extend(payload)
    args.output.write_bytes(image)
    if args.hex_output:
        args.hex_output.write_text("".join(f"{byte:02x}\n" for byte in image))


if __name__ == "__main__":
    main()
