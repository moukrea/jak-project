#!/usr/bin/env python3
"""Phase Gtext-tone — TABLE contre EXECUTION, cote a cote.

Le validateur de la phase exige « les valeurs REELLEMENT utilisees a cote de celles de la
table ». Trois colonnes, trois provenances INDEPENDANTES, pour le meme id :

  TABLE      la source : ce que resout la chaine game_text.gp (decomp -> case -> custom)
  BANQUE     l'octet livre : decode de out/jak1/iso/<n>COMMON.TXT (gtt_bank_probe.py)
  EXECUTION  ce que le PROGRAMME rend : (lookup-text! *common-text* (text-id <nom>) #f),
             imprime par le jeu lui-meme (gtt_runtime_lookup.sh)

Pourquoi les trois et pas une : le dossier a livre pendant 17 jours une copie GELEE du texte
(commit a137796a4a) — la TABLE etait juste, la BANQUE livree etait vieille, et rien ne le
disait. Et une banque juste ne prouve pas encore que le programme resout le bon ID : une cle
JSON decimale la poserait ailleurs (text_ser.cpp:250 parse en HEX) sans que l'octet bouge.

COMPARAISON — sur quoi porte l'egalite
--------------------------------------
`format 0` imprime les OCTETS DE JEU bruts : un accent y apparait comme la sequence de plume
`e~Y~-14H~-1V'~Z`, et l'octet d'accent lui-meme ne survit pas au journal. La banque, elle, est
decodee en UTF-8. On ne peut donc pas exiger l'egalite litterale sur les chaines accentuees.
On compare donc le SQUELETTE ASCII : sequences `~...` retirees, non-ASCII retire, espaces
normalises. C'est plus faible qu'une egalite d'octets, et c'est DIT ici — mais ca discrimine
tout ce qui compte : un id faux, une banque perimee, une langue non chargee, une chaine non
remplacee rendent tous un squelette different.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import unicodedata

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
probe = __import__("gtt_bank_probe")
tone = __import__("gtt_apply_tone")

# nom symbolique (engine/ui/text-h.gc) -> id hex
NAMES = {
    "press-start": "16e", "move-dpad": "113", "select-file-to-save": "140",
    "select-file-to-load": "141", "insert-memcard": "143",
    "memcard-space-requirement2": "134", "memcard-do-not-remove": "138",
    "autosave-disabled-msg": "158", "check-memcard": "15b",
    "autosave-warn-msg": "161", "check-memcard-and-retry": "163",
    "no-disc-msg": "16b", "bad-disc-msg": "16d",
}
BANK = {"en-US": 0, "fr-FR": 1, "de-DE": 2, "es-ES": 3, "it-IT": 4}


def skeleton(s):
    """Squelette comparable entre une chaine UTF-8 et un journal d'octets de jeu.

    Trois classes de caracteres ne survivent pas a `format 0` et sont donc retirees des DEUX
    cotes, sinon elles fabriquent de faux desaccords (mesure : 41 sur 65 avant ce filtre) :
      - les sequences de plume `~Y ~-14H ~Z` qui portent les accents ;
      - `_`, qui n'est pas un souligne mais l'ESPACE LARGE (octet 0x03) des chaines Sony
        `MEMORY_CARD_(PS2)` — un octet < 0x20, absent du journal ;
      - l'apostrophe, encodee hors ASCII par la police (`l'opzione` -> `lopzione`).
    Et les accents sont REPLIES sur leur lettre de base (NFD puis retrait des diacritiques) :
    la banque dit `a`, le journal dit `a` suivi d'une sequence de plume qu'on vient de retirer.
    NFD et non NFKD, pour que `º` (l'ordinal de `Memory_Card_n_~D`) reste non-ASCII et tombe
    des deux cotes, comme il tombe dans le journal.
    Ce qui reste discrimine tout ce qui compte : id faux, banque perimee, langue non chargee.
    """
    s = re.sub(r"~[+-]?\d*[A-Za-z]", "", s)      # ~Y ~-14H ~Z ~33L ... : plume, pas du texte
    s = s.replace("_", "").replace("'", "").replace("\u2019", "")
    s = "".join(c for c in unicodedata.normalize("NFD", s) if not unicodedata.combining(c))
    s = "".join(c for c in s if 32 <= ord(c) < 127)
    return re.sub(r"\s+", " ", s).strip().lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runtime", default=".autoport/reports/Gtext-tone/runtime-lookup.txt")
    ap.add_argument("--out", default=".autoport/reports/Gtext-tone/table-vs-runtime.txt")
    a = ap.parse_args()

    rt = {}
    for line in open(os.path.join(ROOT, a.runtime), encoding="utf-8"):
        m = re.match(r"^GTT (\S+) (\S+) (.*)$", line.rstrip("\n"))
        if m:
            rt[(m.group(1), m.group(2))] = m.group(3)

    enc, rep = probe.load_font_db()
    t12, t24 = probe.load_advance_tables()

    L = [
        "# Gtext-tone — TABLE contre EXECUTION, cote a cote",
        "#",
        "#   TABLE      source resolue par game_text.gp : decomp -> game_case_text -> game_custom_text",
        "#   BANQUE     octets livres, decodes de out/jak1/iso/<n>COMMON.TXT",
        "#   EXECUTION  (lookup-text! *common-text* (text-id <nom>) #f) imprime par le JEU",
        "#",
        "# Egalite comparee sur le SQUELETTE ASCII (les sequences de plume `~...` d'accent ne",
        "# survivent pas au journal de `format 0`). Voir l'en-tete du script.",
        "",
    ]
    tot = bad = 0
    for lang, lid in BANK.items():
        bankfile = os.path.join(ROOT, "out", "jak1", "iso", "%dCOMMON.TXT" % lid)
        _blang, entries = probe.read_bank(bankfile)
        eff = tone.effective(lang)
        L.append("## %s  (banque %dCOMMON.TXT, language-id lu dans la banque = %d)" % (lang, lid, _blang))
        for name, ident in NAMES.items():
            table = eff.get(ident, ("<ABSENT>", "-"))[0]
            raw = entries.get(ident)
            bank = probe.decode(raw, _blang, enc, rep) if raw is not None else "<ABSENT>"
            run = rt.get((lang, name), "<NON MESURE>")
            tot += 1
            ok = skeleton(table) == skeleton(bank) == skeleton(run)
            if not ok:
                bad += 1
            L.append("  #x%-5s %-27s %s" % (ident, name, "ACCORD" if ok else "*** DESACCORD ***"))
            L.append("     TABLE      %s" % table)
            L.append("     BANQUE     %s" % bank)
            L.append("     EXECUTION  %s" % run)
        L.append("")
    L.append("## VERDICT")
    L.append("  %d comparaisons, %d en accord, %d en desaccord." % (tot, tot - bad, bad))
    if bad == 0:
        L.append("  La chaine que le programme RESOUT est, sur les 5 langues et les 13 ids, celle")
        L.append("  de la source. Ni copie gelee, ni id decale.")
    txt = "\n".join(L) + "\n"
    open(os.path.join(ROOT, a.out), "w", encoding="utf-8").write(txt)
    print(txt)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
