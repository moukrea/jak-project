#!/usr/bin/env python3
"""
Bake the committed "recharged" replacement textures to GPU-compressed KTX2 (ASTC).

WHY (measured on device, 2026-08-26, phase Gshield-load-and-crash):
  the PNG path costs `stage texture took 1799 ms` at worst on the SHIELD. One PBR
  material = 4 maps of 2048x2048, each decoded by stbi_load (151-330 ms), decoded
  TWICE (probe pass + re-fetch before upload), then glGenerateMipmap (68-235 ms).
  The KTX2 path already in the engine (managed pack) does the same material in 87 ms:
  no decode, no mip generation, and the GPU keeps a compressed image instead of
  16 MiB of RGBA8 per map.

WHAT THIS TOOL DOES:
  custom_assets/<game>/recharged_textures/<tpage>/<material>/<file>.png
    -> custom_assets/<game>/recharged_textures_baked/astc/<tpage>/<material>/<file>.ktx2
    -> custom_assets/<game>/recharged_textures_baked/astc/<tpage>/<material>/<material>.stats.json

  * every mip level down to 1x1 is built OFFLINE by box reduction from level 0
    (never cascaded, so the chain does not drift),
  * every level is encoded with astcenc: 4x4 for `_normal` (the fragile map), 6x6
    for everything else,
  * the container is the KTX2 SUBSET that `common/util/Ktx2Subset.{h,cpp}` accepts,
    and every file is RE-READ and re-validated by this tool with the same checks
    before it is allowed to exist,
  * the per-pixel STATISTICS that `LoaderStages.cpp` computes at runtime while it
    has the decoded PNG in hand (normal-map DC, height mean / robust half-range /
    feature wavelength, roughness min-mean-max) are computed here instead, with the
    SAME formulas, and written next to the textures. Without a decode at runtime
    those numbers have nowhere else to come from.

TRANSCRIPTION PARITY, MEASURED (2026-08-26): the statistics this tool writes were
compared against a REAL ENGINE RUN that still decoded the PNGs
(.autoport/logs/gmb-attempt3-desktop-smoke.log, x86 desktop, "pbr height stat:" /
"pbr normal DC:" / "pbr roughness data:" lines). Every printed digit agrees on the
25 PNG-sourced maps. The only divergence is the four vil-beach-01* files, which are
JPEG despite their .png name: Pillow's libjpeg and the engine's stb_image differ by
up to 3/255 on that file, which moves its normal DC by 0.9% (tilt 10.70 vs 10.74
deg). Re-run that comparison after touching any formula here.

This tool NEVER writes into git-tracked engine sources and never needs a build.
astcenc is REQUIRED (and only here): the packaging script must work without it.
"""

import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    import numpy as np
except ImportError:  # pragma: no cover
    sys.stderr.write("bake: numpy is required (pip install numpy)\n")
    sys.exit(2)

try:
    from PIL import Image
except ImportError:  # pragma: no cover
    sys.stderr.write("bake: Pillow is required (pip install Pillow)\n")
    sys.exit(2)

# ---------------------------------------------------------------------------
# KTX2 subset — mirror of common/util/Ktx2Subset.{h,cpp}
# ---------------------------------------------------------------------------

KTX2_IDENTIFIER = bytes([0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A])

VK_FORMAT_R8G8B8A8_UNORM = 37
VK_FORMAT_ASTC_4x4_UNORM = 157
VK_FORMAT_ASTC_6x6_UNORM = 165

# The subset the reader accepts (Ktx2Subset.cpp::is_supported_format), with the
# block geometry it uses (block_info): {vkFormat: (block_w, block_h, block_bytes)}.
SUPPORTED_FORMATS = {
    37: (1, 1, 4),    # R8G8B8A8_UNORM
    131: (4, 4, 8),   # BC1_RGB_UNORM
    139: (4, 4, 8),   # BC4_UNORM
    141: (4, 4, 16),  # BC5_UNORM
    145: (4, 4, 16),  # BC7_UNORM
    147: (4, 4, 8),   # ETC2_R8G8B8_UNORM
    153: (4, 4, 8),   # EAC_R11_UNORM
    155: (4, 4, 16),  # EAC_R11G11_UNORM
    157: (4, 4, 16),  # ASTC_4x4_UNORM
    165: (6, 6, 16),  # ASTC_6x6_UNORM
}

FORMAT_NAMES = {
    37: "R8G8B8A8_UNORM",
    157: "ASTC_4x4_UNORM",
    165: "ASTC_6x6_UNORM",
}

# KHR data format descriptor
KHR_DF_MODEL_ASTC = 162
KHR_DF_MODEL_RGBSDA = 1
KHR_DF_PRIMARIES_BT709 = 1
KHR_DF_TRANSFER_LINEAR = 1


