#!/usr/bin/env bash
# census/dead-published-keys-round-2.sh — LES CINQ SIGNALEMENTS DU 12/09, RECENSES.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course. Sa
# sortie `cle=valeur` rejoint celle du moteur dans le MEME journal, moissonnee par la MEME regle.
# Il n'ecrit aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la
# machine.
#
# CE QU'IL COMPTE. `dead_keys_r2_defects` = la somme de CINQ termes publies SEPAREMENT, un par
# signalement de `reports/dead-cover-and-legends/FINDINGS.txt` :
#
#   T1 — CLE PUBLIEE QUE LA CONSTRUCTION A FIGEE. Une entree `{"cle", v}` livree (hors `#ifdef`
#        eteint) dont la valeur `v` est une variable locale initialisee a un LITTERAL et dont
#        aucun ecrivain n'est compile. `grass_overhang` : ecrite uniquement sous
#        `#ifdef OG_FEAT_GRASS_OVERHANG`, option OFF dans les DEUX caches de construction livres.
#        L'autorite n'est pas la syntaxe, c'est le CACHE DE CONSTRUCTION.
#
#   T2 — CLE PUBLIEE A VALEUR LITTERALE QUI NE SE DIT PAS CONSTANTE. Une entree dont la valeur est
#        une chaine, un booleen, un nombre, ou un identifiant qui resout vers un `constexpr`
#        litteral, et dont le NOM ne porte pas le suffixe `_const`. Le contrat laisse deux voies —
#        retirer, ou renommer pour dire que c'est une constante ; la voie prise est publiee CLE
#        PAR CLE (`dead_keys_r2_t2_path_<cle>`).
#
#   T3 — MIROIR PARTIEL DE LA PORTE DU POM. Le fragment decide le displacement par une conjonction ;
#        `PbrDrawBinder::set` la recopie cote CPU pour classer chaque draw. Le terme est l'ECART
#        entre le nombre de termes des deux cotes : un miroir partiel se lit comme un accord.
#
#   T4 — MOTIF DE GARDE PERIME. Le bloc `lgtmath::kPbrParams` est GARDE parce que sa sortie est
#        relue hors de la fonction. On mesure, argument par argument, lesquels des consommateurs
#        cites dependent ENCORE du bloc ; tout argument qui n'en depend plus doit etre NOMME dans
#        le motif ecrit au-dessus de la garde, sinon le motif ment par omission.
#
#   T5 — REGISTRE DES CLES RETIREES INCOMPLET. Les captures deja prises portent des cles que le
#        binaire ne publie plus, et `refset_qualification.h` les scelle par `checked_hash` : on ne
#        peut pas les marquer en place. Le registre `kRetiredQualificationKeys` est le chemin de
#        resolution. Le terme est la DIFFERENCE SYMETRIQUE entre ce que l'histoire montre de
#        retire et ce que le registre declare : une cle disparue mais absente du registre, ET une
#        entree de registre qu'aucune disparition ne justifie.
#
# POURQUOI LE ZERO N'EST PAS UN ZERO D'INACTION. Les CINQ detecteurs sont rejoues, dans ce
# processus et par les MEMES fonctions, sur l'arbre TEL QU'IL ETAIT au commit EPINGLE d'avant
# l'item. Chaque `..._before` doit etre NON NUL : un zero apres sans un non-nul avant ne prouve
# rien, et c'est ce que le contrat exige nommement. Un temoin « avant » lu a `HEAD:` deviendrait
# faux a la seconde ou l'on commite — les deux commits sont ECRITS ICI.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Source illisible, region introuvable, cache
# de construction muet, population vide, temoin « avant » a zero : on publie une valeur NON NULLE
# qui ferme la porte, jamais un zero par silence. Le script sort en 0 meme quand il accuse — c'est
# le validateur qui juge.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "dead_keys_r2_audit_ran=0"; echo "dead_keys_r2_defects=9001"; exit 0; }
cd "$ROOT" || { echo "dead_keys_r2_audit_ran=0"; echo "dead_keys_r2_defects=9002"; exit 0; }

# Le commit d'AVANT l'item, EPINGLE : l'arbre sur lequel les cinq detecteurs doivent MORDRE.
BEFORE_COMMIT=583433bc72bb4d613ecac1de6e49e883038790eb
# Le commit d'avant `dead-cover-and-legends`, EPINGLE : l'horizon du registre. `subdivision` et
# `subdivision_rounds` ont disparu AVANT `BEFORE_COMMIT` ; sans ce second ancrage, le registre
# pourrait les omettre sans que rien ne le voie.
HIST_COMMIT=56fbfe875d75702f28e86dc9f8ea9b320df0e2c8

