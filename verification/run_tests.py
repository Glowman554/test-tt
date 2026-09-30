#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from tqdm import tqdm


RAM_BASE = 0x40000000
PREFIX = "riscv64-unknown-elf-"


def elf_to_hex(elf: Path, out: Path) -> int:
    result = subprocess.run([PREFIX + "nm", str(elf)], capture_output=True, text=True, check=True)

    tohost = None
    for line in result.stdout.splitlines():
        if line.endswith(" tohost"):
            tohost = int(line.split()[0], 16)
            break

    if tohost is None:
        raise ValueError(f"{elf.name}: no tohost symbol found")


    binary = out.with_suffix(".bin")
    subprocess.run([PREFIX + "objcopy", "-O", "binary", str(elf), str(binary)], check=True)

    data = binary.read_bytes()
    binary.unlink()

    padding = -len(data) % 4
    data += bytes(padding)

    lines = []
    for offset in range(0, len(data), 4):
        word = int.from_bytes(data[offset : offset + 4], "little")
        lines.append(f"{word:08x}")

    out.write_text("\n".join(lines) + "\n")
    return tohost


def run_one(sim: Path, elf: Path, out_dir: Path, timeout: int) -> tuple[str, str, str]:
    name = elf.name.removesuffix(".elf")
    image = out_dir / f"{name}.hex"
    log = out_dir / f"{name}.log"

    try:
        tohost = elf_to_hex(elf, image)
    except Exception as exc:
        message = str(exc)
        log.write_text(message + "\n")
        return name, "ERROR", message

    cmd = [str(sim), f"+image={image}", f"+tohost={tohost:x}", f"+timeout={timeout}"]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace", timeout=3600)
        output = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or b""
        output = stdout.decode(errors="replace")
        output += "\nwall-clock timeout\n"

    log.write_text(" ".join(cmd) + "\n" + output)

    if "ARCH_TB: PASS" in output and "TEST FAILED" not in output:
        status = "PASS"
    elif "ARCH_TB: TIMEOUT" in output:
        status = "TIMEOUT"
    else:
        status = "FAIL"

    detail = ""
    for line in output.splitlines():
        is_failure = re.search(r"FAIL|mismatch|Expected|Actual|RVCP", line, re.IGNORECASE)
        is_test_passed = "TEST PASSED" in line

        if is_failure and not is_test_passed:
            detail = line.strip()
            break

    return name, status, detail


def load_expected_failures(path: Path | None) -> dict[str, str]:
    expected = {}

    if path is None:
        return expected

    if not path.exists():
        return expected

    for line in path.read_text().splitlines():
        line = line.strip()

        if not line:
            continue

        if line.startswith("#"):
            continue

        name, _, reason = line.partition(" ")
        expected[name] = reason.strip()

    return expected


def find_elfs(root: Path, filters: list[str]) -> list[Path]:
    elfs = []

    for elf in root.rglob("*.elf"):
        if not filters:
            elfs.append(elf)
            continue

        for filter_text in filters:
            if filter_text in elf.name:
                elfs.append(elf)
                break

    elfs.sort()
    return elfs


def count_results(results: list[tuple[str, str, str]]) -> dict[str, int]:
    statuses = (
        "PASS",
        "XFAIL",
        "FAIL",
        "XPASS",
        "TIMEOUT",
        "ERROR",
    )

    counts = {}
    for status in statuses:
        counts[status] = 0

    for _, status, _ in results:
        counts[status] += 1

    return counts


def write_summary(path: Path, results: list[tuple[str, str, str]]) -> None:
    lines = []

    for name, status, detail in results:
        lines.append(f"{status:7} {name}  {detail}\n")

    path.write_text("".join(lines))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sim", type=Path, required=True)
    parser.add_argument("--elfs", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=os.cpu_count())
    parser.add_argument("--timeout", type=int, default=20_000_000, help="cycle limit per test")
    parser.add_argument("--xfail", type=Path, help="file listing expected failures: <test-name> <reason>")
    parser.add_argument("filters", nargs="*", help="only run ELFs whose name contains one of these strings")
    args = parser.parse_args()

    elfs = find_elfs(args.elfs, args.filters)

    if not elfs:
        print(f"no ELFs found under {args.elfs}", file=sys.stderr)
        return 2

    expected = load_expected_failures(args.xfail)

    args.out.mkdir(parents=True, exist_ok=True)

    results = []

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = []

        for elf in elfs:
            future = pool.submit(run_one, args.sim, elf, args.out, args.timeout)
            futures.append(future)

        completed = as_completed(futures)
        progress = tqdm(completed, total=len(futures))

        for index, future in enumerate(progress, 1):
            name, status, detail = future.result()

            if name in expected:
                if status == "FAIL":
                    status = "XFAIL"
                    detail = expected[name]
                elif status == "PASS":
                    status = "XPASS"
                    detail = "listed in --xfail but passed"

            results.append((name, status, detail))

            if status not in ("PASS", "XFAIL"):
                print(f"[{index}/{len(elfs)}] {status:7} {name}  {detail}", flush=True)

    results.sort()
    counts = count_results(results)

    summary = args.out / "summary.txt"
    write_summary(summary, results)

    count_parts = []
    for status, count in counts.items():
        count_parts.append(f"{count} {status}")

    print(f"\n{len(results)} tests: " + ", ".join(count_parts))

    successful = counts["PASS"] + counts["XFAIL"]

    if successful == len(results):
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
