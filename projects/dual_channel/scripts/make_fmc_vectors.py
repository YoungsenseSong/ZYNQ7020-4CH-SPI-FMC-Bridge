"""CRC-valid RF/record fixtures for full host decoding of the FMC simulation."""
import binascii
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
template = (root / "protocol/golden/nrf_record_valid.bin").read_bytes()
for channel in range(2):
    records = []
    for sequence in range(4):
        record = bytearray(template)
        record[5] = channel
        struct.pack_into("<IIQQIHH", record, 8, sequence, 1,
                         sequence * 8000, sequence * 96, 1, 204, 0)
        struct.pack_into("<HHHHI", record, 40, 0xA55A,
                         channel * 100 + sequence, 96, 2, sequence * 8)
        for index in range(96):
            struct.pack_into("<h", record, 52 + index * 2,
                             (1 if channel == 0 else -1) * (1000 + sequence * 96 + index))
        struct.pack_into("<H", record, 38, binascii.crc_hqx(record[:38], 0xFFFF))
        struct.pack_into("<I", record, 244, binascii.crc32(record[40:244]) & 0xFFFFFFFF)
        records.append(record)
    (out / f"channel{channel}.bin").write_bytes(b"".join(records))
