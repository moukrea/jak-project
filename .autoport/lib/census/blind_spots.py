#!/usr/bin/env python3
# lib/census/blind_spots.py — LES ANGLES MORTS DE L'AUDIT DU RECENSEMENT, pour l'item
# `census-audit-blind-spots`. Appele par `lib/census/census-audit-blind-spots.sh`, qui est le
# crochet generique lance par `lib/proof_run.sh` apres la course. Ecrit des `cle=valeur` sur la
# sortie standard, et RIEN d'autre : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL COMPTE. `census_blind_spot_defects` = la somme de QUATRE termes publies SEPAREMENT,
# plus une penalite. Chacun ferme un angle mort que l'audit precedent (`census-false-reds`)
# gardait, tous signales le 2026-09-12 dans `reports/census-false-reds/FINDINGS.txt` et
# `reports/dead-cover-and-legends/FINDINGS.txt`.
#
#   T1 — TABLE DE SURVEILLANCE NON DECLAREE. `kCompressionTokens` ne porte plus qu'un jeton,
#        `RT_KNEE`, qui n'a AUCUNE occurrence dans le CODE des shaders. Un zero de
#        `tonemap_sites_shader` se lit alors « aucun shader ne compresse », alors qu'il dit
#        « aucun des noms SURVEILLES n'apparait ». Les deux grandeurs sont desormais publiees
#        SEPAREMENT — jetons surveilles, jetons observes dans le code — et une table qui DIVERGE
#        (surveilles > observes) doit se declarer telle par un marqueur machine
#        `AUTOPORT_WATCH_TABLE(<nom>)` dans la source qui la porte. Une table qui diverge sans se
#        declarer est le defaut.
#
#   T2 — SEAU RENDU INATTEIGNABLE PAR UN DRAPEAU D'HOTE FIGE. L'audit precedent jugeait les
#        PORTES (uniformes) et les JETONS (tables de texte), jamais les DRAPEAUX D'HOTE.
#        `s_host_shade` et `s_host_legacy` selectionnent les seaux de `note_world_draw` : un
#        drapeau fige par ses sites d'appel rend des seaux INATTEIGNABLES sans qu'aucun compteur
#        ne le dise. La chaine `if/else if` est lue DANS LA SOURCE, jamais recopiee ici, et la
#        joignabilite de chaque seau est decidee par satisfiabilite sur les atomes de la chaine.
#        Le compte publie est DIFFERENTIEL : seuls entrent les seaux joignables sans l'epinglage
#        et perdus avec lui.
#        LA CONSTRUCTION DU BUILD EST UN EPINGLAGE. Les deux sites d'appel de `host_paths` vivent
#        de part et d'autre d'un `#ifdef OG_FEAT_PBR` : avec l'option a OFF, le seul site compile
#        passe `(false, false)` et TOUS les seaux tombent. On lit donc la valeur des options dans
#        `build/CMakeCache.txt` et on ecarte les sites que ce build ne compile pas.
#
#   T3 — ARGUMENT DE SITE D'APPEL ILLISIBLE. Le detecteur d'enregistreur constant de
#        `census-false-reds.sh` lit UNE ligne par site (`sed -E 's/.*f\(([^)]*)\).*/\1/'`) : un
#        appel etale sur plusieurs lignes ne rend RIEN, deux appels sur une ligne n'en rendent
#        qu'un, et un argument illisible etait classe NON litteral, donc vers le VERT. Ici les
#        sites sont trouves sur le TEXTE ENTIER, par equilibrage de parentheses, et le compte de
#        sites et le compte d'arguments ILLISIBLES sont publies SEPAREMENT. Un argument illisible
#        est un DEFAUT, jamais un vert.
#
#   T4 — TEMOIN DE SURVIE QU'UN AUTRE ITEM DOIT SUPPRIMER. `kLegacyControlNames` prenait
#        `u_pbr_mode` comme temoin « survit a la purge », et `lib/census/lighting-legacy-purge.sh`
#        le liste parmi les 36 uniformes que cet item doit SUPPRIMER : le jour ou la purge
#        aboutit, le temoin tombe sans que personne l'ait decide. L'intersection entre les temoins
#        de survie (source moteur ET recensements de harnais) et les listes de suppression des
#        items OUVERTS est publiee ; elle doit etre vide.
#
# CE QU'IL COUVRE EN PLUS, SANS ENTRER DANS LA SOMME (signalement de `dead-cover-and-legends`).
# Trois familles de jetons que le detecteur de legendes ne jugeait pas : les uniformes a UN seul
# segment, les `Classe::membre`, les noms SCREAMING_SNAKE hors ligne `program`/`ShaderId`. Elles
# sont jugees ici, avec pour chacune une AUTORITE nommee et un seau d'exclusion CHIFFRE. Le compte
# de jetons nouvellement juges est publie ; un zero est une VACUITE et entre, lui, dans la somme.
# Ce que le jugement TROUVE appartient a `dead_legend_sites`, la grandeur du voisin, pas a la
# mienne : il est publie, liste, et verse aux signalements.
#
# POURQUOI LE ZERO N'EST PAS UN ZERO D'INACTION. Deux defenses, comme chez les voisins :
#   1. les detecteurs sont joues, dans CE processus et par les MEMES fonctions, sur des copies
#      JETABLES ou l'on a SEME un cas a prendre et un cas a laisser — dont un drapeau d'hote fige,
#      que le livrable exige nommement (`blind_selftests_failed`) ;
#   2. les quatre termes sont recalcules sur l'arbre TEL QU'IL ETAIT au commit EPINGLE d'avant cet
#      item (`blind_before_defects`), qui doit etre NON NUL.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Source manquante, table illisible, corpus
# muet, controle seme en echec : on publie une valeur NON NULLE qui ferme la porte, jamais un zero
# par silence.
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ── LA PUBLICATION ──────────────────────────────────────────────────────────────────────────────
# UNE VALEUR NE PORTE JAMAIS D'ESPACE : `proof_run.sh` ne moissonne que
# `^cle=[^[:space:]]+$`, et une valeur qui en porte une est publiee pour personne. On colle les
# espaces AU POINT DE PUBLICATION, jamais a la main dans chaque appel. Une cle de TEXTE ne se vide
# jamais toute seule : on ecrit "-", jamais la chaine vide.
OUT = []
def pub(k, v):
    s = re.sub(r'\s+', '_', str(v))
    OUT.append('%s=%s' % (k, s if s else '-'))

REASONS = []
PENALTY = [0]
def note(msg, cost=1000):
    REASONS.append(re.sub(r'\s+', '-', msg))
    PENALTY[0] += cost

def joinlist(items, cap=40):
    items = sorted(set(items))
    if not items:
        return '-'
    if len(items) > cap:
        items = items[:cap] + ['...+%d' % (len(set(items)) - cap)]
    return ','.join(re.sub(r'\s+', '_', str(i)) for i in items)

