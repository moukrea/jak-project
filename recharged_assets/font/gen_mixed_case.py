#!/usr/bin/env python3
"""Passe les textes de jak1 en CASSE MIXTE. Demande owner : « fini le all caps ».

Ce que ce script convertit
--------------------------
  1. `decompiler_out/jak1/assets/game_text.txt` — le banc de base EXTRAIT de l'ISO de
     l'owner (279 entrees x 7 langues + un bloc `credits`). Il est GENERE par le
     decompilateur, donc on ne l'edite pas : on ecrit des fichiers de SURCHARGE
     `game/assets/jak1/text/game_case_text_<lang>.json`, listes APRES lui dans
     `game_text.gp`. `text_ser.cpp` fait `bank->set_line(id, ...)`, donc le dernier
     fichier gagne. Une re-extraction du decompilateur ne les efface pas.
  2. `game/assets/jak1/text/game_custom_text_*.json` et `game_base_text_*.json` — nos
     propres fichiers : convertis SUR PLACE.
  3. `game/assets/jak1/subtitle/subtitle_lines_*.json` — 31 452 lignes, le plus gros
     corpus et celui que l'owner nomme (« sous-titres »). Converti SUR PLACE.

La regle est DONNEE, pas codee : `recharged_assets/font/case_rules.json`.

Ce qui n'est JAMAIS touche
--------------------------
  - les balises `<PAD_X>` `<PAD_CIRCLE>` `<PAD_SQUARE>` `<PAD_TRIANGLE>` `<TIL>` ;
  - les echappements `~33L` `~34L` `~D` `~Y` `~Z` `~+26H` ... (recopies tels quels) ;
  - `_`, qui n'est PAS un souligne mais une ESPACE LARGE (`font_db_jak1.cpp` : `_`
    est encode en \\x03), imposee par les chaines Sony `MEMORY_CARD_(PS2)` ;
  - les jetons qui melent chiffres et lettres, sauf table explicite ;
  - de-DE, ja-JP, ko-KR (voir case_rules.json pour la raison, mesuree).

Verification : le script publie un AUDIT complet (avant -> apres) sous
`.autoport/reports/Gfont-urbanist/case-audit-<lang>.txt`, plus un resume chiffre.
"""
import argparse
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RULES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "case_rules.json")
GAME_TEXT = os.path.join(ROOT, "decompiler_out", "jak1", "assets", "game_text.txt")
TEXTDIR = os.path.join(ROOT, "game", "assets", "jak1", "text")
SUBDIR = os.path.join(ROOT, "game", "assets", "jak1", "subtitle")
REPORTDIR = os.path.join(ROOT, ".autoport", "reports", "Gfont-urbanist")

# Ordre des langues du fichier decompile, lu dans son en-tete `(language-id ...)`
# et dans game_text.gp (0 en-US, 1 fr-FR, 2 de-DE, 3 es-ES, 4 it-IT, 5 ja-JP, 6 en-GB).
DECOMP_LANGS = ["en-US", "fr-FR", "de-DE", "es-ES", "it-IT", "ja-JP", "en-GB"]


