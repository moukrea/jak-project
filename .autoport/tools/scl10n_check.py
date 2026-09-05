#!/usr/bin/env python3
"""Verificateur des libelles du menu Recharged (item recharged-settings-case-l10n).

Ce n'est PAS une porte : `validators/generic.sh` juge `proof.txt`, ecrit par le moteur.
C'est l'outil de labo qui empeche d'ecrire une chaine que la chaine de build refuserait,
que la phase de casse reecrirait, ou que l'instrument compterait comme un defaut.

Quatre controles, dans cet ordre :
  1. ENCODABLE  — chaque caractere existe dans la police jak1 (`common/util/font/dbs/
     font_db_jak1.cpp`). Un caractere absent n'echoue PAS le build : `encode_utf8_to_game`
     recopie les octets UTF-8 un par un et l'ecran affiche du charabia, en silence.
  2. POINT FIXE — passer la chaine dans le `Caser` de `recharged_assets/font/gen_mixed_case.py`
     ne doit rien changer. Sinon la prochaine passe de casse reecrit le libelle.
  3. CASSE      — aucun mot ordinaire (ni sigle, ni jeton numerique) en tout-majuscules.
     Meme regle que `game/system/settings_case_l10n.cpp:is_shouting`.
  4. IDENTITE   — dans une langue traduite, la chaine ne doit pas etre l'anglais mot pour mot,
     sauf si l'anglais ne contient que des sigles.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "recharged_assets", "font"))
TEXTDIR = os.path.join(ROOT, "game", "assets", "jak1", "text")
FONTDB = os.path.join(ROOT, "common", "util", "font", "dbs", "font_db_jak1.cpp")

# id de langue -> locale, lu de game/assets/jak1/game_text.gp
LOCALES = {
    0: "en-US", 1: "fr-FR", 2: "de-DE", 3: "es-ES", 4: "it-IT", 5: "ja-JP", 6: "en-GB",
    7: "pt-PT", 8: "fi-FI", 9: "sv-SE", 10: "da-DK", 11: "no-NO", 12: "nl-NL", 13: "pt-BR",
    14: "hu-HU", 15: "ca-ES", 16: "is-IS", 19: "pl-PL", 20: "lt-LT", 21: "cs-CZ",
    22: "hr-HR", 23: "gl-ES", 24: "bs-BA",
}
# en-US et en-GB sont de l'anglais : mesure du 2026-09-05 sur les bancs livres, 0.00 et 0.02
# d'ecart au banc anglais sur les entrees stock, contre 0.58 a 0.90 pour toutes les autres.
ENGLISH = {0, 6}

_RULES = json.load(open(os.path.join(ROOT, "recharged_assets", "font", "case_rules.json")))
ACRONYMS = set(_RULES["acronyms"])
# Les noms propres ne servent QU'A l'exemption d'identite (« Jak II » est identique partout).
# Ils restent soumis au test de casse : « JAK » crie autant que « MASTER ».
PROPER = set(_RULES["proper"])


def encodable_chars():
    """Le jeu de caracteres UTF-8 que la police jak1-v2 sait ecrire."""
    src = open(FONTDB, encoding="utf-8").read()

    def block(name):
        i = src.index(name)
        j = src.index("\n};", i)
        return src[i:j]

    ok = set(" \t")
    ok |= set("0123456789")
    ok |= set("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    ok |= set("abcdefghijklmnopqrstuvwxyz")   # octets recopies tels quels, glyphes Urbanist
    ok |= set("~ ,.-+()!:?=%*/#;<>@[_'\"")
    pairs = re.findall(r'\{"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', block("encode_info_jak1_v2"))
    for utf8, _game in pairs:
        if len(utf8) == 1:
            ok.add(utf8)
    pairs = re.findall(r'\{"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"', block("replace_info_jak1"))
    for _game, utf8 in pairs:
        if len(utf8) == 1:
            ok.add(utf8)
    return ok


def _ascii_word_byte(c):
    return ("A" <= c <= "Z") or ("a" <= c <= "z") or ("0" <= c <= "9") or c == "'"


def words(s):
    """Meme decoupage que settings_case_l10n.cpp:words_of et que Caser.convert."""
    out, i, n = [], 0, len(s)
    while i < n:
        c = s[i]
        if c == "<":
            j = s.find(">", i)
            if j != -1 and j - i <= 20:
                i = j + 1
                continue
        if c == "~":
            j = i + 1
            if j < n and s[j] in "+-":
                j += 1
            while j < n and s[j].isdigit():
                j += 1
            if j < n:
                j += 1
            i = j
            continue
        # ASCII SEULEMENT, comme `is_word_byte` du C++. `str.isalnum()` est vrai pour les kana :
        # avec lui, TOUTE chaine japonaise devient « un mot sans minuscule » donc « tout-majuscules »,
        # y compris les 361 deja livrees dans game_custom_text_ja-JP.json. Le juge de la porte est
        # le C++ ; un verificateur plus severe que lui refuse du texte valide.
        if _ascii_word_byte(c):
            j = i
            while j < n and _ascii_word_byte(s[j]):
                j += 1
            out.append(s[i:j])
            i = j
            continue
        i += 1
    return out


def plain(w):
    if any(ch.isdigit() for ch in w):
        return False
    if sum(1 for ch in w if ch.isalpha()) < 2:
        return False
    return w.upper() not in ACRONYMS


def shouting(s):
    return any(plain(w) and not any(c.islower() for c in w) for w in words(s))


def language_neutral(s):
    return not any(plain(w) and w.upper() not in PROPER for w in words(s))


def check(table):
    """table : {id_hex_str: {locale: chaine}}. Rend la liste des reproches."""
    import gen_mixed_case as G
    rules = json.load(open(os.path.join(ROOT, "recharged_assets", "font", "case_rules.json")))
    caser = G.Caser(rules)
    ok = encodable_chars()
    bad = []
    for tid, per_loc in sorted(table.items()):
        en = per_loc.get("en-US")
        if not en:
            bad.append("%s : pas de chaine en-US" % tid)
            continue
        for lang, loc in sorted(LOCALES.items()):
            s = per_loc.get(loc)
            if s is None:
                bad.append("%s/%s : ABSENT" % (tid, loc))
                continue
            for ch in s:
                if ch not in ok:
                    bad.append("%s/%s : caractere non encodable %r dans %r" % (tid, loc, ch, s))
            fixed = caser.run(s, loc, "label")
            if fixed != s:
                bad.append("%s/%s : pas un point fixe de la phase de casse : %r -> %r"
                           % (tid, loc, s, fixed))
            if shouting(s):
                bad.append("%s/%s : tout-majuscules : %r" % (tid, loc, s))
            if lang not in ENGLISH and s == en and not language_neutral(en):
                bad.append("%s/%s : identique a l'anglais : %r" % (tid, loc, s))
    return bad


NOTES = os.path.join(ROOT, ".autoport", "reports", "recharged-settings-case-l10n", "notes")


def check_locale(loc, path=None):
    """Verifie UN fichier de traduction `tr-<loc>.json` (id hexa -> chaine) contre labels-en.json."""
    src = json.load(open(os.path.join(NOTES, "labels-en.json"), encoding="utf-8"))
    tr = json.load(open(path or os.path.join(NOTES, "tr-%s.json" % loc), encoding="utf-8"))
    table = {}
    for tid, meta in src.items():
        if tid.startswith("_"):
            continue
        table[tid] = {"en-US": meta["en"], loc: tr.get(tid)}
    global LOCALES
    saved = LOCALES
    lang = [k for k, v in LOCALES.items() if v == loc][0]
    LOCALES = {0: "en-US", lang: loc} if loc != "en-US" else {0: "en-US"}
    try:
        return check(table)
    finally:
        LOCALES = saved


if __name__ == "__main__":
    if sys.argv[1] == "--locale":
        problems = check_locale(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    else:
        problems = check(json.load(open(sys.argv[1], encoding="utf-8")))
    for p in problems:
        print(p)
    print("---- %d reproche(s)" % len(problems))
    sys.exit(1 if problems else 0)