# ── LE MASQUE : COMMENTAIRES ET CHAINES NEUTRALISES, OFFSETS PRESERVES ──────────────────────────
# Un `grep` ne sait pas si une occurrence est du code ou un commentaire, et c'est toute la question
# ici. On ne SUPPRIME rien : on remplace le contenu des commentaires et des chaines par des
# espaces, en gardant les sauts de ligne. Les offsets et les numeros de ligne restent donc ceux du
# fichier, et une directive `#...` reste VISIBLE — elle est du code, et T2 en a besoin.
def mask_code(text):
    out = list(text)
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nx = text[i + 1] if i + 1 < n else ''
        if c == '/' and nx == '/':
            while i < n and text[i] != '\n':
                out[i] = ' '
                i += 1
            continue
        if c == '/' and nx == '*':
            j = text.find('*/', i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if text[k] != '\n':
                    out[k] = ' '
            i = j
            continue
        if c in '"\'':
            q = c
            out[i] = ' '
            i += 1
            while i < n and text[i] != q:
                if text[i] == '\\':
                    out[i] = ' '
                    i += 1
                    if i < n and text[i] != '\n':
                        out[i] = ' '
                        i += 1
                    continue
                if text[i] == '\n':
                    break
                out[i] = ' '
                i += 1
            if i < n and text[i] == q:
                out[i] = ' '
                i += 1
            continue
        i += 1
    return ''.join(out)

def line_of(text, off):
    return text.count('\n', 0, off) + 1

# ── T3 : LES SITES D'APPEL, LUS SUR LE TEXTE ENTIER ─────────────────────────────────────────────
# `census-false-reds.sh` lisait UNE ligne par site. Trois formes lui echappaient, et la troisieme
# tombait vers le VERT :
#   * un appel etale sur plusieurs lignes — `sed` n'y trouve pas la parenthese fermante, ne
#     substitue rien, et rend la LIGNE ENTIERE comme « argument » ;
#   * deux appels sur une meme ligne — `.*f\(` est glouton, un seul site sort ;
#   * un argument que rien ne permet de lire — classe NON litteral, donc « variable », donc vert.
# Ici : recherche sur le texte MASQUE (donc jamais dans un commentaire ni dans une chaine),
# decoupage par EQUILIBRAGE de parentheses, et trois etats nommes par argument — litteral,
# variable, ILLISIBLE. L'illisible est un defaut ; il ne se confond plus avec une variable.
MAXARG = 4000
LIT_INT = re.compile(r'^[+-]?(?:0[xX][0-9a-fA-F]+|\d+)[uUlL]*$')
LIT_BOOL = re.compile(r'^(?:true|false)$')
LIT_STR = re.compile(r'^"(?:[^"\\]|\\.)*"$')

def split_top_commas(s):
    out, cur, depth = [], '', 0
    for ch in s:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    out.append(cur)
    return out

def find_calls(masked, name, raw=None):
    """Rend [(ligne, offset, [args]|None, raison)] pour chaque `name(` du texte.

    LA STRUCTURE SE LIT SUR LE MASQUE, LE TEXTE SUR LA SOURCE. Chercher le nom et equilibrer les
    parentheses sur le masque garantit qu'on ne lit ni un commentaire ni le contenu d'une chaine ;
    mais DECOUPER l'argument sur le masque rendrait `pass_begin("__buckets")` vide, donc « zero
    argument » — le detecteur accusait sa propre cecite. Les offsets sont identiques dans les deux
    textes (le masque REMPLACE, il ne supprime pas), on decoupe donc aux MEMES positions.

    `args` a None et une raison NON vide = site ILLISIBLE : il ne tombe pas vers le vert, il
    compte. Les raisons sont nommees, jamais agregees en « erreur »."""
    if raw is None:
        raw = masked
    sites = []
    for m in re.finditer(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'\s*\(', masked):
        op = masked.index('(', m.end() - 1)
        depth, j, n = 0, op, len(masked)
        body, reason = None, ''
        while j < n:
            ch = masked[j]
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
                if depth == 0:
                    body = masked[op + 1:j]
                    break
            elif ch == ';' and depth >= 1:
                reason = 'ponctuation-;-dans-les-arguments'
                break
            elif ch == '#' and (j == 0 or masked[j - 1] == '\n' or masked[:j].rsplit('\n', 1)[-1].strip() == ''):
                reason = 'directive-preprocesseur-dans-les-arguments'
                break
            if j - op > MAXARG:
                reason = 'arguments-plus-longs-que-%d-caracteres' % MAXARG
                break
            j += 1
        if body is None and not reason:
            reason = 'parenthese-fermante-absente'
        if body is None:
            sites.append((line_of(masked, m.start()), m.start(), None, reason))
            continue
        cuts, depth = [], 0
        for k, ch in enumerate(body):
            if ch in '([{':
                depth += 1
            elif ch in ')]}':
                depth -= 1
            elif ch == ',' and depth == 0:
                cuts.append(k)
        args, prev = [], 0
        for c in cuts + [len(body)]:
            args.append(raw[op + 1 + prev:op + 1 + c].strip())
            prev = c + 1
        if len(args) == 1 and not args[0]:
            args = []
        sites.append((line_of(masked, m.start()), m.start(), args, ''))
    return sites

def classify_arg(a):
    a = a.strip()
    if not a:
        return 'illisible'
    if LIT_INT.match(a) or LIT_BOOL.match(a) or LIT_STR.match(a):
        return 'litteral'
    return 'variable'

# ── T2a : LA CONSTRUCTION DU BUILD EST UN EPINGLAGE ─────────────────────────────────────────────
# `dead-cover-and-legends` l'a mesure sur `grass_overhang` : une valeur peut etre litterale par
# CONSTRUCTION DU BUILD et non par syntaxe. Les deux sites de `host_paths` vivent de part et
# d'autre d'un `#ifdef OG_FEAT_PBR`. On lit donc les options du build qui produit `build/game/gk`
# et on ecarte les sites que ce build NE COMPILE PAS. Un macro inconnu laisse le site EN PLACE et
# se compte (`blind_hostflag_unknown_guards`) : un inconnu ne ferme jamais une porte par silence.
def cmake_defines(cache_path):
    """Les macros `-D` que ce build pose, lues dans son cache. `OG_FEAT_X:BOOL=ON` => defini."""
    d = {}
    p = Path(cache_path)
    if not p.is_file():
        return None
    for line in p.read_text(errors='ignore').splitlines():
        m = re.match(r'^(OG_[A-Z0-9_]+|GOALC_[A-Z0-9_]+):BOOL=(ON|OFF|TRUE|FALSE|1|0)\s*$', line)
        if m:
            d[m.group(1)] = m.group(2) in ('ON', 'TRUE', '1')
    return d

RX_PP = re.compile(r'^[ \t]*#[ \t]*(ifdef|ifndef|if|elif|else|endif)\b[ \t]*(.*)$', re.M)

def eval_pp(kind, arg, defs):
    """Rend True/False/None (inconnu) pour une condition de preprocesseur, sur les macros connues."""
    a = (arg or '').strip()
    if kind == 'ifdef':
        name = a.split()[0] if a.split() else ''
        return defs.get(name, False) if (name in defs or name.startswith('OG_')) else None
    if kind == 'ifndef':
        v = eval_pp('ifdef', a, defs)
        return None if v is None else (not v)
    m = re.fullmatch(r'defined\s*\(\s*([A-Za-z_]\w*)\s*\)', a) or re.fullmatch(r'defined\s+([A-Za-z_]\w*)', a)
    if m:
        return eval_pp('ifdef', m.group(1), defs)
    m = re.fullmatch(r'!\s*defined\s*\(\s*([A-Za-z_]\w*)\s*\)', a)
    if m:
        v = eval_pp('ifdef', m.group(1), defs)
        return None if v is None else (not v)
    if re.fullmatch(r'0+', a):
        return False
    if re.fullmatch(r'[1-9]\d*', a):
        return True
    return None

def guard_map(masked, defs):
    """Rend une liste (debut, fin, etat) ou etat vaut True (compile), False (pas compile) ou
    None (inconnu), pour chaque intervalle d'offsets du fichier."""
    events = []
    for m in RX_PP.finditer(masked):
        events.append((m.start(), m.end(), m.group(1), m.group(2)))
    spans = []
    stack = []          # [(etat_de_la_branche_courante, une_branche_a_deja_ete_prise)]
    last = 0
    def cur_state():
        st = True
        for s, _taken in stack:
            if s is False:
                return False
            if s is None:
                st = None
        return st
    for start, end, kind, arg in events:
        spans.append((last, start, cur_state()))
        if kind in ('ifdef', 'ifndef', 'if'):
            v = eval_pp(kind, arg, defs)
            stack.append((v, v is True))
        elif kind == 'elif':
            if stack:
                _s, taken = stack[-1]
                v = eval_pp('if', arg, defs)
                stack[-1] = (False if taken else v, taken or v is True)
        elif kind == 'else':
            if stack:
                s, taken = stack[-1]
                if taken:
                    stack[-1] = (False, True)
                elif s is None:
                    stack[-1] = (None, False)
                else:
                    stack[-1] = (True, True)
        elif kind == 'endif':
            if stack:
                stack.pop()
        last = end
    spans.append((last, len(masked), cur_state()))
    return spans

def state_at(spans, off):
    for a, b, st in spans:
        if a <= off < b:
            return st
    return True

# ── T2b : LA CHAINE DE SELECTION DES SEAUX, LUE DANS LA SOURCE ──────────────────────────────────
# Recopier ici la liste des seaux et leurs conditions les ferait DERIVER de la source en silence —
# exactement le defaut que `census_gate_table_drift` existe pour prendre chez le voisin. On lit
# donc la chaine `if / else if / else` de `note_world_draw` dans le texte masque, et on decide la
# joignabilite de chaque seau par SATISFIABILITE : un seau de la clause i est joignable s'il
# existe une affectation des atomes qui rende `!C1 & ... & !C(i-1) & Ci` vraie. Les atomes sont
# les sous-expressions qui ne sont ni `&&`, ni `||`, ni `!` ; deux occurrences du MEME texte sont
# le MEME atome, ce qui suffit a lier les clauses entre elles.
def _match_close(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '(':
            depth += 1
        elif s[j] == ')':
            depth -= 1
            if depth == 0:
                return j
    return -1

def _split_top(s, op):
    out, cur, depth, i = [], '', 0, 0
    while i < len(s):
        c = s[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if depth == 0 and s.startswith(op, i):
            out.append(cur)
            cur = ''
            i += len(op)
            continue
        cur += c
        i += 1
    out.append(cur)
    return out

def parse_bool(s):
    s = ' '.join(s.split())
    while s.startswith('(') and _match_close(s, 0) == len(s) - 1:
        s = s[1:-1].strip()
    if not s:
        return ('atom', '')
    p = _split_top(s, '||')
    if len(p) > 1:
        return ('or', [parse_bool(x) for x in p])
    p = _split_top(s, '&&')
    if len(p) > 1:
        return ('and', [parse_bool(x) for x in p])
    if s.startswith('!') and not s.startswith('!='):
        return ('not', parse_bool(s[1:]))
    return ('atom', s)

def atoms_of(node, acc):
    k = node[0]
    if k == 'atom':
        acc.add(node[1])
    elif k == 'not':
        atoms_of(node[1], acc)
    else:
        for c in node[1]:
            atoms_of(c, acc)
    return acc

def eval_bool(node, env):
    k = node[0]
    if k == 'atom':
        return env[node[1]]
    if k == 'not':
        return not eval_bool(node[1], env)
    if k == 'and':
        return all(eval_bool(c, env) for c in node[1])
    return any(eval_bool(c, env) for c in node[1])

RX_PATHASSIGN = re.compile(r'\bpath\s*=\s*([A-Za-z_]\w*)\s*;')

def read_chain(masked, fn_name):
    """Rend [(condition|None pour le `else`, seau)] dans l'ordre de la chaine de `fn_name`."""
    m = re.search(r'(?<![A-Za-z0-9_])' + re.escape(fn_name) + r'\s*\([^)]*\)\s*\{', masked)
    if not m:
        return []
    # le corps de la fonction, par equilibrage d'accolades
    start = masked.index('{', m.end() - 1)
    depth, j = 0, start
    while j < len(masked):
        if masked[j] == '{':
            depth += 1
        elif masked[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = masked[start + 1:j]
    # la chaine commence a la premiere clause qui affecte `path`
    chain, i = [], 0
    first = None
    while i < len(body):
        mm = re.compile(r'(?<![A-Za-z0-9_])(else\s+if|if|else)(?![A-Za-z0-9_])').search(body, i)
        if not mm:
            break
        kind = ' '.join(mm.group(1).split())
        if kind == 'else':
            k = body.find('{', mm.end())
            if k < 0:
                break
            e = _brace_end(body, k)
            blk = body[k + 1:e]
            if RX_PATHASSIGN.search(blk) and first is not None:
                chain.append((None, RX_PATHASSIGN.search(blk).group(1)))
                break
            i = mm.end()
            continue
        op = body.find('(', mm.end())
        if op < 0:
            break
        cl = _match_close(body, op)
        if cl < 0:
            break
        cond = body[op + 1:cl]
        k = body.find('{', cl)
        if k < 0:
            break
        e = _brace_end(body, k)
        blk = body[k + 1:e]
        am = RX_PATHASSIGN.search(blk)
        if am:
            if first is None and kind == 'else if':
                # une chaine qui commence par `else if` n'est pas une chaine : on l'ignore
                i = mm.end()
                continue
            first = True
            chain.append((cond, am.group(1)))
        elif first is not None and kind == 'else if':
            chain.append((cond, None))
        i = e + 1 if e > mm.end() else mm.end()
    return chain

def _brace_end(s, i):
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                return j
    return len(s) - 1

def reachable_buckets(chain, pinned):
    """Rend l'ensemble des seaux joignables. `pinned` : {texte-d-atome: True|False}."""
    nodes = [(parse_bool(c) if c is not None else None, b) for c, b in chain]
    acc = set()
    for nd, _b in nodes:
        if nd is not None:
            atoms_of(nd, acc)
    free = sorted(a for a in acc if a not in pinned)
    reach = set()
    if len(free) > 22:          # garde-fou : on ne fait pas exploser 2^n en silence
        return None
    for mask in range(1 << len(free)):
        env = dict(pinned)
        for bit, a in enumerate(free):
            env[a] = bool(mask & (1 << bit))
        for nd, b in nodes:
            if nd is None or eval_bool(nd, env):
                if b:
                    reach.add(b)
                break
    return reach

# ── T1 : LES TABLES DE JETONS, SURVEILLEES vs OBSERVEES ─────────────────────────────────────────
# `sed -n '/nom\[/,/};/p'` NE CONVIENT PAS quand la declaration tient sur UNE ligne : la fin de
# plage est cherchee a partir de la ligne SUIVANTE et la plage avale la table d'apres (mesure du
# voisin : `kGateNames` rendait en plus les onze noms de `kLegacyUniformNames`). On s'arrete donc
# sur la ligne MEME ou `};` apparait, celle de depart comprise.
RX_TABLE = re.compile(r'(?<![A-Za-z0-9_])(k[A-Za-z0-9_]*Tokens)\s*\[[^\]]*\]\s*(?:=|\{)')
RX_STR = re.compile(r'"([A-Za-z_][A-Za-z0-9_]*)"')

def table_entries(text, name):
    lines = text.splitlines()
    on, got = False, []
    for l in lines:
        if not on and (name + '[') in l and '{' in l:
            on = True
        if on:
            got.extend(RX_STR.findall(l))
            if '};' in l:
                break
    return got

def token_tables(text):
    return sorted(set(RX_TABLE.findall(text)))

def shader_corpus(base):
    d = Path(base) / 'game/graphics/opengl_renderer/shaders'
    files = sorted(p for p in d.rglob('*') if p.is_file()) if d.is_dir() else []
    raw = '\n'.join(p.read_text(errors='ignore') for p in files)
    return files, raw, mask_code(raw)

# ── T4 : LES TEMOINS DE SURVIE, ET CE QUE LES ITEMS OUVERTS DOIVENT SUPPRIMER ────────────────────
# UN TEMOIN se reconnait a son NOM : le tableau ou la variable qui le porte dit `CONTROL` / `CTL`
# / `TEMOIN`. On ne retient que les jetons de forme UNIFORME (`u_...`) ou ECHANTILLONNEUR
# (`tex_...`) : `SO_CTL=$(hits "$SO" lighting_census shade_proof)` nomme des MODULES, pas des
# uniformes, et aucune liste de purge ne les vise.
# Le PORTEUR est retenu sur SA FORME, jamais sur une liste ecrite ici : une constante entierement
# majuscule (shell, python) ou un tableau C nomme `k...Control...`. Les deux conventions du depot,
# et rien d'autre — sans ce filtre, `(?i)ctl` prendrait le premier `actlist` venu.
RX_WITNESS_HOLDER = re.compile(
    r'(?<![A-Za-z0-9_])((?:[A-Za-z_][A-Za-z0-9_]*)?(?:CONTROL|Control|CTL|TEMOIN|Temoin)[A-Za-z0-9_]*)'
    r'\s*(?:\[[^\]]*\])?\s*=')

def witness_holder_ok(name):
    return name.isupper() or name.startswith('k')
RX_UNIFORM_TOK = re.compile(r'(?<![A-Za-z0-9_])((?:u|tex)_[A-Za-z0-9_]+)(?![A-Za-z0-9_])')

def scan_witnesses(base, files):
    """Rend [(jeton, fichier, ligne, porteur)] : les noms d'uniformes que le code ERIGE EN TEMOIN."""
    out = []
    for rel in files:
        p = Path(base) / rel
        if not p.is_file():
            continue
        txt = p.read_text(errors='ignore')
        for m in RX_WITNESS_HOLDER.finditer(txt):
            holder = m.group(1)
            if not witness_holder_ok(holder):
                continue
            # la portee du porteur : jusqu'au `;` ou au `}` de fin de declaration, sinon la ligne
            tail = txt[m.end():m.end() + 400]
            stop = len(tail)
            for ch in (';', '\n}'):
                k = tail.find(ch)
                if 0 <= k < stop:
                    stop = k
            nl = tail.find('\n')
            if '{' not in tail[:max(nl, 0) + 1] and 0 <= nl < stop:
                stop = nl
            for t in RX_UNIFORM_TOK.findall(tail[:stop]):
                out.append((t, rel, line_of(txt, m.start()), holder))
    return out

RX_BASH_ARRAY = re.compile(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\(')
RX_REMOVAL = re.compile(r'(?i)REMOVED|PURGE|DELET|SUPPR|SRC_FILES')

def bash_arrays(text):
    """Rend {nom: [entrees]} pour chaque `NOM=(` ... `)` du script."""
    out = {}
    for m in RX_BASH_ARRAY.finditer(text):
        depth, j = 0, m.end() - 1
        while j < len(text):
            if text[j] == '(':
                depth += 1
            elif text[j] == ')':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = text[m.end():j]
        body = re.sub(r'#[^\n]*', '', body)
        out[m.group(1)] = [w.strip('"\'') for w in body.split() if w.strip('"\'')]
    return out

def open_items(backlog_path):
    """Les items qui ne sont PAS fermes. Un item ferme ne supprimera plus rien."""
    CLOSED = {'validated', 'archived', 'done', 'owner-ok', 'owner_ok'}
    try:
        import yaml
        doc = yaml.safe_load(Path(backlog_path).read_text(encoding='utf-8')) or {}
    except Exception:
        return None
    return [c.get('id') for c in (doc.get('items') or [])
            if c.get('id') and str(c.get('status', '')).strip() not in CLOSED]

def declared_uniforms(base):
    """{nom-d-uniforme: nom-de-fichier} d'apres le TEXTE des shaders. L'autorite d'un uniforme,
    c'est le shader qui le declare — et si ce FICHIER doit quitter l'arbre, le nom est condamne
    tout autant que s'il figurait nommement dans une liste de suppression."""
    d = Path(base) / 'game/graphics/opengl_renderer/shaders'
    out = {}
    if not d.is_dir():
        return out
    for p in sorted(d.rglob('*')):
        if not p.is_file():
            continue
        for m in re.finditer(r'uniform\s+(?:\w+\s+)+?(\w+)\s*(?:\[|;)', mask_code(p.read_text(errors='ignore'))):
            out.setdefault(m.group(1), p.name)
    return out

# ── LES TROIS FAMILLES QUE LE DETECTEUR DE LEGENDES NE JUGEAIT PAS ──────────────────────────────
# Signalement de `dead-cover-and-legends` (12/09), et son avertissement : sans une AUTORITE par
# famille, le compte serait majoritairement faux (mesure du voisin : 89 candidats, ~60 faux
# positifs de structure). Chaque famille a donc ici son autorite NOMMEE et son seau d'exclusion
# CHIFFRE. Ce que le jugement trouve appartient a `dead_legend_sites`, pas a la somme d'ici.
#
#   F1 uniforme a UN segment   autorite = le SUFFIXE DU FICHIER. `u_courant`, `u_modele` sont de
#                              la prose mathematique de nos sources GOAL (`.gc`) ; un commentaire
#                              C++/GLSL qui ecrit `u_xxx` nomme un uniforme. Les `.gc` restent
#                              dans le seau exclu, publie et liste.
#   F2 `Classe::membre`        autorite = la CLASSE. On ne juge que si `Classe` est declaree dans
#                              l'arbre (class/struct/namespace/enum). `SharedRenderState::frame_idx`
#                              s'ecrit `render_state->frame_idx` au point d'usage : `frame_idx` est
#                              dans les mots du CODE, le jeton n'est donc pas perime.
#   F3 SCREAMING_SNAKE         autorite = les mots du CODE **et les mots des CHAINES**. Les noms de
#                              variables d'environnement ne vivent QUE dans des litteraux
#                              (`getenv("OG_DIE_MODE")`) : sans les chaines, « aucune occurrence de
#                              code » ne les distingue pas d'un symbole retire. Les options CMake
#                              et les prefixes d'API (GL_, VK_, SDL_...) completent l'autorite.
ROOTS = ['game', 'common', 'goal_src/jak1', 'android', 'tools', 'goalc', 'decompiler']
CORPUS = ['game/graphics', 'common/custom_data', 'goal_src/jak1/pc', 'game/kernel/jak1']
CORPUS_EXT = ('.cpp', '.h', '.hpp', '.glsl', '.vert', '.frag', '.tese', '.tesc', '.comp', '.gc')
LC = {'.cpp': '//', '.h': '//', '.hpp': '//', '.c': '//', '.glsl': '//', '.vert': '//',
      '.frag': '//', '.tese': '//', '.tesc': '//', '.comp': '//', '.java': '//',
      '.gc': ';', '.gd': ';', '.py': '#'}
BLOCKED = {'.cpp', '.h', '.hpp', '.c', '.glsl', '.vert', '.frag', '.tese', '.tesc', '.comp', '.java'}
WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
TOMB = re.compile(r"RETIRE|SUPPRIM|supprim|retir|purge|n'existe\w* plus|plus pousse|plus declare"
                  r"|removed|no longer|part avec|partent avec|ne sont plus|n'est plus|DELETED"
                  r"|deleted|abandonn|disparu|a quitte|A QUITTE|GONE|jamais livre|est parti", re.I)
RX_U1 = re.compile(r'(?<![A-Za-z0-9_])u_[a-z][a-z0-9]*(?![A-Za-z0-9_])')
RX_MEMBER = re.compile(r'(?<![A-Za-z0-9_:])([A-Z][A-Za-z0-9_]*)::([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])')
RX_SCREAM = re.compile(r'(?<![A-Za-z0-9_])[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+(?![A-Za-z0-9_])')
RX_TYPEDECL = re.compile(r'(?<![A-Za-z0-9_])(?:class|struct|namespace|union|enum(?:\s+class)?)\s+([A-Z][A-Za-z0-9_]*)')
API_PREFIX = ('GL_', 'GLES', 'VK_', 'EGL_', 'SDL_', 'AL_', 'ALC_', 'CL_', 'IMGUI_', 'PFN')
PROGWORD = re.compile(r'program|ShaderId')

def segments(text, lc, block):
    """(kind, texte, ligne) : `code` d'un cote, `legend` de l'autre (commentaires ET chaines)."""
    out = []
    i, n = 0, len(text)
    cur, line, cl = [], 1, 1
    def fl(kind, s, l):
        if s.strip():
            out.append((kind, s, l))
    while i < n:
        if text.startswith(lc, i):
            fl('code', ''.join(cur), cl); cur = []
            j = text.find('\n', i); j = n if j < 0 else j
            fl('legend', text[i:j], line); i = j; cl = line; continue
        if block and text.startswith('/*', i):
            fl('code', ''.join(cur), cl); cur = []
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            fl('legend', text[i:j], line); line += text[i:j].count('\n'); i = j; cl = line; continue
        c = text[i]
        if c == '"':
            fl('code', ''.join(cur), cl); cur = []
            j = i + 1
            while j < n:
                if text[j] == '\\': j += 2; continue
                if text[j] == '"': j += 1; break
                if text[j] == '\n': break
                j += 1
            fl('legend', text[i:j], line); i = j; cl = line; continue
        if c == '\n': line += 1
        cur.append(c); i += 1
    fl('code', ''.join(cur), cl)
    return out

def legend_blocks(segs):
    out, cur = [], []
    for k, s, l in segs:
        if k != 'legend':
            continue
        if cur and l - cur[-1][2] <= 1:
            cur.append((k, s, l))
        else:
            if cur:
                out.append(cur)
            cur = [(k, s, l)]
    if cur:
        out.append(cur)
    return out

# LES EN-TETES DES API QUE LE BINAIRE RELIE. Un commentaire qui ecrit `DEPTH_COMPONENT24` ou
# `COMPARE_REF_TO_TEXTURE` cite une enumeration d'OpenGL, pas un symbole que nous aurions retire :
# sans cette autorite, le detecteur accuse la prose de tout le renderer. Elles ne sont JAMAIS un
# corpus de legendes — on n'y cherche rien, on s'en sert pour dire « ce nom appartient a autrui ».
API_ROOTS = ['third-party/glad/include', 'third-party/SDL/include']
RX_SCREAM_ANY = re.compile(r'(?<![A-Za-z0-9_])([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)(?![A-Za-z0-9_])')

def segment_runs(words):
    """Toutes les sous-chaines a frontiere `_` des mots donnes.

    POURQUOI. `OCC_RADIUS` est le PREFIXE de `OCC_RADIUS_M`, qui existe ; `DEPTH_COMPONENT24` est
    le SUFFIXE de `GL_DEPTH_COMPONENT24`, qui existe. Une prose qui abrege un nom vivant n'est pas
    une legende perimee, et l'egalite stricte ne sait pas le voir."""
    out = set()
    for x in words:
        parts = x.split('_')
        for i in range(len(parts)):
            for j in range(i + 1, len(parts) + 1):
                out.add('_'.join(parts[i:j]))
    return out

def build_world(base):
    b = Path(base)
    code_words, str_words, types = set(), set(), set()
    nfiles = 0
    for r in ROOTS:
        d = b / r
        if not d.is_dir():
            continue
        for p in d.rglob('*'):
            if not p.is_file() or p.suffix not in LC:
                continue
            nfiles += 1
            try:
                t = p.read_text(errors='ignore')
            except Exception:
                continue
            for k, s, l in segments(t, LC[p.suffix], p.suffix in BLOCKED):
                if k == 'code':
                    code_words.update(WORD.findall(s))
                    types.update(RX_TYPEDECL.findall(s))
                elif s.lstrip().startswith('"'):
                    str_words.update(WORD.findall(s))
    sh = b / 'game/graphics/opengl_renderer/shaders'
    shader_files = {p.name for p in sh.rglob('*') if p.is_file()} if sh.is_dir() else set()
    shid = b / 'game/graphics/opengl_renderer/Shader.h'
    enum = set()
    if shid.is_file():
        enum = set(re.findall(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*\d+', shid.read_text(errors='ignore'), re.M))
    cml = b / 'CMakeLists.txt'
    opts = set()
    if cml.is_file():
        opts = set(re.findall(r'(?:option|set)\s*\(\s*([A-Z][A-Z0-9_]+)', cml.read_text(errors='ignore')))
    # L'autorite des API liees, et les prefixes SCREAMING que NOTRE arbre declare lui-meme.
    api = set()
    napi = 0
    for r in API_ROOTS:
        d = b / r
        if not d.is_dir():
            continue
        for p in d.rglob('*.h'):
            napi += 1
            api.update(RX_SCREAM_ANY.findall(p.read_text(errors='ignore')))
    ours = set()
    for x in code_words:
        if RX_SCREAM_ANY.fullmatch(x):
            ours.add(x.split('_')[0])
    return dict(code_words=code_words, str_words=str_words, types=types, nfiles=nfiles,
                shader_files=shader_files, enum=enum, cmake=opts,
                declared=set(declared_uniforms(base)),
                api_files=napi, api_runs=segment_runs(api),
                own_runs=segment_runs(code_words | str_words), own_prefixes=ours)

def scan_new_families(base, world):
    """Rend {famille: (juges, [perimes]), ...} et {famille: exclus}."""
    b = Path(base)
    judged = {'uniforme1': 0, 'membre': 0, 'screaming': 0}
    stale = {'uniforme1': [], 'membre': [], 'screaming': []}
    excl = {'uniforme1': [], 'membre': 0, 'screaming': 0}
    # LE SEAU NOMME : un vocabulaire ETRANGER que notre arbre ne declare nulle part (ioctl du
    # noyau, mnemoniques PS2, enum d'une API non reliee). Il est publie et LISTE, jamais ignore.
    foreign = []
    tombs = 0
    nf = 0
    for d in CORPUS:
        dd = b / d
        if not dd.is_dir():
            continue
        for p in sorted(dd.rglob('*')):
            if not p.is_file() or p.suffix not in CORPUS_EXT:
                continue
            nf += 1
            rel = str(p.relative_to(b))
            try:
                segs = segments(p.read_text(errors='ignore'), LC[p.suffix], p.suffix in BLOCKED)
            except Exception:
                continue
            for blk in legend_blocks(segs):
                if TOMB.search(' '.join(s for k, s, l in blk)):
                    tombs += 1
                    continue
                for k, s, l in blk:
                    st = s.lstrip()
                    if st.startswith('#include'):
                        continue
                    if st.startswith('"') and ' ' not in s:
                        continue
                    # F1
                    for m in RX_U1.finditer(s):
                        t = m.group(0)
                        if p.suffix == '.gc':
                            excl['uniforme1'].append('%s@%s:%d' % (t, rel, l))
                            continue
                        judged['uniforme1'] += 1
                        if t not in world['declared'] and t not in world['code_words']:
                            stale['uniforme1'].append('%s@%s:%d' % (t, rel, l))
                    # F2
                    for m in RX_MEMBER.finditer(s):
                        cls, mem = m.group(1), m.group(2)
                        if cls not in world['types']:
                            excl['membre'] += 1
                            continue
                        if mem.endswith('_') or s[m.end():m.end() + 1] in ('*', '?'):
                            excl['membre'] += 1   # `ShrubTree::wind_*` : un JOKER, pas un membre
                            continue
                        judged['membre'] += 1
                        if mem not in world['code_words'] and mem not in world['str_words']:
                            stale['membre'].append('%s::%s@%s:%d' % (cls, mem, rel, l))
                    # F3 — D6 juge deja les lignes qui disent `program`/`ShaderId`
                    if not PROGWORD.search(s):
                        for m in RX_SCREAM.finditer(s):
                            t = m.group(0)
                            judged['screaming'] += 1
                            if (t.startswith(API_PREFIX) or t in world['cmake']
                                    or t in world['enum'] or t in world['own_runs']):
                                excl['screaming'] += 1          # un nom que NOUS portons encore
                                continue
                            if t in world['api_runs']:
                                excl['screaming'] += 1          # un nom d'une API que nous RELIONS
                                continue
                            if t.split('_')[0] not in world['own_prefixes']:
                                foreign.append('%s@%s:%d' % (t, rel, l))
                                continue
                            stale['screaming'].append('%s@%s:%d' % (t, rel, l))
    return judged, stale, excl, foreign, tombs, nf

# ════════════════════════════════════════ LES QUATRE AUDITS ════════════════════════════════════
# Chacun est une FONCTION de l'arbre qu'on lui donne : c'est ce qui permet de la rejouer, telle
# quelle, sur une copie JETABLE ou l'on a seme un cas a prendre et un cas a laisser, et sur
# l'arbre TEL QU'IL ETAIT au commit epingle. Un detecteur qu'on ne peut pas rejouer ne se
# controle pas.
P = dict(
    census_src='game/graphics/opengl_renderer/lighting_census.cpp',
    census_hdr='game/graphics/opengl_renderer/lighting_census.h',
    shade_src='game/graphics/opengl_renderer/shade_proof.cpp',
    hdr_src='game/graphics/opengl_renderer/hdr.cpp',
    call_dir='game/graphics',
    cache='build/CMakeCache.txt',
    ns='lighting_census',
    chain_fn='note_world_draw',
)
RX_WATCH_DECL = re.compile(r'AUTOPORT_WATCH_TABLE\s*\(\s*([A-Za-z_]\w*)\s*\)')

def read(base, rel):
    p = Path(base) / rel
    try:
        return p.read_text(errors='ignore') if p.is_file() else None
    except Exception:
        return None

def audit_watch_tables(base, paths, code_hits):
    """T1. Rend [(fichier, table, surveilles, observes, declaree)]."""
    out = []
    for key in ('shade_src', 'hdr_src'):
        rel = paths[key]
        txt = read(base, rel)
        if txt is None:
            continue
        declared = set(RX_WATCH_DECL.findall(txt))
        for name in token_tables(txt):
            ents = table_entries(txt, name)
            obs = sum(1 for t in ents if code_hits(t) > 0)
            out.append((rel, name, len(ents), obs, 1 if name in declared else 0))
    return out

RX_DECL = re.compile(r'(?m)^\s*void\s+([a-z_]\w*)\s*\(([^);]*)\)\s*;')

def declared_functions(base, paths):
    """Les fonctions de l'en-tete du recensement : {nom: [(type, parametre), ...]}."""
    txt = read(base, paths['census_hdr'])
    if txt is None:
        return {}
    out = {}
    for m in RX_DECL.finditer(mask_code(txt)):
        params = []
        for a in split_top_commas(m.group(2)):
            a = a.strip()
            if not a:
                continue
            # UN PARAMETRE A VALEUR PAR DEFAUT REND L'ARITE VARIABLE. `roi_after` en a trois :
            # un site a quatre arguments est parfaitement licite, et l'accuser d'illisibilite
            # aurait mis un faux ROUGE dans le seul terme cense n'en porter aucun.
            has_default = '=' in a
            w = WORD.findall(a.split('=')[0])
            if w:
                params.append((' '.join(w[:-1]) if len(w) > 1 else w[0], w[-1], has_default))
        out[m.group(1)] = params
    return out

def source_files(base, rel_dir):
    d = Path(base) / rel_dir
    if not d.is_dir():
        return []
    return sorted(p for p in d.rglob('*') if p.is_file() and p.suffix in ('.cpp', '.h', '.hpp'))

def audit_callsites(base, paths, fns, defs):
    """T3. Rend {nom: {...}} — sites, lignes, litteraux, ILLISIBLES, et par position d'argument
    la valeur epinglee quand tous les sites COMPILES passent le meme litteral."""
    res = {}
    files = source_files(base, paths['call_dir'])
    cache = []
    for p in files:
        txt = p.read_text(errors='ignore')
        m = mask_code(txt)
        cache.append((str(p.relative_to(base)), m, guard_map(m, defs), txt))
    for name, params in sorted(fns.items()):
        qual = paths['ns'] + '::' + name
        sites, lines, unread, excluded, unknown = [], set(), [], 0, 0
        for rel, m, spans, txt in cache:
            for ln, off, args, reason in find_calls(m, qual, txt):
                st = state_at(spans, off)
                if st is False:
                    excluded += 1
                    continue
                if st is None:
                    unknown += 1
                if args is None:
                    unread.append('%s@%s:%d(%s)' % (name, rel, ln, reason))
                    continue
                need = sum(1 for _t, _p, d in params if not d)
                if not (need <= len(args) <= len(params)):
                    unread.append('%s@%s:%d(arite-%d-attendue-%d-a-%d)'
                                  % (name, rel, ln, len(args), need, len(params)))
                    continue
                sites.append((rel, ln, args))
                lines.add((rel, ln))
        pinned = {}
        for i, (_ty, pname, _d) in enumerate(params):
            usable = [a for a in sites if i < len(a[2])]
            kinds = {classify_arg(a[2][i]) for a in usable}
            vals = {a[2][i].strip() for a in usable}
            if usable and len(usable) == len(sites) and kinds == {'litteral'} and len(vals) == 1:
                pinned[pname] = vals.pop()
        res[name] = dict(
            sites=len(sites), lines=len(lines), unreadable=unread, excluded=excluded,
            unknown_guards=unknown, params=[p2 for _t, p2, _d in params], pinned=pinned,
            literal=sum(1 for a in sites for x in a[2] if classify_arg(x) == 'litteral'),
            args=sum(len(a[2]) for a in sites),
            multiline=sum(1 for rel, ln, a in sites if any('\n' in x for x in a)),
            shared_line=len(sites) - len(lines))
    return res

RX_ASSIGN_PARAM = re.compile(r'(?m)^\s*(s_[a-z_0-9]+)\s*=\s*([a-z_]\w*)\s*;')

def audit_host_flags(base, paths, calls):
    """T2. Rend (drapeaux, chaine, joignables_libres, joignables_epingles).

    Un DRAPEAU D'HOTE est une variable statique qu'une fonction du recensement ecrit depuis un
    parametre BOOLEEN. On lit la correspondance dans le CORPS de la fonction — la recopier ici la
    ferait deriver de la source en silence."""
    src = read(base, paths['census_src'])
    if src is None:
        return {}, [], None, None
    m = mask_code(src)
    flags = {}
    for name, info in calls.items():
        mm = re.search(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'\s*\(([^)]*)\)\s*\{', m)
        if not mm:
            continue
        body = m[mm.end():mm.end() + 1200]
        body = body[:_brace_end('{' + body, 0)]
        for am in RX_ASSIGN_PARAM.finditer(body):
            var, param = am.group(1), am.group(2)
            if param in info['params']:
                flags[var] = dict(fn=name, param=param, pinned=info['pinned'].get(param))
    chain = read_chain(m, paths['chain_fn'])
    free = reachable_buckets(chain, {})
    pins = {v: (k['pinned'] == 'true') for v, k in flags.items() if k['pinned'] in ('true', 'false')}
    held = reachable_buckets(chain, pins)
    return flags, chain, free, held

def audit_witnesses(base, paths, census_dir, backlog):
    """T4. Rend (temoins, listes_de_suppression, intersection).

    Les listes de suppression viennent des items OUVERTS seulement : un item FERME ne supprimera
    plus rien, et compter ses listes rendrait la porte inatteignable. Deux formes comptent — le NOM
    du symbole, et le FICHIER qui le declare : un uniforme dont le shader doit quitter l'arbre est
    condamne aussi surement que celui qu'une liste nomme."""
    cen = Path(base) / census_dir
    scripts = sorted(cen.glob('*.sh')) if cen.is_dir() else []
    wits = scan_witnesses(base, [paths['census_src']] + [str(p.relative_to(base)) for p in scripts])
    rm_names, rm_files, contributors = set(), set(), set()
    open_ids = set(backlog) if backlog is not None else None
    for p in scripts:
        item = p.stem
        if open_ids is not None and item not in open_ids:
            continue
        arrays = bash_arrays(p.read_text(errors='ignore'))
        for aname, entries in arrays.items():
            if not RX_REMOVAL.search(aname):
                continue
            hit = False
            for e in entries:
                if '/' in e or '.' in e:
                    rm_files.add(os.path.basename(e))
                else:
                    rm_names.add(e)
                hit = True
            if hit:
                contributors.add(item)
    decl = declared_uniforms(base)
    overlap = []
    for tok, rel, ln, holder in wits:
        why = ''
        if tok in rm_names:
            why = 'nomme'
        elif decl.get(tok) in rm_files:
            why = 'declare-dans-' + str(decl.get(tok))
        if why:
            overlap.append('%s@%s:%d/%s/%s' % (tok, rel, ln, holder, why))
    return wits, dict(names=len(rm_names), files=len(rm_files), items=sorted(contributors)), overlap

# ════════════════════════════════════ LE RECENSEMENT DU JOUR ═══════════════════════════════════
BEFORE_COMMIT = '8b753c8a12f276fa626d38095a4a1b071deab64c'
CENSUS_DIR = '.autoport/lib/census'
BACKLOG = '.autoport/backlog.yaml'

def run_terms(base, paths, census_dir=CENSUS_DIR, backlog_path=BACKLOG, prefix=None, quiet=False):
    """Les QUATRE termes sur l'arbre `base`. Rend un dict ; publie si `prefix` est donne."""
    defs = cmake_defines(Path(base) / paths['cache'])
    if defs is None:
        defs = cmake_defines(paths['cache']) or {}
    _files, _raw, shmask = shader_corpus(base)
    def code_hits(tok):
        return len(re.findall(r'(?<![A-Za-z0-9_])' + re.escape(tok) + r'(?![A-Za-z0-9_])', shmask))
    tables = audit_watch_tables(base, paths, code_hits)
    t1 = sum(1 for _f, _n, w, o, d in tables if o < w and not d)
    fns = declared_functions(base, paths)
    calls = audit_callsites(base, paths, fns, defs)
    t3 = sum(len(v['unreadable']) for v in calls.values())
    flags, chain, free, held = audit_host_flags(base, paths, calls)
    if free is None or held is None:
        t2, lost = 0, []
    else:
        lost = sorted(free - held)
        t2 = len(lost)
    bl = open_items(Path(base) / backlog_path) if (Path(base) / backlog_path).is_file() else open_items(backlog_path)
    wits, rm, overlap = audit_witnesses(base, paths, census_dir, bl)
    t4 = len(overlap)
    return dict(t1=t1, t2=t2, t3=t3, t4=t4, tables=tables, calls=calls, flags=flags, chain=chain,
                free=free, held=held, lost=lost, wits=wits, rm=rm, overlap=overlap,
                defs=defs, shaders=len(_files), corpus_control=code_hits('u_lighting_on'))

# ════════════════════════════ LES CONTROLES SEMES, SUR DES ARBRES JETABLES ═════════════════════
# Un detecteur branche sur rien rendrait le meme zero que quatre populations propres. On rejoue
# donc `run_terms` — LA MEME fonction, pas une copie — sur deux arbres fabriques : l'un ou chaque
# defaut est SEME, l'autre ou chaque cas est SAIN. Le livrable l'exige nommement pour le drapeau
# d'hote : « Semer un drapeau fige et verifier que le compte monte ».
SEED_HDR = '''namespace lighting_census {
void host_zz(bool zz);
void gate_zz(int v);
void note_world_draw(Kind k);
}
'''
SEED_SRC = '''namespace lighting_census {
namespace {
bool s_host_zz = false;
int s_gate_zz = 0;
const char* const kZzControlNames[3] = {%s};
}
void host_zz(bool zz) {
  s_host_zz = zz;
}
void gate_zz(int v) {
  s_gate_zz = v;
}
void note_world_draw(Kind k) {
  int path;
  if (k == Kind::Hfrag) {
    path = kUnaccounted;
  } else if (s_host_zz && s_gate_zz != 0) {
    path = kZ;
  } else {
    path = kUnaccounted;
  }
  s_count[path]++;
}
}
'''
SEED_SHADE = '''%s
const char* const kZzTokens[2] = {"ZZ_LIVE", "ZZ_DEAD"};
'''
SEED_SHADER = ('uniform int u_lighting_on;\nuniform int u_zz_safe;\nuniform int u_zz_safe2;\n'
               'uniform int u_zz_safe3;\nvoid main(){ float k = ZZ_LIVE; }\n')
SEED_DOOMED_SHADER = 'uniform int u_zz_doomed;\nuniform int u_zz_byfile;\n'
SEED_CACHE = 'OG_FEAT_ZZ_ON:BOOL=ON\nOG_FEAT_ZZ_OFF:BOOL=OFF\n'
SEED_BACKLOG = '''items:
  - id: zz-open
    status: open
  - id: zz-closed
    status: validated
'''
SEED_PURGE_OPEN = '''#!/usr/bin/env bash
REMOVED_UNIFORMS=(
  u_zz_doomed
)
SRC_FILES=(
  game/graphics/opengl_renderer/shaders/zz_doomed.glsl
)
'''
SEED_PURGE_CLOSED = '''#!/usr/bin/env bash
REMOVED_UNIFORMS=(
  u_zz_safe
)
'''

def seed_tree(td, dirty):
    """Fabrique un arbre jetable. `dirty` : chaque defaut est SEME. Sinon chaque cas est SAIN."""
    b = Path(td)
    def w(rel, txt):
        p = b / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(txt)
    w('game/graphics/opengl_renderer/lighting_census.h', SEED_HDR)
    # LES TEMOINS DU BANC. Sale : l'un est condamne PAR SON NOM (une liste de suppression le
    # nomme), l'autre PAR SON FICHIER (le shader qui le declare doit quitter l'arbre). Propre :
    # les trois vivent dans un shader que personne ne supprime.
    wits = ('"u_zz_doomed", "u_zz_byfile", "u_zz_safe"' if dirty
            else '"u_zz_safe", "u_zz_safe2", "u_zz_safe3"')
    w('game/graphics/opengl_renderer/lighting_census.cpp', SEED_SRC % wits)
    # une table de jetons qui DIVERGE : `ZZ_DEAD` n'est dans aucun shader. Propre = elle se
    # DECLARE table de surveillance ; sale = elle ne se declare pas.
    w('game/graphics/opengl_renderer/shade_proof.cpp',
      SEED_SHADE % ('' if dirty else '// AUTOPORT_WATCH_TABLE(kZzTokens)'))
    w('game/graphics/opengl_renderer/hdr.cpp', '// pas de table ici\n')
    w('game/graphics/opengl_renderer/shaders/zz.frag', SEED_SHADER)
    w('game/graphics/opengl_renderer/shaders/zz_doomed.glsl', SEED_DOOMED_SHADER)
    w('build/CMakeCache.txt', SEED_CACHE)
    w('.autoport/backlog.yaml', SEED_BACKLOG)
    w('.autoport/lib/census/zz-open.sh', SEED_PURGE_OPEN)
    w('.autoport/lib/census/zz-closed.sh', SEED_PURGE_CLOSED)
    # LES SITES D'APPEL. Trois formes que le detecteur A LA LIGNE de `census-false-reds.sh` ne
    # rendait pas : un appel etale sur DEUX lignes, deux appels sur UNE ligne, un argument
    # ILLISIBLE. Plus un site que la CONSTRUCTION DU BUILD ne compile pas.
    calls = ['namespace zz {',
             'void a() {',
             '  lighting_census::gate_zz(',
             '      3);',                                    # appel sur deux lignes
             '  lighting_census::gate_zz(3); lighting_census::gate_zz(3);',  # deux sur une ligne
             '}',
             '#ifdef OG_FEAT_ZZ_OFF',
             '  void dead() { lighting_census::host_zz(false); }',  # jamais compile
             '#endif',
             '#ifdef OG_FEAT_ZZ_ON']
    if dirty:
        # le drapeau d'hote FIGE : tous les sites compiles passent le meme litteral
        calls.append('  void live() { lighting_census::host_zz(false); }')
        # et un argument que rien ne permet de lire : la parenthese ne se ferme pas
        calls.append('  void broken() { lighting_census::gate_zz(1 ; }')
    else:
        calls.append('  void live() { lighting_census::host_zz(v); }')
    calls += ['#endif', '}', '']
    w('game/graphics/zz_calls.cpp', '\n'.join(calls))
    return b

def seed_paths():
    q = dict(P)
    q['cache'] = 'build/CMakeCache.txt'
    return q

def run_controls():
    checks = []
    def chk(ok, label):
        checks.append((bool(ok), label))
    for dirty in (True, False):
        td = tempfile.mkdtemp()
        try:
            seed_tree(td, dirty)
            r = run_terms(td, seed_paths())
            tag = 'seme' if dirty else 'sain'
            chk(r['shaders'] >= 1, 'corpus-jetable-lu-%s' % tag)
            chk(r['corpus_control'] >= 1, 'temoin-de-corpus-jetable-%s' % tag)
            if dirty:
                chk(r['t1'] == 1, 'table-de-surveillance-non-declaree-PRISE')
                chk(r['t2'] >= 1, 'seau-perdu-par-drapeau-fige-PRIS')
                chk(r['t3'] >= 1, 'argument-illisible-PRIS')
                chk(r['t4'] == 2, 'temoin-condamne-PRIS-par-nom-et-par-fichier(%d)' % r['t4'])
                chk('kZ' in (r['free'] or set()), 'seau-joignable-sans-epinglage')
                chk('kZ' not in (r['held'] or set()), 'seau-injoignable-avec-epinglage')
            else:
                chk(r['t1'] == 0, 'table-de-surveillance-DECLAREE-laissee')
                chk(r['t2'] == 0, 'drapeau-variable-laisse')
                chk(r['t3'] == 0, 'arguments-lisibles-laisses')
                chk(r['t4'] == 0, 'temoins-sains-laisses')
            # LES FORMES QUE LE DETECTEUR A LA LIGNE NE VOYAIT PAS
            gz = r['calls'].get('gate_zz', {})
            chk(gz.get('sites', 0) >= 3, 'appel-multi-lignes-et-deux-appels-sur-une-ligne-%s(%d)'
                % (tag, gz.get('sites', 0)))
            chk(gz.get('shared_line', 0) >= 1, 'deux-appels-sur-une-meme-ligne-%s' % tag)
            hz = r['calls'].get('host_zz', {})
            chk(hz.get('excluded', 0) == 1, 'site-ecarte-par-la-construction-du-build-%s' % tag)
            chk(hz.get('sites', 0) == 1, 'site-compile-retenu-%s' % tag)
            chk(len(r['rm'].get('items') or []) == 1, 'seul-un-item-OUVERT-apporte-sa-liste-%s' % tag)
        except Exception as e:      # un controle qui explose est un controle EN ECHEC
            chk(False, 'controle-jetable-a-explose:%s' % type(e).__name__)
        finally:
            shutil.rmtree(td, ignore_errors=True)
    # LES TROIS FAMILLES NOUVELLEMENT JUGEES, sur leur propre arbre jetable.
    td = tempfile.mkdtemp()
    try:
        b = Path(td)
        def w(rel, txt):
            p = b / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(txt)
        w('game/graphics/opengl_renderer/shaders/zz.frag', 'uniform int u_zzlive;\nvoid main(){}\n')
        w('game/graphics/opengl_renderer/Shader.h', 'enum class ShaderId {\n  ZZ_LIVE = 0,\n};\n')
        w('game/zz_types.h', 'struct ZzClass { int zz_member; };\n#define ZZ_OWN_LIVE 1\n')
        w('game/graphics/zz_legends.cpp', '\n'.join([
            '// F1 : u_zzabsent ne figure dans aucun shader ; u_zzlive y figure.',
            '// F2 : ZzClass::zz_member est declare ; ZzClass::zz_manquant ne l\'est pas ;',
            '//      Etranger::quoi vient d\'une classe que notre arbre ne declare pas.',
            '// F3 : ZZ_OWN_MANQUANT appartient a notre vocabulaire ; ETRANGE_MOT_XY non.',
            'void zz(){}',
            '']))
        w('goal_src/jak1/pc/zz_prose.gc',
          '; la prose GOAL parle de u_courantzz, un vecteur de son propre vocabulaire\n')
        world = build_world(td)
        j, st, ex, fo, _tb, nf = scan_new_families(td, world)
        chk(nf >= 2, 'corpus-de-familles-jetable-lu')
        chk(any('u_zzabsent' in x for x in st['uniforme1']), 'F1-uniforme-a-un-segment-mort-PRIS')
        chk(not any('u_zzlive' in x for x in st['uniforme1']), 'F1-uniforme-vivant-laisse')
        chk(any('u_courantzz' in x for x in ex['uniforme1']), 'F1-prose-GOAL-EXCLUE-et-chiffree')
        chk(any('zz_manquant' in x for x in st['membre']), 'F2-membre-retire-PRIS')
        chk(not any('zz_member' in x for x in st['membre']), 'F2-membre-vivant-laisse')
        chk(ex['membre'] >= 1, 'F2-classe-inconnue-EXCLUE-et-chiffree')
        chk(any('ZZ_OWN_MANQUANT' in x for x in st['screaming']), 'F3-nom-de-NOTRE-vocabulaire-retire-PRIS')
        chk(not any('ZZ_OWN_LIVE' in x for x in st['screaming']), 'F3-nom-vivant-laisse')
        chk(any('ETRANGE_MOT_XY' in x for x in fo), 'F3-vocabulaire-etranger-EXCLU-et-chiffre')
    except Exception as e:
        chk(False, 'controle-de-familles-a-explose:%s' % type(e).__name__)
    finally:
        shutil.rmtree(td, ignore_errors=True)
    return checks

# ══════════════════════════════════════ LA PUBLICATION ═════════════════════════════════════════
def main():
    base = '.'
    r = run_terms(base, P)

    # ── LE SOCLE : sans lui, tous les zeros qui suivent sont des zeros d'INACTION ───────────────
    pub('blind_audit_ran', 1)
    pub('blind_shader_files', r['shaders'])
    pub('blind_corpus_control', r['corpus_control'])
    if r['shaders'] == 0 or r['corpus_control'] == 0:
        note('corpus-de-shaders-muet(fichiers=%d temoin=%d)' % (r['shaders'], r['corpus_control']))
    for k in ('census_src', 'census_hdr', 'shade_src', 'hdr_src', 'cache'):
        if read(base, P[k]) is None and not Path(P[k]).is_file():
            note('source-absente:' + P[k])
    pub('blind_build_cache', P['cache'])
    pub('blind_build_options', ','.join('%s=%d' % (k, v) for k, v in sorted(r['defs'].items())) or '-')
    if not r['defs']:
        note('aucune-option-de-build-lue:la-construction-ne-peut-pas-etre-jugee')

    # ── T1 : JETONS SURVEILLES vs JETONS OBSERVES DANS LE CODE ─────────────────────────────────
    div, undecl = [], []
    for f, name, w, o, d in r['tables']:
        pub('blind_table_%s_watched' % name, w)
        pub('blind_table_%s_observed' % name, o)
        pub('blind_table_%s_declared_watch' % name, d)
        if o < w:
            div.append('%s@%s(%d/%d)' % (name, os.path.basename(f), o, w))
            if not d:
                undecl.append(name)
    pub('blind_tables_audited', len(r['tables']))
    pub('blind_tables_divergent', len(div))
    pub('blind_tables_divergent_list', joinlist(div))
    pub('blind_watch_undeclared', r['t1'])
    pub('blind_watch_undeclared_list', joinlist(undecl))
    if not r['tables']:
        note('aucune-table-de-jetons-lue')
    for n in undecl:
        note('table-de-surveillance-non-declaree:' + n, 0)

    # ── T2 : LES DRAPEAUX D'HOTE ET LES SEAUX QU'ILS FERMENT ───────────────────────────────────
    for var, info in sorted(r['flags'].items()):
        pub('blind_hostflag_%s_writer' % var, '%s(%s)' % (info['fn'], info['param']))
        pub('blind_hostflag_%s_pinned' % var, info['pinned'] if info['pinned'] else '-')
    pub('blind_hostflags_audited', len(r['flags']))
    pub('blind_hostflags_pinned', sum(1 for v in r['flags'].values() if v['pinned']))
    pub('blind_buckets_audited', len(r['chain']))
    pub('blind_buckets_reachable_free', len(r['free'] or []))
    pub('blind_buckets_reachable_held', len(r['held'] or []))
    pub('blind_buckets_unreachable', r['t2'])
    pub('blind_buckets_unreachable_list', joinlist(r['lost']))
    if len(r['chain']) < 4:
        note('chaine-de-selection-des-seaux-illisible(%d-clauses)' % len(r['chain']))
    if not r['flags']:
        note('aucun-drapeau-d-hote-lu')
    if r['free'] is None or r['held'] is None:
        note('joignabilite-des-seaux-non-decidable')
    for b in r['lost']:
        note('seau-rendu-injoignable-par-un-drapeau-fige:' + b, 0)

    # ── T3 : LES SITES D'APPEL ET LES ARGUMENTS ILLISIBLES ─────────────────────────────────────
    tot = dict(sites=0, lines=0, args=0, literal=0, shared=0, excluded=0, unknown=0)
    unread = []
    for name, v in sorted(r['calls'].items()):
        pub('blind_call_%s_sites' % name, v['sites'])
        pub('blind_call_%s_unreadable' % name, len(v['unreadable']))
        tot['sites'] += v['sites']; tot['lines'] += v['lines']; tot['args'] += v['args']
        tot['literal'] += v['literal']; tot['shared'] += v['shared_line']
        tot['excluded'] += v['excluded']; tot['unknown'] += v['unknown_guards']
        unread.extend(v['unreadable'])
    pub('blind_callsite_functions', len(r['calls']))
    pub('blind_callsite_sites', tot['sites'])
    pub('blind_callsite_lines', tot['lines'])
    pub('blind_callsite_shared_line', tot['shared'])
    pub('blind_callsite_args', tot['args'])
    pub('blind_callsite_literal_args', tot['literal'])
    pub('blind_callsite_excluded_by_build', tot['excluded'])
    pub('blind_callsite_unknown_guards', tot['unknown'])
    pub('blind_callsite_unreadable', r['t3'])
    pub('blind_callsite_unreadable_list', joinlist(unread))
    if not r['calls'] or tot['sites'] == 0:
        note('aucun-site-d-appel-lu:le-detecteur-ne-mord-sur-rien')
    for u in unread:
        note('argument-illisible:' + u, 0)

    # ── T4 : LES TEMOINS DE SURVIE CONTRE LES LISTES DE SUPPRESSION ────────────────────────────
    pub('blind_witness_sites', len(r['wits']))
    pub('blind_witness_list', joinlist('%s@%s/%s' % (t, os.path.basename(f), h)
                                       for t, f, _l, h in r['wits']))
    pub('blind_purge_items', len(r['rm']['items']))
    pub('blind_purge_items_list', joinlist(r['rm']['items']))
    pub('blind_purge_names', r['rm']['names'])
    pub('blind_purge_files', r['rm']['files'])
    pub('blind_witness_purge_overlap', r['t4'])
    pub('blind_witness_purge_list', joinlist(r['overlap']))
    if not r['wits']:
        note('aucun-temoin-de-survie-lu')
    if r['rm']['names'] == 0 and r['rm']['files'] == 0:
        note('aucune-liste-de-suppression-lue:l-intersection-est-vide-par-cecite')
    for o in r['overlap']:
        note('temoin-qu-un-item-ouvert-doit-supprimer:' + o, 0)

    # ── LES TROIS FAMILLES NOUVELLEMENT JUGEES (hors somme, sauf VACUITE) ──────────────────────
    world = build_world(base)
    judged, stale, excl, foreign, tombs, nf = scan_new_families(base, world)
    pub('blind_family_corpus_files', nf)
    pub('blind_family_tombstone_blocks', tombs)
    pub('blind_family_world_files', world['nfiles'])
    pub('blind_family_api_files', world['api_files'])
    total_judged = sum(judged.values())
    for fam in sorted(judged):
        pub('blind_family_%s_judged' % fam, judged[fam])
        pub('blind_family_%s_stale' % fam, len(stale[fam]))
        pub('blind_family_%s_stale_list' % fam, joinlist(stale[fam]))
        ex = excl[fam]
        pub('blind_family_%s_excluded' % fam, len(ex) if isinstance(ex, list) else ex)
        if isinstance(ex, list):
            pub('blind_family_%s_excluded_list' % fam, joinlist(ex))
    pub('blind_family_foreign_vocabulary_excluded', len(foreign))
    pub('blind_family_foreign_vocabulary_list', joinlist(foreign))
    pub('blind_newly_judged_tokens', total_judged)
    pub('blind_newly_judged_stale', sum(len(v) for v in stale.values()))
    # UNE COUVERTURE QUI NE JUGE RIEN N'EST PAS UNE COUVERTURE : la vacuite, elle, est un defaut.
    VACUITY = [('uniforme1', 1), ('membre', 1), ('screaming', 1)]
    vac = sum(1 for fam, mini in VACUITY if judged[fam] < mini)
    pub('blind_newly_judged_vacuous_families', vac)
    if vac:
        note('famille-couverte-qui-ne-juge-aucun-jeton(%d)' % vac)
    if world['api_files'] == 0:
        note('en-tetes-d-API-illisibles:le-vocabulaire-etranger-ne-peut-pas-etre-separe')

    # ── LES CONTROLES SEMES ────────────────────────────────────────────────────────────────────
    checks = run_controls()
    failed = [l for ok, l in checks if not ok]
    pub('blind_selftests_run', len(checks))
    pub('blind_selftests_failed', len(failed))
    pub('blind_selftests_failed_list', joinlist(failed))
    for l in failed:
        note('controle-seme-en-echec:' + l)

    # ── LE TEMOIN « AVANT », SUR UN COMMIT EPINGLE ─────────────────────────────────────────────
    # CE BLOC N'ENTRE PAS DANS LA SOMME : c'est un temoin de NON-VACUITE, pas un verdict. Un objet
    # git absent le rend muet, il ne ferme aucune porte. Mais un zero ici voudrait dire que les
    # quatre detecteurs ne mordaient DEJA PAS avant cet item, et le vert d'aujourd'hui ne vaudrait
    # rien. Le commit est EPINGLE, jamais `HEAD` : un temoin « avant » lu a HEAD devient faux a la
    # seconde ou l'on commite et se met a dire zero.
    pub('blind_before_commit', BEFORE_COMMIT[:10])
    before_read, bt = 0, tempfile.mkdtemp()
    b1 = b2 = b3 = b4 = -1
    try:
        ok = subprocess.run(['git', 'archive', BEFORE_COMMIT, 'game', '.autoport/lib/census',
                             '.autoport/backlog.yaml'],
                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if ok.returncode == 0 and ok.stdout:
            tar = subprocess.run(['tar', '-x', '-C', bt], input=ok.stdout, stderr=subprocess.DEVNULL)
            if tar.returncode == 0 and (Path(bt) / P['census_src']).is_file():
                before_read = 1
                q = dict(P)
                # le cache du build n'est pas dans git : on epingle celui d'AUJOURD'HUI, et on le
                # DIT. La question posee est « avec les options d'aujourd'hui, que disait le code
                # d'alors », pas « quel build tournait alors ».
                q['cache'] = str(Path(base).resolve() / P['cache'])
                br = run_terms(bt, q)
                b1, b2, b3, b4 = br['t1'], br['t2'], br['t3'], br['t4']
    except Exception:
        pass
    finally:
        shutil.rmtree(bt, ignore_errors=True)
    pub('blind_before_read', before_read)
    pub('blind_before_watch_undeclared', b1)
    pub('blind_before_buckets_unreachable', b2)
    pub('blind_before_callsite_unreadable', b3)
    pub('blind_before_witness_purge_overlap', b4)
    before_total = (b1 + b2 + b3 + b4) if before_read else -1
    pub('blind_before_defects', before_total)
    if before_read == 1 and before_total <= 0:
        note('temoin-avant-a-zero:les-detecteurs-ne-mordaient-deja-pas')

    # ── LA SOMME, ET SA POLARITE ───────────────────────────────────────────────────────────────
    total = r['t1'] + r['t2'] + r['t3'] + r['t4'] + PENALTY[0]
    pub('blind_penalty', PENALTY[0])
    pub('blind_reason', (';'.join(REASONS))[:900] if REASONS else '-')
    pub('census_blind_spot_defects', total)
    print('\n'.join(OUT))
    return 0

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        # POLARITE : une exception ne rend jamais un vert par silence.
        print('blind_audit_ran=0')
        print('blind_reason=exception:%s:%s' % (type(exc).__name__, re.sub(r'\s+', '_', str(exc))[:120]))
        print('census_blind_spot_defects=9001')
        sys.exit(0)