def expected_level_size(vk_format: int, w: int, h: int) -> int:
    """Ktx2Subset.cpp::expected_level_size — the ONLY size the reader accepts."""
    bw, bh, bb = SUPPORTED_FORMATS[vk_format]
    return ((w + bw - 1) // bw) * ((h + bh - 1) // bh) * bb


def mip_sizes(w: int, h: int):
    """The chain the reader walks: w = w > 1 ? w / 2 : 1, down to 1x1, level 0 first."""
    sizes = [(w, h)]
    while sizes[-1] != (1, 1):
        cw, ch = sizes[-1]
        sizes.append((cw // 2 if cw > 1 else 1, ch // 2 if ch > 1 else 1))
    return sizes


def _dfd_block(vk_format: int) -> bytes:
    """Basic data format descriptor. The engine reader ignores it; the KTX2 spec
    and `ktx validate` do not, and writing it costs 44 bytes."""
    bw, bh, bb = SUPPORTED_FORMATS[vk_format]
    compressed = vk_format != VK_FORMAT_R8G8B8A8_UNORM
    n_samples = 1 if compressed else 4
    block_size = 24 + 16 * n_samples
    out = bytearray()
    out += struct.pack("<I", 4 + block_size)             # dfdTotalSize
    out += struct.pack("<I", 0)                          # vendorId(17) | descriptorType(15)
    out += struct.pack("<I", 2 | (block_size << 16))     # versionNumber | descriptorBlockSize
    out += bytes([KHR_DF_MODEL_ASTC if compressed else KHR_DF_MODEL_RGBSDA,
                  KHR_DF_PRIMARIES_BT709, KHR_DF_TRANSFER_LINEAR, 0])
    out += bytes([bw - 1, bh - 1, 0, 0])                 # texelBlockDimension0..3
    out += bytes([bb, 0, 0, 0, 0, 0, 0, 0])              # bytesPlane0..7
    if compressed:
        out += struct.pack("<HBB", 0, bb * 8 - 1, 0)     # bitOffset, bitLength-1, ASTC_DATA
        out += bytes([0, 0, 0, 0])                       # samplePosition0..3
        out += struct.pack("<II", 0, 0xFFFFFFFF)         # sampleLower / sampleUpper
    else:
        for ch_i in range(4):
            out += struct.pack("<HBB", ch_i * 8, 7, ch_i)
            out += bytes([0, 0, 0, 0])
            out += struct.pack("<II", 0, 255)
    assert len(out) == 4 + block_size
    return bytes(out)


def _kvd_block(writer: str) -> bytes:
    """Key/value data: KTXwriter, as the spec asks for."""
    out = bytearray()
    for key, value in (("KTXwriter", writer),):
        payload = key.encode("utf-8") + b"\0" + value.encode("utf-8") + b"\0"
        out += struct.pack("<I", len(payload))
        out += payload
        pad = (-len(payload)) % 4
        out += b"\0" * pad
    return bytes(out)


def write_ktx2(path: Path, vk_format: int, w: int, h: int, levels_big_to_small, writer: str):
    """Write the KTX2 subset file.

    Two orderings live in the same file and they are NOT the same ordering:
      * the LEVEL INDEX is ordered level 0 first = LARGEST first. That is what
        Ktx2Subset.cpp::parse walks (it starts at (width,height) and halves), and
        what ManagedAssets.cpp uploads (levels[first + i] with i=0 the base).
      * the LEVEL DATA is ordered SMALLEST first, as the KTX2 spec mandates.
    """
    n = len(levels_big_to_small)
    assert n == len(mip_sizes(w, h)), "not a complete mip chain"
    dfd = _dfd_block(vk_format)
    kvd = _kvd_block(writer)

    header_end = 12 + 9 * 4 + 4 * 4 + 2 * 8  # 80, == Ktx2Subset.cpp kHeaderEnd
    level_index_size = n * 24
    dfd_off = header_end + level_index_size
    kvd_off = dfd_off + len(dfd)
    kvd_end = kvd_off + len(kvd)
    # mip level data alignment = lcm(texel block size, 4)
    _, _, block_bytes = SUPPORTED_FORMATS[vk_format]
    align = block_bytes if block_bytes % 4 == 0 else block_bytes * 4
    data_start = kvd_end + (-kvd_end) % align

    # data smallest -> largest
    offsets = {}
    cursor = data_start
    blob = bytearray()
    for idx in range(n - 1, -1, -1):
        payload = levels_big_to_small[idx]
        pad = (-cursor) % align
        blob += b"\0" * pad
        cursor += pad
        offsets[idx] = cursor
        blob += payload
        cursor += len(payload)

    out = bytearray()
    out += KTX2_IDENTIFIER
    out += struct.pack("<IIIIIIIII",
                       vk_format,
                       1,      # typeSize (1 for block-compressed)
                       w, h,
                       0,      # pixelDepth (2D)
                       0,      # layerCount (non-array)
                       1,      # faceCount
                       n,      # levelCount
                       0)      # supercompressionScheme = none
    out += struct.pack("<IIII", dfd_off, len(dfd), kvd_off, len(kvd))
    out += struct.pack("<QQ", 0, 0)  # sgdByteOffset / sgdByteLength
    for idx in range(n):
        ln = len(levels_big_to_small[idx])
        out += struct.pack("<QQQ", offsets[idx], ln, ln)
    assert len(out) == dfd_off
    out += dfd
    out += kvd
    # the alignment gap between the key/value block and the first (smallest) level
    # is part of the FILE, not only of the offset arithmetic — forgetting to emit it
    # truncates the file by up to `align` bytes and the largest level runs past the
    # end. Caught by the mandatory re-read on the first real bake.
    out += b"\0" * (data_start - kvd_end)
    assert len(out) == data_start
    out += blob
    assert len(out) == cursor
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(bytes(out))


def verify_ktx2(path: Path):
    """Re-read a produced file with EXACTLY the checks Ktx2Subset.cpp::parse makes.

    Returns (ok, message, info). A file that does not pass this is never kept.
    """
    data = path.read_bytes()
    size = len(data)
    header_end = 12 + 9 * 4 + 4 * 4 + 2 * 8
    if size < header_end:
        return False, "ktx2: file too small", None
    if data[:12] != KTX2_IDENTIFIER:
        return False, "ktx2: bad identifier", None
    (vk_format, _type_size, width, height, depth, layer_count, face_count, level_count,
     scheme) = struct.unpack_from("<IIIIIIIII", data, 12)
    if vk_format not in SUPPORTED_FORMATS:
        return False, f"ktx2: unsupported vkFormat {vk_format}", None
    if scheme != 0:
        return False, f"ktx2: supercompression {scheme} not in subset", None
    if depth > 1 or layer_count > 1 or face_count != 1:
        return False, "ktx2: only plain 2D textures are in the subset", None
    if width == 0 or height == 0 or level_count == 0 or level_count > 16:
        return False, "ktx2: bad dimensions/levels", None
    if size < header_end + level_count * 24:
        return False, "ktx2: truncated level index", None
    levels = []
    w, h = width, height
    for i in range(level_count):
        off, ln, _un = struct.unpack_from("<QQQ", data, header_end + i * 24)
        if off + ln > size:
            return False, f"ktx2: level {i} out of bounds", None
        want = expected_level_size(vk_format, w, h)
        if ln != want:
            return False, f"ktx2: level {i} size {ln} != expected {want} for {w}x{h}", None
        levels.append((off, ln))
        w = w // 2 if w > 1 else 1
        h = h // 2 if h > 1 else 1
    # Beyond parse(): the chain must actually reach 1x1 (the engine assumes a full
    # chain, glTexStorage2D is told level_count and never generates mips).
    if (w, h) != (1, 1) or level_count != len(mip_sizes(width, height)):
        return False, (f"ktx2: incomplete mip chain ({level_count} levels for "
                       f"{width}x{height}, expected {len(mip_sizes(width, height))})"), None
    info = {"vk_format": vk_format, "width": width, "height": height,
            "level_count": level_count, "levels": levels, "size": size}
    return True, "ok", info


# ---------------------------------------------------------------------------
# astcenc driving
# ---------------------------------------------------------------------------

ASTC_MAGIC = bytes([0x13, 0xAB, 0xA1, 0x5C])


def find_astcenc(explicit):
    if explicit:
        p = Path(explicit)
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
        die(f"astcenc not executable at {p}")
    env = os.environ.get("ASTCENC")
    if env and Path(env).is_file():
        return env
    found = shutil.which("astcenc")
    if found:
        return found
    local = Path.home() / ".local" / "bin" / "astcenc"
    if local.is_file():
        return str(local)
    die("astcenc NOT FOUND. This tool cannot bake without it.\n"
        "  Install the ARM astc-encoder (https://github.com/ARM-software/astc-encoder),\n"
        "  put it on PATH or in ~/.local/bin/astcenc, or pass --astcenc <path>.\n"
        "  NOTE: baking is a SEPARATE step; android/build_custom_pack.sh never needs astcenc.")


def die(msg):
    sys.stderr.write("bake: " + msg + "\n")
    sys.exit(2)


def astc_payload(astc_path: Path, block_w: int, block_h: int, w: int, h: int) -> bytes:
    """Strip the 16-byte .astc header and check it describes what we asked for."""
    raw = astc_path.read_bytes()
    if len(raw) < 16 or raw[:4] != ASTC_MAGIC:
        raise RuntimeError(f"{astc_path}: not an .astc file")
    bx, by, bz = raw[4], raw[5], raw[6]
    dx = raw[7] | (raw[8] << 8) | (raw[9] << 16)
    dy = raw[10] | (raw[11] << 8) | (raw[12] << 16)
    dz = raw[13] | (raw[14] << 8) | (raw[15] << 16)
    if (bx, by, bz) != (block_w, block_h, 1) or (dx, dy, dz) != (w, h, 1):
        raise RuntimeError(f"{astc_path}: header says {bx}x{by}x{bz} block, {dx}x{dy}x{dz} image; "
                           f"asked for {block_w}x{block_h}, {w}x{h}")
    return raw[16:]


def make_astc_file(path: Path, payload: bytes, block_w: int, block_h: int, w: int, h: int):
    """Rebuild a standalone .astc (for `astcenc -dl` round-trips)."""
    hdr = bytearray(ASTC_MAGIC)
    hdr += bytes([block_w, block_h, 1])
    for v in (w, h, 1):
        hdr += bytes([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF])
    path.write_bytes(bytes(hdr) + payload)


def run_astcenc(astcenc, args, verbose):
    proc = subprocess.run([astcenc] + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout.decode("utf-8", "replace"))
        raise RuntimeError(f"astcenc failed ({proc.returncode}): {' '.join(args)}")
    if verbose:
        sys.stderr.write(proc.stdout.decode("utf-8", "replace"))


# ---------------------------------------------------------------------------
# Runtime statistics, recomputed offline
#   Every formula below is a transcription of game/graphics/opengl_renderer/
#   loader/LoaderStages.cpp. Float widths are matched on purpose (the engine
#   computes in float32 and accumulates in double).
# ---------------------------------------------------------------------------

F32_2_255 = np.float32(2.0) / np.float32(255.0)
F32_1_255 = np.float32(1.0) / np.float32(255.0)


def normal_dc_stats(rgba: np.ndarray) -> dict:
    """LoaderStages.cpp `NORMAL-MAP DC`:
         nx = r*2/255-1 ; ny = g*2/255-1 ; nz = max(b*2/255-1, 0.05)
         dc = mean(clamp(nx/nz, +-4)), mean(clamp(ny/nz, +-4))"""
    r = rgba[..., 0].astype(np.float32) * F32_2_255 - np.float32(1.0)
    g = rgba[..., 1].astype(np.float32) * F32_2_255 - np.float32(1.0)
    b = np.maximum(rgba[..., 2].astype(np.float32) * F32_2_255 - np.float32(1.0),
                   np.float32(0.05))
    gx = np.clip(r / b, np.float32(-4.0), np.float32(4.0))
    gy = np.clip(g / b, np.float32(-4.0), np.float32(4.0))
    n = gx.size
    dc_x = float(np.float32(np.sum(gx, dtype=np.float64) / n))
    dc_y = float(np.float32(np.sum(gy, dtype=np.float64) / n))
    tilt = math.degrees(math.atan(math.sqrt(dc_x * dc_x + dc_y * dc_y)))
    return {"normal_dc_x": dc_x, "normal_dc_y": dc_y, "normal_tilt_deg": tilt}


def height_stats(rgba: np.ndarray) -> dict:
    """LoaderStages.cpp `HEIGHT-MAP STATISTICS`: mean of R/255, robust half-range
    from the 2nd/98th percentile of the 256-bin histogram, height_norm = 0.5/half."""
    r = rgba[..., 0]
    npx = int(r.size)
    hist = np.bincount(r.ravel(), minlength=256).astype(np.int64)
    cum = np.cumsum(hist)
    mean = np.float32(int(r.sum(dtype=np.uint64)) / float(npx) / 255.0)
    lo_target = int(npx * 0.02)
    hi_target = int(npx * 0.98)
    idx_lo = int(np.searchsorted(cum, lo_target, side="left"))
    idx_hi = int(np.searchsorted(cum, hi_target, side="left"))
    p2_b = idx_lo if idx_lo < 256 else 0
    p98_b = idx_hi if idx_hi < 256 else 255
    p2 = np.float32(p2_b) / np.float32(255.0)
    p98 = np.float32(p98_b) / np.float32(255.0)
    half = max(p98 - mean, mean - p2)
    half = max(half, np.float32(2.0) / np.float32(255.0))
    norm = min(max(np.float32(0.5) / half, np.float32(0.5)), np.float32(16.0))
    return {"height_mean": float(mean), "height_p2": float(p2), "height_p98": float(p98),
            "height_half": float(half), "height_norm": float(norm)}


def height_lambda_tiles(rgba: np.ndarray) -> float:
    """LoaderStages.cpp `measure_height_lambda_tiles` — feature wavelength in TILES."""
    h, w = rgba.shape[0], rgba.shape[1]
    if w <= 0 or h <= 0:
        return 0.25
    step = max(1, max(w, h) // 1024)
    cw0 = max(1, (w + step - 1) // step)
    ch0 = max(1, (h + step - 1) // step)
    buf = np.ascontiguousarray(rgba[0:h:step, 0:w:step, 0]).astype(np.float32) * F32_1_255

    def variance(v):
        n = v.size
        if n == 0:
            return 0.0
        s = float(np.sum(v, dtype=np.float64))
        s2 = float(np.sum(v.astype(np.float64) ** 2))
        mean = s / n
        return max(s2 / n - mean * mean, 0.0)

    var0 = variance(buf)
    if var0 < 1e-8:
        return 0.25
    target = 0.5 * var0
    var_prev = var0
    cw, ch = cw0, ch0
    l_last = 0
    l_star = 0.0
    crossed = False
    l = 1
    while cw >= 2 and ch >= 2 and l <= 12:
        nw, nh = cw // 2, ch // 2
        a = buf[0:2 * nh:2, 0:2 * nw:2]
        b = buf[0:2 * nh:2, 1:2 * nw:2]
        c = buf[1:2 * nh:2, 0:2 * nw:2]
        d = buf[1:2 * nh:2, 1:2 * nw:2]
        buf = (((a + b) + c) + d) * np.float32(0.25)
        cw, ch = nw, nh
        l_last = l
        var_l = variance(buf)
        if var_l <= target:
            t = 0.0
            if var_prev > 0.0 and var_l > 0.0:
                denom = math.log(var_prev) - math.log(var_l)
                t = (math.log(var_prev) - math.log(target)) / max(denom, 1e-12)
            l_star = float(l - 1) + min(max(t, 0.0), 1.0)
            crossed = True
            break
        var_prev = var_l
        l += 1
    if not crossed:
        l_star = float(l_last)
    lambda_texels = float(np.float32(2.0 ** (l_star + 1.0)))
    lambda_tiles = lambda_texels / float(max(cw0, ch0))
    return float(min(max(lambda_tiles, 1.0 / 1024.0), 1.0))


def channel_r_stats(rgba: np.ndarray) -> dict:
    """LoaderStages.cpp `pbr roughness data`: min/mean/max of channel R, /255."""
    r = rgba[..., 0]
    npx = int(r.size)
    return {"r_min": float(int(r.min()) / 255.0),
            "r_mean": float(int(r.sum(dtype=np.uint64)) / npx / 255.0),
            "r_max": float(int(r.max()) / 255.0)}


def stats_for_map(kind: str, rgba: np.ndarray) -> dict:
    out = {}
    if kind == "_normal":
        out.update(normal_dc_stats(rgba))
    elif kind == "_height":
        out.update(height_stats(rgba))
        out["height_lambda_tiles"] = height_lambda_tiles(rgba)
    elif kind == "_roughness":
        out.update(channel_r_stats(rgba))
    return out


# ---------------------------------------------------------------------------
# Bake
# ---------------------------------------------------------------------------

NORMAL_SUFFIX = "_normal"


def map_kind(material: str, stem: str) -> str:
    """"" for the base colour map, "_normal"/"_roughness"/... otherwise."""
    if stem == material:
        return ""
    if stem.startswith(material + "_"):
        return stem[len(material):]
    return "_" + stem.split("_")[-1]


def block_for(kind: str):
    # `_normal` is the fragile map: 4x4 (8.00 bpp). Everything else: 6x6 (3.56 bpp).
    if kind == NORMAL_SUFFIX:
        return 4, 4, VK_FORMAT_ASTC_4x4_UNORM
    return 6, 6, VK_FORMAT_ASTC_6x6_UNORM


def load_rgba(path: Path):
    """PIL sniffs the CONTENT, not the extension — four `*.png` in this set are
    actually JPEG (vil-beach-01*), and the runtime's stbi_load sniffs too."""
    with Image.open(path) as im:
        fmt = im.format
        mode = im.mode
        rgba = im.convert("RGBA")
        arr = np.asarray(rgba, dtype=np.uint8)
        level0 = rgba.copy()
    return arr, level0, fmt, mode


def bake_map(astcenc, src: Path, dst: Path, kind: str, tmpdir: Path, quality: str,
             verbose: bool, skip_existing: bool):
    t0 = time.time()
    arr, level0, src_fmt, src_mode = load_rgba(src)
    h, w = arr.shape[0], arr.shape[1]
    block_w, block_h, vk_format = block_for(kind)
    sizes = mip_sizes(w, h)

    stats = stats_for_map(kind, arr)

    if skip_existing and dst.is_file():
        ok, msg, info = verify_ktx2(dst)
        if ok and info["width"] == w and info["height"] == h and info["vk_format"] == vk_format:
            return {"skipped": True, "w": w, "h": h, "levels": info["level_count"],
                    "vk_format": vk_format, "bytes": info["size"], "stats": stats,
                    "src_format": src_fmt, "src_mode": src_mode,
                    "src_bytes": src.stat().st_size, "seconds": time.time() - t0}

    payloads = []
    for li, (lw, lh) in enumerate(sizes):
        png_in = tmpdir / f"lvl{li}.png"
        astc_out = tmpdir / f"lvl{li}.astc"
        # EVERY level is a box reduction OF LEVEL 0, never of the previous level:
        # cascading a box filter drifts (each pass re-filters already-filtered data).
        img = level0 if (lw, lh) == (w, h) else level0.resize((lw, lh), Image.BOX)
        img.save(png_in, format="PNG", compress_level=1)
        run_astcenc(astcenc, ["-cl", str(png_in), str(astc_out), f"{block_w}x{block_h}", quality],
                    verbose)
        payload = astc_payload(astc_out, block_w, block_h, lw, lh)
        want = expected_level_size(vk_format, lw, lh)
        if len(payload) != want:
            raise RuntimeError(f"{src}: level {li} {lw}x{lh} -> {len(payload)} B, "
                               f"the reader demands exactly {want} B")
        payloads.append(payload)
        png_in.unlink(missing_ok=True)
        astc_out.unlink(missing_ok=True)

    writer = f"tools/bake_recharged_textures.py (astcenc {quality} {block_w}x{block_h})"
    tmp_ktx = tmpdir / "out.ktx2"
    write_ktx2(tmp_ktx, vk_format, w, h, payloads, writer)
    ok, msg, info = verify_ktx2(tmp_ktx)
    if not ok:
        raise RuntimeError(f"{src}: produced KTX2 REJECTED by the reader's own checks: {msg}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(tmp_ktx), str(dst))
    # And once more where it will actually be read from.
    ok, msg, info = verify_ktx2(dst)
    if not ok:
        dst.unlink(missing_ok=True)
        raise RuntimeError(f"{dst}: rejected after move: {msg}")
    return {"skipped": False, "w": w, "h": h, "levels": info["level_count"],
            "vk_format": vk_format, "bytes": info["size"], "stats": stats,
            "src_format": src_fmt, "src_mode": src_mode, "src_bytes": src.stat().st_size,
            "seconds": time.time() - t0}


def roundtrip_control(astcenc, ktx2_path: Path, kind: str, tmpdir: Path, verbose: bool):
    """Decompress level 0 back out of the WRITTEN ktx2 and recompute the same
    statistics on it. A statistic that moved is a statistic the compression ate,
    and we want to know before the owner does."""
    ok, msg, info = verify_ktx2(ktx2_path)
    if not ok:
        raise RuntimeError(f"{ktx2_path}: {msg}")
    data = ktx2_path.read_bytes()
    off, ln = info["levels"][0]
    bw, bh, _ = SUPPORTED_FORMATS[info["vk_format"]]
    astc_p = tmpdir / "ctrl.astc"
    png_p = tmpdir / "ctrl.png"
    make_astc_file(astc_p, data[off:off + ln], bw, bh, info["width"], info["height"])
    run_astcenc(astcenc, ["-dl", str(astc_p), str(png_p)], verbose)
    with Image.open(png_p) as im:
        arr = np.asarray(im.convert("RGBA"), dtype=np.uint8)
    out = stats_for_map(kind, arr)
    astc_p.unlink(missing_ok=True)
    png_p.unlink(missing_ok=True)
    return out


def human(n):
    return f"{n / (1024 * 1024):.2f} MiB"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--game", default="jak1")
    ap.add_argument("--src", default=None, help="default: custom_assets/<game>/recharged_textures")
    ap.add_argument("--out", default=None,
                    help="default: custom_assets/<game>/recharged_textures_baked/astc")
    ap.add_argument("--astcenc", default=None)
    ap.add_argument("--quality", default="-thorough",
                    help="astcenc quality: a preset ('thorough', '-thorough', ...) or a float "
                         "0-100. Note argparse: write --quality=-fast, not --quality -fast.")
    ap.add_argument("--only", action="append", default=[],
                    help="material name (repeatable); default = all")
    ap.add_argument("--skip-existing", action="store_true",
                    help="keep a .ktx2 that already verifies (stats are still recomputed)")
    ap.add_argument("--control", action="append", default=[],
                    help="material to ALSO round-trip through `astcenc -dl` and compare "
                         "statistics on ('all' for every material)")
    ap.add_argument("--control-json", default=None, help="write the comparison to this path")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    # astcenc presets are spelled with a leading dash; accept both spellings so
    # `--quality thorough` does not trip argparse's option parsing.
    if args.quality and not args.quality.startswith("-"):
        try:
            float(args.quality)
        except ValueError:
            args.quality = "-" + args.quality

    root = Path(__file__).resolve().parent.parent
    src_root = Path(args.src) if args.src else root / "custom_assets" / args.game / "recharged_textures"
    out_root = (Path(args.out) if args.out else
                root / "custom_assets" / args.game / "recharged_textures_baked" / "astc")
    if not src_root.is_dir():
        die(f"source directory not found: {src_root}")
    astcenc = find_astcenc(args.astcenc)
    print(f"[bake] astcenc  : {astcenc}")
    print(f"[bake] source   : {src_root}")
    print(f"[bake] output   : {out_root}")
    print(f"[bake] quality  : {args.quality}  (normal=4x4, others=6x6)")

    orm_tmp = tempfile.TemporaryDirectory(prefix="bake-orm-")
    orm_dir = Path(orm_tmp.name)
    materials = {}
    for f in sorted(src_root.rglob("*.png")):
        mat_dir = f.parent
        tpage = mat_dir.parent.name
        material = mat_dir.name
        materials.setdefault((tpage, material), []).append(f)
    if args.only:
        materials = {k: v for k, v in materials.items() if k[1] in args.only}

    # Gmemory-ceiling-and-crash : L'ORM EST DEBALLE ICI, HORS LIGNE.
    #
    # L'ORM (occlusion / rugosite / metal empaquetes en R / G / B) n'etait deballe que par le
    # chemin PNG (LoaderStages.cpp, branche `if (orm)`), qui a la decision facile : il tient
    # les pixels decodes et fait trois `make_channel`. Le chemin KTX2 ne peut pas : ses images
    # sont compressees GPU, il n'y a plus de pixel a lire. Le cycle precedent en avait conclu
    # qu'un materiau portant un _orm ne pouvait pas etre pre-cuit — c'etait exact pour le
    # RUNTIME, faux pour la CUISSON. Le deballage n'a pas besoin d'etre fait au chargement : il
    # est fait ici, une fois, et les trois plans deviennent des cartes DEDIEES.
    #
    # Ca ne cree aucun genre nouveau cote moteur : `_ao` et `_metallic` sont deja des suffixes
    # que le chemin pre-cuit charge (`load_map("ao")`, `load_map("metallic")`), et la regle
    # « une carte DEDIEE gagne sur la carte empaquetee » du chemin PNG donne exactement le
    # meme resultat des deux cotes. Le canal G (rugosite) n'est extrait que si le materiau
    # n'a PAS de _roughness dedie — sinon le dedie gagne, comme au runtime.
    #
    # Le _orm.png lui-meme reste dans le pack et n'est PAS cuit : c'est lui qui sert sur une
    # cible sans ASTC (le bureau), ou le chemin PNG est inchange.
    orm_unpacked = []
    for key in sorted(materials):
        tpage, material = key
        files = materials[key]
        orm = next((f for f in files if f.stem == material + "_orm"), None)
        if orm is None:
            continue
        has_dedicated = {f.stem[len(material):] for f in files if f.stem.startswith(material + "_")}
        want = [("_ao", 0), ("_metallic", 2)]
        if "_roughness" not in has_dedicated:
            want.append(("_roughness", 1))
        arr, _lvl0, _fmt, _mode = load_rgba(orm)
        stage = orm_dir / tpage / material
        stage.mkdir(parents=True, exist_ok=True)
        made = []
        for suffix, chan in want:
            if suffix in has_dedicated:
                continue  # un fichier dedie existe deja : il gagne, on ne le remplace pas.
            plane = arr[:, :, chan]
            gray = np.dstack([plane, plane, plane,
                              np.full_like(plane, 255)])
            out = stage / f"{material}{suffix}.png"
            Image.fromarray(gray, mode="RGBA").save(out, format="PNG", compress_level=1)
            files.append(out)
            made.append(suffix)
        files[:] = [f for f in files if f is not orm]
        orm_unpacked.append(f"{tpage}/{material}[{','.join(made) or 'rien'}]")
    if orm_unpacked:
        print(f"[bake] ORM DEBALLE HORS LIGNE en cartes dediees : {', '.join(orm_unpacked)}")

    if not materials:
        die("no material found")

    controls = set(args.control)
    control_all = "all" in controls
    control_rows = []
    total_src = total_dst = 0
    n_written = n_verified = n_failed = 0
    failures = []
    rows = []
    t_start = time.time()

    with tempfile.TemporaryDirectory(prefix="bake-rtex-") as td:
        tmpdir = Path(td)
        for (tpage, material), files in sorted(materials.items()):
            mat_src = mat_dst = 0
            maps_json = {}
            print(f"\n[bake] {tpage}/{material}  ({len(files)} maps)")
            for f in sorted(files):
                kind = map_kind(material, f.stem)
                dst = out_root / tpage / material / (f.stem + ".ktx2")
                try:
                    r = bake_map(astcenc, f, dst, kind, tmpdir, args.quality, args.verbose,
                                 args.skip_existing)
                except Exception as e:  # noqa: BLE001 — report, never half-write
                    n_failed += 1
                    failures.append(f"{f}: {e}")
                    print(f"  FAILED {f.name}: {e}")
                    continue
                n_written += 0 if r["skipped"] else 1
                n_verified += 1
                bw, bh, _ = SUPPORTED_FORMATS[r["vk_format"]]
                mat_src += r["src_bytes"]
                mat_dst += r["bytes"]
                rows.append((f"{tpage}/{material}/{f.stem}", f"{bw}x{bh}", r["levels"],
                             r["src_bytes"], r["bytes"], r["seconds"], r["src_format"]))
                print(f"  {f.name:52s} {r['w']}x{r['h']} {bw}x{bh} "
                      f"levels={r['levels']:2d} {r['src_bytes']:>9d} -> {r['bytes']:>9d} B "
                      f"({r['seconds']:5.1f}s{' skipped' if r['skipped'] else ''})")
                entry = {"file": f.stem + ".ktx2", "source": f.name,
                         "source_format": r["src_format"], "source_mode": r["src_mode"],
                         "w": r["w"], "h": r["h"], "levels": r["levels"],
                         "vk_format": r["vk_format"],
                         "format": FORMAT_NAMES.get(r["vk_format"], str(r["vk_format"])),
                         "block": f"{bw}x{bh}", "bytes": r["bytes"]}
                entry.update(r["stats"])
                maps_json[kind if kind else "base"] = entry

                if (control_all or material in controls) and r["stats"]:
                    try:
                        after = roundtrip_control(astcenc, dst, kind, tmpdir, args.verbose)
                    except Exception as e:  # noqa: BLE001
                        failures.append(f"control {f}: {e}")
                        print(f"  control FAILED {f.name}: {e}")
                    else:
                        control_rows.append({"map": f"{tpage}/{material}/{f.stem}", "kind": kind,
                                             "png": r["stats"], "ktx2_decompressed": after})
            total_src += mat_src
            total_dst += mat_dst
            if maps_json:
                stats_path = out_root / tpage / material / f"{material}.stats.json"
                stats_path.parent.mkdir(parents=True, exist_ok=True)
                doc = {
                    "schema": "recharged-baked-textures/1",
                    "tpage": tpage,
                    "material": material,
                    "note": ("Statistics the PNG path computed at runtime from decoded pixels "
                             "(LoaderStages.cpp). The KTX2 path never decodes, so they are "
                             "computed here from the SOURCE pixels with the same formulas."),
                    "maps": maps_json,
                }
                stats_path.write_text(json.dumps(doc, indent=2, sort_keys=True) + "\n")
                print(f"  -> {stats_path.relative_to(out_root)}  "
                      f"({human(mat_src)} -> {human(mat_dst)})")

    dt = time.time() - t_start
    print("\n" + "=" * 96)
    print(f"{'map':56s} {'block':>6s} {'lvls':>5s} {'src B':>10s} {'ktx2 B':>10s} {'s':>6s}")
    for name, blk, lvls, sb, db, sec, _fmt in rows:
        print(f"{name:56s} {blk:>6s} {lvls:5d} {sb:10d} {db:10d} {sec:6.1f}")
    print("=" * 96)
    print(f"[bake] produced/verified : {n_written} written, {n_verified} verified, "
          f"{n_failed} failed")
    print(f"[bake] on disk           : {human(total_src)} PNG -> {human(total_dst)} KTX2 "
          f"({100.0 * total_dst / max(total_src, 1):.1f} %)")
    print(f"[bake] wall clock        : {dt:.1f} s")

    if control_rows:
        print("\n[bake] NON-REGRESSION CONTROL — statistics from PNG pixels vs from the "
              "DECOMPRESSED ktx2")
        for c in control_rows:
            print(f"  {c['map']} ({c['kind'] or 'base'})")
            keys = sorted(set(c["png"]) | set(c["ktx2_decompressed"]))
            for k in keys:
                a = c["png"].get(k)
                b = c["ktx2_decompressed"].get(k)
                if a is None or b is None:
                    print(f"    {k:22s} png={a} ktx2={b}")
                    continue
                d = b - a
                rel = (abs(d) / abs(a) * 100.0) if a else float("nan")
                print(f"    {k:22s} png={a:12.6f}  ktx2={b:12.6f}  delta={d:+12.6f}  "
                      f"({rel:6.2f} %)")
        if args.control_json:
            Path(args.control_json).write_text(json.dumps(control_rows, indent=2) + "\n")
            print(f"  -> {args.control_json}")

    if failures:
        print("\n[bake] FAILURES:")
        for f in failures:
            print("  " + f)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
