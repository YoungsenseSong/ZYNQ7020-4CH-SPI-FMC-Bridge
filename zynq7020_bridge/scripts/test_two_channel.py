"""Reproducible MC002 RTL regression. Python stdlib + Icarus only.

All generated vectors, executables, captures and logs go in a NEW output folder.
Existing CH0 tests run with their original source/golden layout, without edits.
"""
import argparse
import binascii
import csv
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import time
import zlib

PROJECT = Path(__file__).resolve().parents[1]
WORKSPACE = PROJECT.parents[2]
PROTOCOL = PROJECT.parent.parent / "protocol"
SOURCES = ["rtl/common/cdc_sync.v", "rtl/spi/spi_record_parser.v",
           "rtl/spi/spi_fixed_transaction_master.v", "rtl/spi/ch0_spi_controller.v",
           "rtl/scheduler/two_channel_record_mux.v", "rtl/top/two_channel_capture_core.v"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate_vectors(out):
    base = (PROTOCOL / "golden/nrf_record_valid.bin").read_bytes()
    if len(base) != 248:
        raise ValueError("frozen golden record must contain 248 bytes")
    for ch in range(2):
        records = []
        for n, seq in enumerate((0xFFFFFFFE, 0xFFFFFFFF, 0, 1)):
            record = bytearray(base)
            record[5] = ch + 1  # sensor node identity, distinct from SPI port
            struct.pack_into("<I", record, 8, seq)
            struct.pack_into("<I", record, 12, 1)
            struct.pack_into("<Q", record, 16, 1000 + ch * 73 + n * 100)
            struct.pack_into("<Q", record, 24, n * 32)
            # Synthetic payload deliberately distinct across channels/records.
            record[40:244] = bytes((ch * 131 + n * 37 + i * 11) & 255 for i in range(204))
            struct.pack_into("<H", record, 38, binascii.crc_hqx(record[:38], 0xFFFF))
            struct.pack_into("<I", record, 244, zlib.crc32(record[40:244]))
            records.append(record)
        (out / f"channel{ch}.bin").write_bytes(b"".join(records))


def verify_capture(out):
    expected = {ch: (out / f"channel{ch}.bin").read_bytes() for ch in range(2)}
    buffers = {}
    for row in csv.DictReader((out / "capture.csv").open(newline="", encoding="utf-8")):
        run, ch, rec, offset = (int(row[k]) for k in ("run", "channel", "record", "offset"))
        if run not in (0, 2) or ch not in (0, 1) or not 0 <= rec < 4:
            raise AssertionError(f"unexpected capture identity: {row}")
        data = buffers.setdefault((run, ch, rec), bytearray())
        if offset != len(data):
            raise AssertionError("missing, duplicate or reordered output byte")
        data.append(int(row["data"], 16))
    wanted = {(r, ch, n) for r in (0, 2) for ch in (0, 1) for n in range(4)}
    if set(buffers) != wanted:
        raise AssertionError("missing or extra records")
    for (run, ch, rec), data in buffers.items():
        if data != expected[ch][rec * 248:(rec + 1) * 248]:
            raise AssertionError(f"payload mismatch {(run, ch, rec)}")
        if binascii.crc_hqx(data[:38], 0xFFFF) != struct.unpack_from("<H", data, 38)[0]:
            raise AssertionError("header CRC")
        if zlib.crc32(data[40:244]) != struct.unpack_from("<I", data, 244)[0]:
            raise AssertionError("payload CRC")
    return {"records": len(buffers), "bytes": sum(map(len, buffers.values())),
            "runs": [0, 2], "sequence_wrap": [4294967294, 4294967295, 0, 1]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--iverilog", default="iverilog")
    parser.add_argument("--vvp", default="vvp")
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    tools = {name: shutil.which(getattr(args, name)) for name in ("iverilog", "vvp")}
    if not all(tools.values()):
        raise RuntimeError("Icarus iverilog and vvp required")
    results = []

    def run(label, command, marker=None):
        print(f"RUN {label}", flush=True)
        start = time.monotonic()
        result = subprocess.run(command, cwd=PROJECT, capture_output=True,
                                text=True, errors="replace", timeout=180)
        log = result.stdout + result.stderr
        (out / f"{label}.log").write_text(log, encoding="utf-8")
        item = {"name": label, "command": list(map(str, command)), "cwd": str(PROJECT),
                "exit_code": result.returncode, "seconds": round(time.monotonic() - start, 3)}
        results.append(item)
        (out / "commands.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        if result.returncode or (marker and marker not in log):
            raise RuntimeError(f"{label} failed; see {out / (label + '.log')}\n{log[-3000:]}")
        print(f"PASS {label} ({item['seconds']} s)", flush=True)

    generate_vectors(out)
    tests = [
        ("tb_two_channel_record_mux", ["rtl/scheduler/two_channel_record_mux.v"], []),
        ("tb_two_channel_capture_core", SOURCES + ["sim/two_channel_spi_slave_model.sv"],
         [f"+MC_GOLDEN_DIR={out.as_posix()}", f"+MC_CAPTURE={(out / 'capture.csv').as_posix()}"]),
        ("tb_spi_record_parser", ["rtl/spi/spi_record_parser.v"], []),
        ("tb_block_builder", ["rtl/block/block_builder.v"], []),
        ("tb_bram_pingpong", ["rtl/block/bram_pingpong.v"], []),
        ("tb_four_channel_record_aligner", ["rtl/alignment/four_channel_record_aligner.v"], []),
        ("tb_ch0_record_aligner", ["rtl/alignment/four_channel_record_aligner.v"], []),
        ("tb_ch0_spi_controller", ["rtl/spi/ch0_spi_controller.v",
         "rtl/spi/spi_fixed_transaction_master.v", "rtl/spi/spi_record_parser.v"], []),
    ]
    used = {Path(__file__).resolve()}
    for name, sources, plusargs in tests:
        files = [PROJECT / f"sim/{name}.sv"] + [PROJECT / p for p in sources]
        used.update(files)
        executable = out / f"{name}.vvp"
        run(f"{name}_compile", [tools["iverilog"], "-g2012", "-Wall", "-I",
            str(PROJECT / "rtl/common"), "-s", name, "-o", str(executable)] + list(map(str, files)))
        run(name, [tools["vvp"], str(executable), f"+GOLDEN_DIR={(PROTOCOL / 'golden').as_posix()}"] + plusargs,
            name.upper() + "_OK")
    used.add(PROJECT / "rtl/common/protocol_defs.vh")
    used.update((PROTOCOL / "golden").glob("*"))
    manifest = {str(p.relative_to(WORKSPACE)): digest(p) for p in sorted(used) if p.is_file()}
    (out / "input_sha256.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    summary = {"status": "PASS", "rtl_tests": len(tests), "capture": verify_capture(out),
               "tools": tools, "evidence": "RTL simulation with digital SPI slave models; no board/RF/DMA evidence"}
    (out / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