python3 - "$BEFORE_COMMIT" "$HIST_COMMIT" <<'PYEOF'
import re, subprocess, sys, tempfile, shutil
from pathlib import Path

BEFORE_COMMIT, HIST_COMMIT = sys.argv[1], sys.argv[2]

# ── LA PUBLICATION ──────────────────────────────────────────────────────────────────────────────
# UNE VALEUR NE PORTE JAMAIS D'ESPACE. Le moissonneur de `proof_run.sh` ne retient que
# `^cle=[^[:space:]]+$` : une raison ecrite en francais serait publiee pour personne. On colle les
# espaces AU POINT DE PUBLICATION, jamais a la main dans chaque appel.
OUT = []
def pub(k, v):
    OUT.append('dead_keys_r2_%s=%s' % (k, re.sub(r'\s+', '_', str(v))))
REASONS, PENALTY = [], [0]
def note(msg, cost=1000):
    REASONS.append(msg)
    PENALTY[0] += cost

REFSET = 'game/graphics/refset.cpp'
SHADER = 'game/graphics/opengl_renderer/shaders/pbr_fused.glsl'
BGC = 'game/graphics/opengl_renderer/background/background_common.cpp'
PATHS = [REFSET, SHADER, BGC, 'CMakeLists.txt']

def lines_of(base, rel):
    p = Path(base) / rel
    if not p.is_file():
        return None
    return p.read_text(errors='ignore').split('\n')

# ── LE DECOUPEUR DE BLOCS ───────────────────────────────────────────────────────────────────────
# Une accolade dans une chaine ou derriere `//` ne ferme rien. Sans ce filtre, la region d'une
# fonction se termine ou le hasard d'un litteral l'a decide.
def strip_line(l, keep_strings=True):
    """Le texte de la ligne sans son commentaire `//`. `keep_strings` garde le CONTENU des chaines :
    une table de cles PUBLIEES ne se lit pas sans elles — sans ce drapeau `{"cle", false}` devient
    `{, false}` et tous les detecteurs de cles rendent zero sur une table pleine. Les compteurs
    d'accolades et de parentheses, eux, le mettent a False : une accolade dans un litteral ne ferme
    rien, et c'est ce qui decide ou une region s'arrete."""
    out, i, n, q = [], 0, len(l), False
    while i < n:
        c = l[i]
        if q:
            if c == '\\':
                if keep_strings:
                    out.append(l[i:i + 2])
                i += 2; continue
            if c == '"':
                q = False
            if keep_strings:
                out.append(c)
            i += 1; continue
        if c == '"':
            q = True
            if keep_strings:
                out.append(c)
            i += 1; continue
        if l.startswith('//', i):
            break
        out.append(c); i += 1
    return ''.join(out)

def code_only(l):
    return strip_line(l, keep_strings=False)

def region(lines, needle, start_at=0):
    """Rend (i0, i1) INCLUS, les index 0-based des lignes de la region ouverte par `needle`."""
    for i in range(start_at, len(lines)):
        if needle in lines[i]:
            depth, seen = 0, False
            for j in range(i, min(len(lines), i + 600)):
                s = code_only(lines[j])
                depth += s.count('{') - s.count('}')
                if '{' in s:
                    seen = True
                if seen and depth <= 0:
                    return i, j
            return None
    return None

# ── L'AUTORITE DE CONSTRUCTION ──────────────────────────────────────────────────────────────────
# Une option n'est pas eteinte parce qu'un `option(... OFF)` le dit : elle l'est parce que les
# CACHES des builds livres le disent. `build-arm64/` n'en est pas un (toutes ses options a OFF,
# jamais un binaire) ; les deux livres sont `build/` (x86) et `build-android/` (arm64).
CACHES = ['build/CMakeCache.txt', 'build-android/CMakeCache.txt']
def build_options():
    read, states = 0, {}
    for c in CACHES:
        p = Path(c)
        if not p.is_file():
            continue
        read += 1
        for m in re.finditer(r'^([A-Za-z_][A-Za-z0-9_]*):BOOL=(ON|OFF|TRUE|FALSE|1|0)\s*$',
                             p.read_text(errors='ignore'), re.M):
            on = m.group(2) in ('ON', 'TRUE', '1')
            states.setdefault(m.group(1), set()).add(on)
    return read, states

CACHE_READ, CACHE_STATE = build_options()
pub('t1_build_caches_read', CACHE_READ)
if CACHE_READ != len(CACHES):
    note('caches-de-construction-illisibles(%d/%d)' % (CACHE_READ, len(CACHES)))