# ------------------------------------------------------------------------------------
# Conversion d'une chaine
# ------------------------------------------------------------------------------------
class Caser:
    def __init__(self, rules):
        self.acr = set(rules["acronyms"])
        self.num = rules["numeric"]
        self.proper = set(rules["proper"])
        self.small = set(rules["title_small_words"])
        # phrases atomiques, traitees avant tout decoupage (les plus longues d'abord)
        self.phrases = sorted(rules.get("phrases", {}).items(), key=lambda kv: -len(kv[0]))
        self.langs = rules["languages"]

    def cfg(self, lang):
        return self.langs.get(lang, self.langs["_default"])

    @staticmethod
    def _isletter(c):
        return unicodedata.category(c).startswith("L")

    def word_case(self, w, mode, keep_upper, first, last):
        """mode: 'lower' | 'cap' | 'title'."""
        up = w.upper()
        if up in keep_upper:
            return up
        if up in self.acr:
            return up
        if any(ch.isdigit() for ch in w):
            return self.num.get(up, w.lower())
        # le possessif anglais ne doit pas cacher le nom propre : SAGE'S -> Sage's
        stem = up[:-2] if up.endswith("'S") else up
        if up in self.proper or stem in self.proper:
            return w[0].upper() + w[1:].lower()
        if mode == "name":
            return w[0].upper() + w[1:].lower()
        if mode == "title":
            if up in self.small and not first and not last:
                return w.lower()
            return w[0].upper() + w[1:].lower()
        if mode == "cap":
            return w[0].upper() + w[1:].lower()
        return w.lower()

    def convert(self, s, lang, style):
        """style : 'title' | 'sentence' | 'name'. (NE PAS renommer en `kind` : la
        boucle de jetons utilise deja ce nom et l'ombrerait.)"""
        cfg = self.cfg(lang)
        keep_upper = set(cfg.get("keep_upper_words", []))
        # phrases atomiques : mises de cote sous un jeton neutre, restaurees a la fin
        # Recherche INSENSIBLE A LA CASSE : sans cela une seconde passe sur un texte
        # deja converti ne reconnaitrait plus « Memory_Card_(PS2) » et le redecouperait.
        holds = []
        for src_p, dst_p in self.phrases:
            low_p = src_p.lower()
            while low_p in s.lower():
                k = s.lower().index(low_p)
                s = s[:k] + ("\x00%d\x00" % len(holds)) + s[k + len(src_p):]
                holds.append(dst_p)
        out = []
        # 1re passe : decoupage en jetons (mot / balise / echappement / autre)
        toks = []
        i = 0
        n = len(s)
        while i < n:
            c = s[i]
            if c == "<":
                j = s.find(">", i)
                if j != -1 and j - i <= 20:
                    toks.append(("raw", s[i:j + 1]))
                    i = j + 1
                    continue
            if c == "~":
                j = i + 1
                if j < n and s[j] in "+-":
                    j += 1
                while j < n and s[j].isdigit():
                    j += 1
                if j < n:
                    j += 1          # la lettre de commande
                toks.append(("raw", s[i:j]))
                i = j
                continue
            if self._isletter(c):
                j = i
                while j < n and (self._isletter(s[j]) or
                                 (s[j] == "'" and j + 1 < n and self._isletter(s[j + 1]))):
                    j += 1
                toks.append(("word", s[i:j]))
                i = j
                continue
            if c.isdigit():
                j = i
                while j < n and (s[j].isdigit() or self._isletter(s[j])):
                    j += 1
                toks.append(("word", s[i:j]))
                i = j
                continue
            toks.append(("sep", c))
            i += 1

        widx = [k for k, t in enumerate(toks) if t[0] == "word"]
        first_word = widx[0] if widx else -1
        last_word = widx[-1] if widx else -1

        sentence_start = True
        for k, (kind, val) in enumerate(toks):
            if kind != "word":
                out.append(val)
                if kind == "sep":
                    # '=' ouvre une valeur, comme une fin de phrase : sans lui, la
                    # chaine la plus vue du jeu rendait « = Oui, ... = non ».
                    if val in ".!?=":
                        sentence_start = True
                continue
            if style == "name":
                mode = "name"
            elif style == "title":
                mode = "title"
            else:
                mode = "cap" if sentence_start else "lower"
            out.append(self.word_case(val, mode, keep_upper,
                                      k == first_word, k == last_word))
            sentence_start = False
        res = "".join(out)
        for idx, dst_p in enumerate(holds):
            res = res.replace("\x00%d\x00" % idx, dst_p)
        return res

    def label_is_sentence(self, s):
        t = s.rstrip()
        return t.endswith((".", "!", "?"))

    def run(self, s, lang, corpus):
        """corpus: 'label' | 'sentence' | 'name'."""
        cfg = self.cfg(lang)
        if cfg["mode"] == "skip":
            return s
        if corpus == "name":
            return self.convert(s, lang, "name")
        if corpus == "label" and cfg["mode"] == "title-labels" and not self.label_is_sentence(s):
            return self.convert(s, lang, "title")
        return self.convert(s, lang, "sentence")


