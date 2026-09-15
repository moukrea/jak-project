"""Read ELF64 symbols without executing binaries; compare pre-relocation bytes."""
import hashlib
import json
import pathlib
import struct

NOTES = pathlib.Path(__file__).resolve().parent.parent
SYMBOL = "_ZN6Mips2C4jak119sp_process_block_3d7executeEPv"


def symbol_bytes(path, symbol):
    data = path.read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", data)
    assert data[:6] == b"\x7fELF\x02\x01"
    sections = [struct.unpack_from("<IIQQQQIIQQ", data, header[6] + i * header[11])
                for i in range(header[12])]
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        names = data[strings[4]:strings[4] + strings[5]]
        for offset in range(section[4], section[4] + section[5], section[9]):
            entry = struct.unpack_from("<IBBHQQ", data, offset)
            name = names[entry[0]:names.find(b"\0", entry[0])].decode()
            if name == symbol:
                owner = sections[entry[3]]
                return data[owner[4] + entry[4]:owner[4] + entry[4] + entry[5]]
    raise RuntimeError(f"missing {symbol} in {path}")


result = {}
for variant, old in [("before", "before"), ("after", "candidate")]:
    a = symbol_bytes(NOTES / "attempt7" / f"{old}-x86-same-headers.o", SYMBOL)
    b = symbol_bytes(NOTES / "attempt9" / f"x86-{variant}.o", SYMBOL)
    c = symbol_bytes(NOTES / "attempt9" / f"x86-{variant}-linked.o", f"full_{variant}_execute")
    result[variant] = {
        "old_size": len(a), "new_size": len(b),
        "old_sha256": hashlib.sha256(a).hexdigest(), "new_sha256": hashlib.sha256(b).hexdigest(),
        "byte_equal_old": a == b, "objcopy_bytes_equal": b == c,
        "differences": sum(x != y for x, y in zip(a, b))}
for variant in ["before", "after"]:
    a = symbol_bytes(NOTES / "attempt9" / f"arm-clang-{variant}.o", SYMBOL)
    b = symbol_bytes(NOTES / "attempt9" / f"arm-clang-{variant}-linked.o", f"full_{variant}_execute")
    result["arm-clang-" + variant] = {
        "size": len(a), "object_symbol_sha256": hashlib.sha256(a).hexdigest(),
        "objcopy_bytes_equal": a == b}
(NOTES / "attempt9/codegen-byte-review.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