def option_state(name):
    """'on' si compilee par les DEUX builds livres, 'off' si par AUCUN, 'split'/'unknown' sinon."""
    if name == '__ANDROID__':
        return 'split'       # ON pour l'arm64, OFF pour le x86 : les deux binaires different
    st = CACHE_STATE.get(name)
    if st is None:
        return 'unknown'
    if st == {True}:
        return 'on'
    if st == {False}:
        return 'off'
    return 'split'

UNKNOWN_GUARDS = set()

def delivered_flags(lines, i0, i1):
    """Rend, pour chaque index de ligne de la region, True si la ligne est COMPILEE dans les deux
    binaires livres. La pile des `#if` est tenue ligne a ligne ; une garde dont l'etat n'est pas
    tranche marque la ligne comme NON tranchee (None) : un inconnu ne devient jamais un vert."""
    flags, stack = {}, []
    for i in range(i0, i1 + 1):
        raw = lines[i].strip()
        m = re.match(r'#\s*(ifdef|ifndef|if|elif|else|endif)\b(.*)', raw)
        if m:
            kind, rest = m.group(1), m.group(2).strip()
            if kind in ('ifdef', 'ifndef', 'if'):
                name = None
                if kind in ('ifdef', 'ifndef'):
                    name = rest.split()[0] if rest.split() else None
                else:
                    dm = re.fullmatch(r'defined\s*\(?\s*([A-Za-z_]\w*)\s*\)?', rest)
                    name = dm.group(1) if dm else None
                if name is None:
                    stack.append(None)
                else:
                    st = option_state(name)
                    if st == 'unknown':
                        UNKNOWN_GUARDS.add(name)
                    want_on = (kind != 'ifndef')
                    stack.append(True if (st == 'on') == want_on and st in ('on', 'off')
                                 else (False if st in ('on', 'off') else None))
            elif kind == 'else':
                if stack:
                    top = stack[-1]
                    stack[-1] = None if top is None else (not top)
            elif kind == 'elif':
                if stack:
                    stack[-1] = None
            elif kind == 'endif':
                if stack:
                    stack.pop()
            flags[i] = None
            continue
        flags[i] = (None if None in stack else all(stack))
    return flags

# ── LES DEUX REGIONS QUI PUBLIENT `effective_options` ───────────────────────────────────────────
# L'autorite n'est pas « le fichier refset.cpp » : c'est l'OBJET imprime sur `REFSET effective`.
# Deux regions le construisent, et rien d'autre. Le descripteur de format du `.native.rgba.json`
# (`{"format","RGBA8"}`, `{"orientation","top-left"}`) n'en fait PAS partie : il decrit comment
# decoder un fichier, il ne pretend mesurer aucun reglage.
REGION_A = 'QualificationJson qualification_effective_options() {'
REGION_B = 'if (autoport_proof::feature_is("lighting-hdr")) {'
RX_OBJECT = 'auto effective_options ='
RX_PAIR = re.compile(r'\{\s*"([A-Za-z_][A-Za-z0-9_]*)"\s*,\s*([^{},]+?)\s*\}')
RX_LITERAL = re.compile(r'(true|false|-?\d+(?:\.\d+)?f?|"[^"]*")')

def published_pairs(base):
    """Rend (pairs, ok) ; pairs = [(cle, valeur, livree, region, ligne)]."""
    lines = lines_of(base, REFSET)
    if lines is None:
        return [], False
    # REGION B S'ANCRE SUR L'OBJET, PAS SUR LA FEATURE. `feature_is("lighting-hdr")` apparait
    # quatorze fois dans ce fichier ; le premier match est un bloc qui ne publie rien. La region
    # qui AUGMENTE l'objet commence a la declaration de `effective_options`.
    obj = next((i for i, l in enumerate(lines) if RX_OBJECT in l), None)
    if obj is None:
        return [], False
    out, ok = [], True
    for tag, needle, start in (('A', REGION_A, 0), ('B', REGION_B, obj)):
        r = region(lines, needle, start)
        if r is None:
            ok = False
            continue
        i0, i1 = r
        flags = delivered_flags(lines, i0, i1)
        for i in range(i0, i1 + 1):
            s = strip_line(lines[i])
            for m in RX_PAIR.finditer(s):
                out.append((m.group(1), m.group(2).strip(), flags.get(i), tag, i + 1))
    return out, ok