# ------------------------------------------------------------------------------------
# Lecture de game_text.txt (forme s-expression, sous-ensemble suffisant)
# ------------------------------------------------------------------------------------
def parse_game_text(path):
    """Rend (entries, credits) ou entries = [(id, [str par langue])] et
    credits = [(id, [str par langue] | str partage)]."""
    src = open(path, encoding="utf-8").read()
    toks = re.findall(r'"(?:[^"\\]|\\.)*"|[()]|[^\s()"]+', src)

    def unq(t):
        return t[1:-1].replace('\\"', '"').replace("\\\\", "\\")

    entries, credits = [], []
    i = 0
    while i < len(toks):
        if toks[i] != "(":
            i += 1
            continue
        # trouve la forme
        depth = 0
        j = i
        while j < len(toks):
            if toks[j] == "(":
                depth += 1
            elif toks[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        form = toks[i:j + 1]
        head = form[1] if len(form) > 1 else ""
        if head.startswith("#x"):
            ident = int(head[2:], 16)
            strs = [unq(t) for t in form[2:-1] if t.startswith('"')]
            entries.append((ident, strs))
        elif head == "credits":
            begin = int(form[3][2:], 16)
            ident = begin - 1
            k = 4
            while k < len(form) - 1:
                if form[k] == "(":
                    d = 0
                    m = k
                    while m < len(form):
                        if form[m] == "(":
                            d += 1
                        elif form[m] == ")":
                            d -= 1
                            if d == 0:
                                break
                        m += 1
                    ident += 1
                    credits.append((ident, [unq(t) for t in form[k + 1:m] if t.startswith('"')]))
                    k = m + 1
                elif form[k].startswith('"'):
                    ident += 1
                    v = unq(form[k])
                    if v:
                        credits.append((ident, v))
                    k += 1
                else:
                    k += 1
        i = j + 1
    return entries, credits


# ------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rules = json.load(open(RULES, encoding="utf-8"))
    C = Caser(rules)
    os.makedirs(REPORTDIR, exist_ok=True)
    stats = {}
    audit = {}

    def note(lang, before, after):
        stats.setdefault(lang, [0, 0])
        stats[lang][0] += 1
        if before != after:
            stats[lang][1] += 1
            audit.setdefault(lang, []).append((before, after))

    # ---- 1. banc de base decompile -> fichiers de surcharge -------------------------
    entries, credits = parse_game_text(GAME_TEXT)
    over = {lang: {} for lang in DECOMP_LANGS}
    for ident, strs in entries:
        for li, s in enumerate(strs):
            if li >= len(DECOMP_LANGS):
                break
            lang = DECOMP_LANGS[li]
            new = C.run(s, lang, "label")
            note(lang, s, new)
            if new != s:
                over[lang]["%x" % ident] = new
    for ident, val in credits:
        if isinstance(val, str):              # nom de personne, partage par les 7 langues
            new = C.run(val, "en-US", "name")
            for lang in DECOMP_LANGS:
                note(lang, val, new)
                if new != val:
                    over[lang]["%x" % ident] = new
        else:
            for li, s in enumerate(val):
                if li >= len(DECOMP_LANGS):
                    break
                lang = DECOMP_LANGS[li]
                new = C.run(s, lang, "label")
                note(lang, s, new)
                if new != s:
                    over[lang]["%x" % ident] = new

    written = []
    for lang, d in over.items():
        if not d:
            continue
        p = os.path.join(TEXTDIR, "game_case_text_%s.json" % lang)
        if not args.dry_run:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(dict(sorted(d.items(), key=lambda kv: int(kv[0], 16))), f,
                          ensure_ascii=False, indent=2)
                f.write("\n")
        written.append((p, len(d)))

    # ---- 2. nos JSON de texte, sur place --------------------------------------------
    for fn in sorted(os.listdir(TEXTDIR)):
        if not (fn.startswith("game_custom_text_") or fn.startswith("game_base_text_")):
            continue
        lang = fn.replace("game_custom_text_", "").replace("game_base_text_", "")
        lang = lang.replace("android_", "").replace(".json", "")
        p = os.path.join(TEXTDIR, fn)
        d = json.load(open(p, encoding="utf-8"))
        out, ch = {}, 0
        for k, v in d.items():
            new = C.run(v, lang, "label") if isinstance(v, str) else v
            note(lang, v, new)
            if new != v:
                ch += 1
            out[k] = new
        if ch and not args.dry_run:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(out, f, ensure_ascii=False, indent=2)
                f.write("\n")
        if ch:
            written.append((p, ch))

    # ---- 3. sous-titres, sur place ---------------------------------------------------
    if os.path.isdir(SUBDIR):
        for fn in sorted(os.listdir(SUBDIR)):
            m = re.match(r"subtitle_lines_(.+)\.json$", fn)
            if not m:
                continue
            lang = m.group(1)
            p = os.path.join(SUBDIR, fn)
            raw = json.load(open(p, encoding="utf-8"))
            ch = [0]

            def line(o, corpus):
                new = C.run(o, lang, corpus)
                note(lang, o, new)
                if new != o:
                    ch[0] += 1
                return new

            # Structure MESUREE : {"cutscenes": {scene: [lignes]}, "hints": {id: [lignes]},
            # "speakers": {id: nom affiche}}. Les CLES sont des identifiants (noms de
            # scene, ids de replique, ids de locuteur) : elles ne sont jamais touchees.
            def walk(o):
                out = {}
                for sec, body in o.items():
                    if sec == "speakers":
                        out[sec] = {k: line(v, "name") if isinstance(v, str) else v
                                    for k, v in body.items()}
                    elif sec in ("cutscenes", "hints"):
                        out[sec] = {k: [line(x, "sentence") if isinstance(x, str) else x
                                        for x in v] if isinstance(v, list) else v
                                    for k, v in body.items()}
                    else:
                        out[sec] = body
                return out

            new = walk(raw)
            if ch[0] and not args.dry_run:
                with open(p, "w", encoding="utf-8") as f:
                    json.dump(new, f, ensure_ascii=False, indent=2)
                    f.write("\n")
            if ch[0]:
                written.append((p, ch[0]))

    # ---- rapport ---------------------------------------------------------------------
    lines = ["CONVERSION EN CASSE MIXTE — resume par langue",
             "langue    vues   changees   part"]
    tot = [0, 0]
    for lang in sorted(stats):
        n, c = stats[lang]
        tot[0] += n
        tot[1] += c
        lines.append("%-9s %6d %8d   %5.1f %%  %s" %
                     (lang, n, c, 100.0 * c / max(n, 1), C.cfg(lang)["mode"]))
    lines.append("%-9s %6d %8d   %5.1f %%" % ("TOTAL", tot[0], tot[1],
                                              100.0 * tot[1] / max(tot[0], 1)))
    lines.append("")
    lines.append("fichiers ecrits : %d" % len(written))
    for p, n in written:
        lines.append("  %-70s %6d" % (os.path.relpath(p, ROOT), n))
    print("\n".join(lines))
    if not args.dry_run:
        open(os.path.join(REPORTDIR, "case-summary.txt"), "w").write("\n".join(lines) + "\n")
        for lang, rows in audit.items():
            with open(os.path.join(REPORTDIR, "case-audit-%s.txt" % lang), "w",
                      encoding="utf-8") as f:
                for a, b in rows:
                    f.write("- %s\n+ %s\n" % (a, b))


if __name__ == "__main__":
    main()
