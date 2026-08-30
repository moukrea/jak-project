#!/usr/bin/env python3
"""Ggrass-density-presets — lit l'EN-TETE d'un `.grassbake` sans lancer le jeu.

POURQUOI CET OUTIL EXISTE. Le moteur refuse un bake dont `fr3_size` ne correspond pas au `.fr3`
qu'il charge (`GrassRenderer.cpp`, « fr3 size mismatch ») — c'est le defaut qui a fait basculer
l'appareil sur le placement EN DIRECT a chaque chargement. Le seul moyen de l'attraper AVANT la
livraison est de lire l'en-tete du bake et de le comparer au fr3 qui part avec lui. Ce fichier est
donc lu par l'empaqueteur (garde dure) ET par le validateur de phase, qui ne se font pas confiance
mutuellement : chacun relit le fichier livre.

Disposition (apres decompression), telle que `save_bake()` l'ecrit :
    0  u32   magic 'GBK1' 0x314B4247
    4  u32   version de format
    8  u32   version tfrag3
   12  char[32] nom du niveau
   44  u64   fr3_size
   52  f32   bake_density_pct
   56  f32   floor_gap_m
   60  f32   total_area_m2
   64  u32   ntris
   68  u64   ncand
Le fichier lui-meme est : u64 taille non compressee, puis une trame zstd (`compress.cpp`).
"""
import struct
import subprocess
import sys

GBK_MAGIC = 0x314B4247


def read_header(path):
    with open(path, "rb") as fh:
        blob = fh.read()
    if len(blob) < 8:
        raise ValueError(f"{path}: trop court ({len(blob)} octets)")
    # 8 octets de taille non compressee, puis la trame zstd.
    try:
        proc = subprocess.run(
            ["zstd", "-dc"], input=blob[8:], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
    except FileNotFoundError:
        raise SystemExit("erreur: la commande `zstd` est absente — impossible de lire un .grassbake")
    raw = proc.stdout
    if len(raw) < 76:
        raise ValueError(f"{path}: decompression trop courte ({len(raw)} octets) — {proc.stderr[:200]!r}")
    magic, fmt, tfv = struct.unpack_from("<III", raw, 0)
    if magic != GBK_MAGIC:
        raise ValueError(f"{path}: magic {magic:#010x} != {GBK_MAGIC:#010x}")
    name = raw[12:44].split(b"\0")[0].decode("ascii", "replace")
    fr3_size, dens, gap, area = struct.unpack_from("<Qfff", raw, 44)
    ntris, ncand = struct.unpack_from("<IQ", raw, 64)
    return {
        "fichier": path,
        "octets": len(blob),
        "format": fmt,
        "tfrag3": tfv,
        "niveau": name,
        "fr3_size": fr3_size,
        "densite": dens,
        "floor_gap": gap,
        "aire_m2": area,
        "ntris": ntris,
        "ncand": ncand,
    }


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    rc = 0
    for path in argv[1:]:
        try:
            h = read_header(path)
        except Exception as exc:  # noqa: BLE001 - on veut le message brut
            print(f"GRASSBAKEHDR fichier={path} erreur={exc}")
            rc = 1
            continue
        print(
            "GRASSBAKEHDR fichier={fichier} octets={octets} format={format} tfrag3={tfrag3} "
            "niveau={niveau} fr3_size={fr3_size} densite={densite:.1f} floor_gap={floor_gap:.3f} "
            "aire_m2={aire_m2:.1f} ntris={ntris} ncand={ncand}".format(**h)
        )
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