def file_constants(base):
    """Les `constexpr` de portee fichier dont la valeur est un LITTERAL : un identifiant qui
    resout vers l'un d'eux est une constante publiee, exactement comme le litteral nu."""
    lines = lines_of(base, REFSET) or []
    consts = {}
    for l in lines:
        m = re.match(r'\s*(?:static\s+)?constexpr\s+[\w:*&<> ]+?\s*\*?\s*(\w+)\s*=\s*(.+?);\s*$',
                     strip_line(l))
        if m and RX_LITERAL.fullmatch(m.group(2).strip()):
            consts[m.group(1)] = m.group(2).strip()
    return consts

# ── T1 : LA CLE QUE LA CONSTRUCTION A FIGEE ─────────────────────────────────────────────────────
RX_DECL = re.compile(r'^\s*(?:const\s+)?(?:bool|int|float|double|auto)\s+(\w+)\s*=\s*(.+?);\s*$')
RX_ASSIGN = re.compile(r'^\s*(\w+)\s*=\s*(.+?);\s*$')

def t1_scan(base):
    lines = lines_of(base, REFSET)
    if lines is None:
        return None
    r = region(lines, REGION_A)
    if r is None:
        return None
    i0, i1 = r
    flags = delivered_flags(lines, i0, i1)
    decls, assigns = {}, {}
    for i in range(i0, i1 + 1):
        s = strip_line(lines[i])
        m = RX_DECL.match(s)
        if m:
            decls[m.group(1)] = (m.group(2).strip(), flags.get(i), i + 1)
            continue
        m = RX_ASSIGN.match(s)
        if m and m.group(1) in decls:
            assigns.setdefault(m.group(1), []).append((flags.get(i), i + 1))
    pairs, _ = published_pairs(base)
    scanned, dead = 0, []
    for key, val, deliv, tag, ln in pairs:
        if tag != 'A' or deliv is not True or not re.fullmatch(r'\w+', val) or val not in decls:
            continue
        scanned += 1
        init, dflag, dln = decls[val]
        if not RX_LITERAL.fullmatch(init):
            continue
        if dflag is not True:
            continue
        writers = assigns.get(val, [])
        if any(f is True for f, _ in writers):
            continue
        dead.append('%s@%s:%d/init=%s/ecrivains=%d' % (key, REFSET, ln, init, len(writers)))
    return scanned, dead

# ── T2 : LA CONSTANTE PUBLIEE QUI NE SE DIT PAS CONSTANTE ───────────────────────────────────────
def t2_scan(base):
    pairs, ok = published_pairs(base)
    if not ok:
        return None
    consts = file_constants(base)
    scanned, bad, named = 0, [], []
    for key, val, deliv, tag, ln in pairs:
        if deliv is False:
            continue
        scanned += 1
        is_lit = bool(RX_LITERAL.fullmatch(val)) or val in consts
        if not is_lit:
            continue
        if key.endswith('_const'):
            named.append('%s@%d' % (key, ln))
        else:
            bad.append('%s=%s@%s:%d' % (key, val.replace('"', ''), REFSET, ln))
    return scanned, bad, named

