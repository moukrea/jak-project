#!/usr/bin/env python3
"""Gloading-screen — fabrique un fichier de rejeu de manette (`pad_replay`).

L'owner 2026-08-29 : « J'avais explicitement demande de capturer cette animation in game ».
Pour capturer l'animation de COURSE il faut que Jak COURE, et il n'existe aucune injection de
manette cote x86 (grep `cpad_inject` : une seule occurrence, et c'est un commentaire qui dit que
ce chemin N'EXISTE PAS ici). Le harnais `game/system/pad_replay.{h,cpp}` -- ecrit pour la phase
Ginput-replay -- lit un fichier de manette et le rejoue A LA FRAME DE LOGIQUE, en forcant en plus
un pas de temps fixe de 1/60 s. C'est exactement ce qu'il faut : la capture d'ecran par frame
ecroule le debit d'images, et sans pas fixe l'animation serait echantillonnee n'importe comment.

Format, lu dans pad_replay.cpp:35-45 et :56-64 (et la validation a l'ouverture, :224-232, qui ne
verifie QUE la signature et la taille d'enregistrement) :
  en-tete 64 o : magic "OGPADRP1", version u32, record_size u32, seed u32, reserved u32,
                 anchor_frame i64, fingerprint[32]
  puis N x 6 o : button0 u16, leftx u8, lefty u8, rightx u8, righty u8   (127 = repos)

L'index 0 est la premiere frame de logique APRES l'apparition de Jak (l'ancre), pas la premiere
frame rendue : le demarrage et le chargement, de duree variable, sont absorbes.
"""

import argparse
import struct

NEUTRAL = 127


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--settle", type=int, default=240,
                    help="frames de logique au repos avant de pousser le stick "
                         "(Jak retombe au sol et la camera est posee pendant ce temps)")
    ap.add_argument("--run", type=int, default=1200, help="frames de logique stick a fond")
    ap.add_argument("--leftx", type=int, default=255, help="0=gauche 127=repos 255=droite")
    ap.add_argument("--lefty", type=int, default=NEUTRAL, help="0=avant 127=repos 255=arriere")
    a = ap.parse_args()

    hdr = struct.pack("<8sIIIIq32s", b"OGPADRP1", 2, 6, 0x0AD12345, 0, 0, b"\0" * 32)
    assert len(hdr) == 64, len(hdr)

    recs = bytearray()
    for _ in range(a.settle):
        recs += struct.pack("<HBBBB", 0, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL)
    for _ in range(a.run):
        recs += struct.pack("<HBBBB", 0, a.leftx, a.lefty, NEUTRAL, NEUTRAL)

    with open(a.out, "wb") as f:
        f.write(hdr)
        f.write(recs)
    print("PADDEMO out=%s repos=%d course=%d leftx=%d lefty=%d octets=%d"
          % (a.out, a.settle, a.run, a.leftx, a.lefty, 64 + len(recs)))


if __name__ == "__main__":
    main()