# ── T3 : LES TERMES DE LA PORTE DU POM, DES DEUX COTES ──────────────────────────────────────────
def split_and(expr):
    """Coupe sur les `&&` de PREMIER niveau. Un `&&` sous parentheses appartient a un terme."""
    out, depth, cur, i = [], 0, '', 0
    while i < len(expr):
        c = expr[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
        if depth == 0 and expr.startswith('&&', i):
            out.append(cur.strip()); cur = ''; i += 2; continue
        cur += c; i += 1
    if cur.strip():
        out.append(cur.strip())
    return out

def t3_shader(base):
    lines = lines_of(base, SHADER)
    if lines is None:
        return None
    for i, l in enumerate(lines):
        s = strip_line(l)
        # LES TROIS UNIFORMES ENSEMBLE. Sans `u_pbr_debug != 8`, le detecteur tombe sur la porte
        # du drapeau de couverture vingt lignes plus haut, qui en porte deux sur trois.
        if ('u_pbr_mode & 16' not in s or 'u_pbr_height_scale > 0.0' not in s
                or 'u_pbr_debug != 8' not in s or 'if' not in s):
            continue
        cond, depth, started = '', 0, False
        for j in range(i, min(len(lines), i + 8)):
            t = code_only(lines[j])
            k = t.index('if') + 2 if (j == i) else 0
            for ch in t[k:]:
                if ch == '(':
                    depth += 1; started = True
                    if depth == 1:
                        continue
                elif ch == ')':
                    depth -= 1
                    if depth == 0:
                        return split_and(cond), i + 1
                if started and depth >= 1:
                    cond += ch
        return None
    return None

def t3_const_true(base, term):
    """Le terme retire etait-il VRAI PAR CONSTRUCTION ? C'est la seule preuve qu'aucun pixel ne
    bouge. On resout `pom_w`, `tess_w` et les `#define` depuis le texte du shader, on evalue."""
    lines = lines_of(base, SHADER)
    if lines is None:
        return 0
    txt = '\n'.join(lines)
    defs = {m.group(1): float(m.group(2))
            for m in re.finditer(r'#define\s+(\w+)\s+(-?\d+(?:\.\d+)?)', txt)}
    tw = re.search(r'float\s+tess_w\s*=\s*(-?\d+(?:\.\d+)?)\s*;', txt)
    pw = re.search(r'float\s+pom_w\s*=\s*max\s*\(\s*1\.0\s*-\s*tess_w\s*,\s*(\w+)\s*\)\s*;', txt)
    m = re.fullmatch(r'pom_w\s*>\s*(\w+)', term.strip())
    if not (tw and pw and m and pw.group(1) in defs and m.group(1) in defs):
        return 0
    pom_w = max(1.0 - float(tw.group(1)), defs[pw.group(1)])
    return 1 if pom_w > defs[m.group(1)] else 0

RX_BOOLDEF = re.compile(r'^\s*const\s+bool\s+(\w+)\s*=\s*(.+?);\s*$')

def t3_cpu(base):
    """Le miroir CPU : le DERNIER argument de `pbr_coverage_note_draw`, ses alias booleens locaux
    resolus. On compte les feuilles, pas les noms : `has_height && pom_disp` en porte trois."""
    lines = lines_of(base, BGC)
    if lines is None:
        return None
    for i, l in enumerate(lines):
        if 'pbr_coverage_note_draw(' not in code_only(l):
            continue
        call = ''
        for j in range(i, min(len(lines), i + 6)):
            call += ' ' + code_only(lines[j])
            if ');' in call:
                break
        inner = call[call.index('pbr_coverage_note_draw(') + len('pbr_coverage_note_draw('):]
        inner = inner[:inner.rindex(')')]
        args, depth, cur = [], 0, ''
        for ch in inner:
            if ch == '(':
                depth += 1
            elif ch == ')':
                depth -= 1
            if ch == ',' and depth == 0:
                args.append(cur.strip()); cur = ''; continue
            cur += ch
        args.append(cur.strip())
        defs = {}
        for j in range(max(0, i - 40), i):
            m = RX_BOOLDEF.match(code_only(lines[j]))
            if m:
                defs[m.group(1)] = m.group(2).strip()
        terms, work = [], list(split_and(args[-1]))
        while work:
            t = work.pop(0)
            if t in defs:
                work.extend(split_and(defs[t]))
            else:
                terms.append(t)
        return terms, i + 1
    return None

# ── T4 : LE MOTIF DE LA GARDE `kPbrParams` ──────────────────────────────────────────────────────
GUARD = 'if (lgtmath::block(lgtmath::kPbrParams)) {'
def t4_scan(base):
    lines = lines_of(base, BGC)
    if lines is None:
        return None
    r = region(lines, GUARD)
    if r is None:
        return None
    i0, i1 = r
    assigned = set()
    for i in range(i0 + 1, i1):
        m = re.match(r'^\s*(\w+)\s*(?:=[^=]|\*=|\+=|-=|/=)', strip_line(lines[i]))
        if m:
            assigned.add(m.group(1))
    call_args, call_line = [], 0
    for i, l in enumerate(lines):
        s = strip_line(l)
        m = re.search(r'pbr_cover_publish_gates\s*\(([^)]*)\)\s*;', s)
        if m and not (i0 <= i <= i1):
            call_args = [a.strip() for a in m.group(1).split(',') if a.strip()]
            call_line = i + 1
            break
    escaping = set(a for a in call_args if a in assigned)
    for l in lines:
        m = re.match(r'^\s*(g_pbr_glob_\w+)\s*=\s*(\w+)\s*;\s*$', strip_line(l))
        if m and m.group(2) in assigned:
            escaping.add(m.group(2))
    outside = [a for a in call_args if a not in assigned and not RX_LITERAL.fullmatch(a)]
    motive, i = [], i0 - 1
    while i >= 0 and lines[i].strip().startswith('//'):
        motive.append(lines[i]); i -= 1
    motive_txt = '\n'.join(motive)
    unnamed = [a for a in outside if not re.search(r'\b%s\b' % re.escape(a), motive_txt)]
    return dict(assigned=len(assigned), args=call_args, call_line=call_line,
                escaping=sorted(escaping), outside=outside, unnamed=unnamed,
                motive_lines=len(motive))

# ── T5 : LE REGISTRE DES CLES RETIREES ──────────────────────────────────────────────────────────
LEDGER = 'static constexpr const char* kRetiredQualificationKeys[] = {'
def ledger_keys(base):
    lines = lines_of(base, REFSET)
    if lines is None:
        return None
    for i, l in enumerate(lines):
        if LEDGER in l:
            out = []
            for j in range(i + 1, min(len(lines), i + 64)):
                if '};' in lines[j]:
                    return out
                m = re.search(r'"([^"]+)"', lines[j])
                if m:
                    out.append(re.split(r'->|\?|@', m.group(1))[0])
            return out
    return []

def delivered_key_set(base):
    pairs, ok = published_pairs(base)
    if not ok:
        return None
    return {k for k, v, d, t, l in pairs if d is not False}

# ── LES ARBRES EPINGLES ─────────────────────────────────────────────────────────────────────────
def checkout(commit):
    d = tempfile.mkdtemp()
    a = subprocess.run(['git', 'archive', commit] + PATHS,
                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if a.returncode != 0 or not a.stdout:
        shutil.rmtree(d, ignore_errors=True); return None
    t = subprocess.run(['tar', '-x', '-C', d], input=a.stdout, stderr=subprocess.DEVNULL)
    if t.returncode != 0 or not (Path(d) / REFSET).is_file():
        shutil.rmtree(d, ignore_errors=True); return None
    return d

BEFORE = checkout(BEFORE_COMMIT)
HIST = checkout(HIST_COMMIT)
pub('before_commit', BEFORE_COMMIT[:10]); pub('before_read', 1 if BEFORE else 0)
pub('hist_commit', HIST_COMMIT[:10]); pub('hist_read', 1 if HIST else 0)
if not BEFORE:
    note('arbre-avant-illisible')
if not HIST:
    note('arbre-historique-illisible')

try:
    # ══ T1 ══════════════════════════════════════════════════════════════════════════════════════
    now = t1_scan('.')
    bef = t1_scan(BEFORE) if BEFORE else None
    if now is None:
        note('t1-region-introuvable'); t1 = 9000
    else:
        scanned, dead = now
        pub('t1_pairs_scanned', scanned)
        pub('t1_list', ','.join(dead) or '-')
        t1 = len(dead)
        if scanned == 0:
            note('t1-population-vide')
    pub('t1_before', len(bef[1]) if bef else -1)
    if bef is not None and len(bef[1]) == 0:
        note('t1-temoin-avant-a-zero')
    pub('t1_build_dead_keys', t1)
    pub('t1_unknown_guards', ','.join(sorted(UNKNOWN_GUARDS)) or '-')
    if UNKNOWN_GUARDS:
        note('t1-garde-de-construction-inconnue')

    # ══ T2 ══════════════════════════════════════════════════════════════════════════════════════
    now = t2_scan('.')
    bef = t2_scan(BEFORE) if BEFORE else None
    if now is None:
        note('t2-region-introuvable'); t2 = 9000
    else:
        scanned, bad, named = now
        pub('t2_pairs_scanned', scanned)
        pub('t2_list', ','.join(bad) or '-')
        pub('t2_const_named', ','.join(named) or '-')
        t2 = len(bad)
        if scanned < 15:
            note('t2-population-trop-petite(%d)' % scanned)
    pub('t2_before', len(bef[1]) if bef else -1)
    if bef is not None and len(bef[1]) == 0:
        note('t2-temoin-avant-a-zero')
    pub('t2_literal_keys', t2)
    # LA VOIE PRISE, CLE PAR CLE. Le contrat en exige deux et une seule par cle : `renamed` si la
    # cle d'avant a disparu et que son homonyme `_const` est publie, `removed` si elle a disparu
    # sans successeur. Une cle qu'on retrouve telle quelle n'a pris AUCUNE voie : c'est un defaut.
    if bef is not None and now is not None:
        head = delivered_key_set('.') or set()
        for entry in bef[1]:
            key = entry.split('=')[0]
            if key in head:
                path = 'aucune'
                note('t2-voie-non-prise:' + key)
            elif key + '_const' in head:
                path = 'renamed'
            else:
                path = 'removed'
            pub('t2_path_' + key, path)

    # ══ T3 ══════════════════════════════════════════════════════════════════════════════════════
    sh_now, cpu_now = t3_shader('.'), t3_cpu('.')
    sh_bef = t3_shader(BEFORE) if BEFORE else None
    cpu_bef = t3_cpu(BEFORE) if BEFORE else None
    if sh_now is None or cpu_now is None:
        note('t3-porte-introuvable'); t3 = 9000
    else:
        pub('t3_shader_terms', len(sh_now[0])); pub('t3_shader_list', ';'.join(sh_now[0]))
        pub('t3_cpu_terms', len(cpu_now[0])); pub('t3_cpu_list', ';'.join(cpu_now[0]))
        t3 = abs(len(sh_now[0]) - len(cpu_now[0]))
    if sh_bef and cpu_bef:
        pub('t3_before_shader_terms', len(sh_bef[0]))
        pub('t3_before_cpu_terms', len(cpu_bef[0]))
        bm = abs(len(sh_bef[0]) - len(cpu_bef[0]))
        pub('t3_before_mismatch', bm)
        if bm == 0:
            note('t3-temoin-avant-a-zero')
        # LE TERME RETIRE ETAIT-IL VRAI PAR CONSTRUCTION ? C'est la preuve qu'aucun pixel ne bouge.
        gone = [t for t in sh_bef[0] if t not in sh_now[0]] if sh_now else []
        pub('t3_before_terms_removed', ';'.join(gone) or '-')
        ct = sum(t3_const_true(BEFORE, t) for t in gone)
        pub('t3_removed_terms_const_true', ct)
        if len(gone) != ct:
            note('t3-terme-retire-non-constant:le-rendu-peut-changer', 5000)
    else:
        pub('t3_before_mismatch', -1)
        note('t3-temoin-avant-illisible')
    pub('t3_mirror_mismatch', t3)

    # ══ T4 ══════════════════════════════════════════════════════════════════════════════════════
    now = t4_scan('.')
    bef = t4_scan(BEFORE) if BEFORE else None
    if now is None:
        note('t4-garde-introuvable'); t4 = 9000
    else:
        pub('t4_block_assigned', now['assigned'])
        pub('t4_cover_arity', len(now['args']))
        pub('t4_cover_args', ','.join(now['args']) or '-')
        pub('t4_cover_args_from_block', len(now['args']) - len(now['outside']))
        pub('t4_cover_args_outside', len(now['outside']))
        pub('t4_cover_args_outside_list', ','.join(now['outside']) or '-')
        pub('t4_escaping_outputs', len(now['escaping']))
        pub('t4_escaping_list', ','.join(now['escaping']) or '-')
        pub('t4_motive_lines', now['motive_lines'])
        pub('t4_unnamed_list', ','.join(now['unnamed']) or '-')
        t4 = len(now['unnamed'])
        if not now['args'] or not now['escaping']:
            note('t4-population-vide')
    pub('t4_before', len(bef['unnamed']) if bef else -1)
    if bef is not None and not bef['unnamed']:
        note('t4-temoin-avant-a-zero')
    pub('t4_motive_unnamed', t4)

    # ══ T5 ══════════════════════════════════════════════════════════════════════════════════════
    head_keys = delivered_key_set('.')
    bef_keys = delivered_key_set(BEFORE) if BEFORE else None
    hist_keys = delivered_key_set(HIST) if HIST else None
    led = ledger_keys('.')
    if head_keys is None or bef_keys is None or hist_keys is None or led is None:
        note('t5-source-illisible'); t5 = 9000
    else:
        delta = (bef_keys | hist_keys) - head_keys
        gaps = delta - set(led)
        extra = set(led) - delta
        pub('t5_head_keys', len(head_keys))
        pub('t5_before_keys', len(bef_keys))
        pub('t5_hist_keys', len(hist_keys))
        pub('t5_delta_keys', len(delta))
        pub('t5_delta_list', ','.join(sorted(delta)) or '-')
        pub('t5_ledger_entries', len(led))
        pub('t5_ledger_list', ','.join(sorted(led)) or '-')
        pub('t5_gaps_list', ','.join(sorted(gaps)) or '-')
        pub('t5_extra_list', ','.join(sorted(extra)) or '-')
        t5 = len(gaps) + len(extra)
        if not delta:
            note('t5-population-vide')
        # LE TEMOIN « AVANT » : le registre n'existait pas, la difference symetrique valait la
        # taille entiere de la population disparue.
        pub('t5_before', len(delta - set(ledger_keys(BEFORE) or [])))
        if len(delta - set(ledger_keys(BEFORE) or [])) == 0:
            note('t5-temoin-avant-a-zero')
        # ══ LES CAPTURES DEJA STOCKEES DANS LE DEPOT, ET LEUR MARQUE ════════════════════════════
        # Une capture ancienne ne peut pas etre RETOUCHEE : `refset_qualification.h` la scelle par
        # `checked_hash` et les recus de rejeu l'epinglent par `capture_fp`. On marque donc son
        # DOSSIER par un voisin `RETIRED-KEYS.txt` qu'aucune empreinte ne couvre.
        # LA MARQUE DOIT ETRE SUIVIE PAR GIT. `.autoport/reports/` est GITIGNORE (.gitignore:173) et
        # ses captures n'y vivent que par `git add -f` : une marque posee sans forcer n'existerait
        # que dans CE repertoire de travail, la porte serait verte ici et rouge partout ailleurs. On
        # interroge donc l'INDEX, pas le disque.
        # APPARTENANCE : un fichier compte comme capture s'il porte la cle en forme de MEMBRE JSON
        # (`"cle":`). Un `.patch` qui cite la table C++ (`{"subdivision", false}`) est du SOURCE, pas
        # une capture ; le seau ecarte est chiffre, jamais muet.
        tracked = set(subprocess.run(['git', 'ls-files'], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True).stdout.split('\n'))
        scanned, carrying, carrying_files, loose_only = 0, {}, [], []
        g = subprocess.run(['git', 'grep', '-l', '-e', 'effective_options', '-e', 'REFSET effective'],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        for f in [x for x in g.stdout.split('\n') if x and not x.startswith('game/')
                  and not x.startswith('.autoport/lib/census/')]:
            fp = Path(f)
            if not fp.is_file() or fp.stat().st_size > 16 * 1024 * 1024:
                continue
            scanned += 1
            t = fp.read_text(errors='ignore')
            member = sorted(k for k in delta if re.search(r'"%s"\s*:' % re.escape(k), t))
            if member:
                carrying.setdefault(str(fp.parent), set()).update(member)
                carrying_files.append(f)
            elif any(re.search(r'"%s"' % re.escape(k), t) for k in delta):
                loose_only.append(f)
        unmarked, marked = [], 0
        for d, keys in sorted(carrying.items()):
            mark = d + '/RETIRED-KEYS.txt'
            if mark not in tracked:
                unmarked.append(d + '(non-suivi)'); continue
            txt = Path(mark).read_text(errors='ignore') if Path(mark).is_file() else ''
            m = re.search(r'^keys=(\S*)$', txt, re.M)
            if not m or set(filter(None, m.group(1).split(','))) != keys:
                unmarked.append(d + '(cles-fausses)'); continue
            marked += 1
        pub('t5_stored_captures_scanned', scanned)
        pub('t5_stored_carrying_files', len(carrying_files))
        pub('t5_stored_carrying_dirs', len(carrying))
        pub('t5_stored_carrying_list', ','.join(sorted(carrying)) or '-')
        pub('t5_stored_marked_dirs', marked)
        pub('t5_stored_unmarked_list', ','.join(unmarked) or '-')
        pub('t5_stored_excluded_source_only', len(loose_only))
        pub('t5_stored_excluded_list', ','.join(sorted(loose_only)) or '-')
        if not carrying:
            note('t5-population-de-captures-vide')
        t5 += len(unmarked)
        pub('t5_unmarked_dirs', len(unmarked))
        # LE TEMOIN « AVANT » DE LA MARQUE : aucune de ces marques n'existait dans l'index du commit
        # epingle. Le compte d'avant est donc la population ENTIERE des dossiers porteurs.
        before_tracked = set(subprocess.run(['git', 'ls-tree', '-r', '--name-only', BEFORE_COMMIT],
                                            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                            text=True).stdout.split('\n'))
        bu = sum(1 for d in carrying if d + '/RETIRED-KEYS.txt' not in before_tracked)
        pub('t5_before_unmarked_dirs', bu)
        if carrying and bu == 0:
            note('t5-temoin-avant-de-marque-a-zero')
    pub('t5_ledger_gaps', t5)

    TOTAL = t1 + t2 + t3 + t4 + t5 + PENALTY[0]
except Exception as exc:                                    # tout inconnu vaut DEFAUT
    note('exception:' + type(exc).__name__ + ':' + str(exc)[:80], 9000)
    TOTAL = PENALTY[0]
finally:
    for d in (BEFORE, HIST):
        if d:
            shutil.rmtree(d, ignore_errors=True)

pub('audit_ran', 1)
pub('penalty', PENALTY[0])
pub('reason', ';'.join(REASONS) if REASONS else '-')
pub('defects', TOTAL)
print('\n'.join(OUT))
PYEOF
exit 0
