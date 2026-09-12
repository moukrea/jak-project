#!/usr/bin/env bash
# census/dead-cover-and-legends.sh — LE RECENSEMENT DES CHEMINS MORTS ET DES LEGENDES PERIMEES,
# pour l'item `dead-cover-and-legends`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course. Sa
# sortie `cle=valeur` rejoint celle du moteur dans le MEME journal, moissonnee par la MEME regle.
# Il n'ecrit aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la
# machine.
#
# CE QU'IL COMPTE. `dead_legend_sites` = le nombre de sites ou le code decide quelque chose que sa
# construction a deja decide, ou nomme comme vivante une chose qui n'existe plus. Six populations,
# chacune avec sa propre autorite et son propre denominateur.
#
#   D1 — CONDITIONS A ISSUE FIXEE (source). Une fonction PORTEUSE range ses parametres dans des
#        variables (`g_x.store(p)` / `m_x = p`). Si TOUS ses sites d'appel passent le MEME
#        litteral dans une position, la variable qui recoit ce parametre est une constante DE
#        CONSTRUCTION : toute condition qui la relit a une issue fixee d'avance. C'est le defaut
#        qui a ouvert l'item : `pbr_cover_publish_gates(height_scale, 0, pbr_debug,
#        pbr_displacement)` — un seul site, `bisect` = 0 et `displacement` = 1 — et le
#        classificateur de couverture testait encore `disp == 2` et `(bis & 128)`.
#        Les ALIAS LOCAUX comptent : `const int bis = g_cover_bisect.load(...)` transporte la
#        constante, et c'est `bis` que la condition nomme.
#
#   D2 — CLE PUBLIEE A VALEUR LITTERALE (source). Une entree `{"cle", <litteral>}` d'une table de
#        cles PUBLIEES est une grandeur qu'aucun etat du binaire ne peut faire bouger : elle se lit
#        comme une mesure et n'en est pas une. `refset.cpp` publiait `{"subdivision", false}` et
#        `{"subdivision_rounds", 0}`, deux reglages retires.
#
#   D3..D6 — LEGENDES PERIMEES (source). Une LEGENDE est un texte que le code porte pour un
#        lecteur : un commentaire, ou une chaine litterale CONTENANT UNE ESPACE. Une chaine SANS
#        espace n'est pas une legende mais une DONNEE — une table de surveillance a le droit de
#        nommer ce que le binaire connait encore (`kLegacyUniformNames`, `kSeven`), et la compter
#        detruirait l'instrument du voisin. Quatre vocabulaires, quatre autorites :
#          D3 uniforme        `u_<famille>_<nom>` qu'AUCUN shader ne declare et qu'aucun code ne nomme
#          D4 fichier-shader  `*.glsl/.vert/.frag/.tese/.tesc/.comp` absent du dossier des shaders
#          D5 champ-gfx       `g_global_settings.<champ>` non declare dans `game/graphics/gfx.h`
#          D6 programme       nom SCREAMING_SNAKE, sur une ligne qui dit `program`/`ShaderId`,
#                             absent de l'enumeration `ShaderId` et de tout code
#
# LA PIERRE TOMBALE N'EST PAS UNE LEGENDE PERIMEE. Un commentaire qui nomme une chose RETIREE en
# DISANT qu'elle est retiree fait exactement son travail : il empeche qu'on la recree. Le marqueur
# est cherche sur le BLOC de commentaire contigu, pas sur la ligne — une explication de retrait
# tient sur dix lignes et le nom tombe rarement sur celle qui porte le mot. Le seau exclu est
# PUBLIE et CHIFFRE (`legend_tombstones`) : un seau d'exclusion muet cache ce qu'il jette.
#
# POURQUOI LE ZERO N'EST PAS UN ZERO D'INACTION. Trois defenses :
#   1. les detecteurs sont joues, dans ce processus et par les MEMES fonctions, sur un arbre
#      JETABLE ou l'on a seme un cas A PRENDRE et un cas A LAISSER (`dead_selftests_failed`) ;
#   2. les corpus ont leur temoin : un jeton VIVANT que le detecteur doit trouver present
#      (`census_corpus_control`), sans quoi « aucune occurrence » serait aussi ce que rendrait un
#      corpus vide ;
#   3. le MEME recensement est rejoue sur l'arbre TEL QU'IL ETAIT au commit EPINGLE d'avant l'item
#      (`dead_before_sites`), qui doit etre NON NUL. Un temoin « avant » lu a `HEAD` deviendrait
#      faux a la seconde ou l'on commite.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Source manquante, corpus vide, temoin a
# zero, controle seme en echec : on publie une valeur NON NULLE qui ferme la porte, jamais un zero
# par silence. Le script sort en 0 meme quand il accuse — c'est le validateur qui juge.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "dead_audit_ran=0"; echo "dead_legend_sites=9001"; exit 1; }
cd "$ROOT" || exit 1

# Le commit d'AVANT l'item, EPINGLE. Jamais `HEAD` : un temoin « avant » lu a HEAD s'accuse
# lui-meme des le commit et se met a dire zero.
BEFORE_COMMIT=56fbfe875d75702f28e86dc9f8ea9b320df0e2c8

python3 - "$BEFORE_COMMIT" <<'PYEOF'
import os, re, subprocess, sys, tempfile, shutil
from pathlib import Path

BEFORE_COMMIT = sys.argv[1]

# ── LA PUBLICATION ──────────────────────────────────────────────────────────────────────────────
# UNE VALEUR NE PORTE JAMAIS D'ESPACE. Le moissonneur de `proof_run.sh` ne retient que
# `^cle=[^[:space:]]+$` : une raison ecrite en francais serait publiee pour personne. On colle les
# espaces AU POINT DE PUBLICATION, jamais a la main dans chaque appel.
OUT = []
def pub(k, v):
    OUT.append('%s=%s' % (k, re.sub(r'\s+', '_', str(v))))
REASONS = []
PENALTY = [0]
def note(msg, cost=1000):
    REASONS.append(msg)
    PENALTY[0] += cost

# ── LE DECOUPEUR : CODE d'un cote, LEGENDE de l'autre ───────────────────────────────────────────
# Un `grep` ne sait pas si une occurrence est du code ou un commentaire, et c'est TOUTE la question
# ici. Ce scanner rend, pour chaque fichier, la suite des segments (`code` | `legend`) avec leur
# ligne. Il connait `//`, `/* */`, `;` (GOAL), `#` (python/shell) et les chaines `"..."`.
LC = {'.cpp': '//', '.h': '//', '.hpp': '//', '.c': '//', '.glsl': '//', '.vert': '//',
      '.frag': '//', '.tese': '//', '.tesc': '//', '.comp': '//', '.java': '//',
      '.gc': ';', '.gd': ';', '.py': '#'}
BLOCKED = {'.cpp', '.h', '.hpp', '.c', '.glsl', '.vert', '.frag', '.tese', '.tesc', '.comp', '.java'}

def segments(text, lc, block):
    out = []
    i = 0; n = len(text); cur = []; line = 1; cl = 1
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

WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')

# ── LES CORPUS ──────────────────────────────────────────────────────────────────────────────────
# ROOTS : ou l'on demande « cette chose existe-t-elle encore ». Large a dessein — un nom encore
# nomme QUELQUE PART dans le code du depot n'est pas retire. `test/` (fixtures, 92 Mo) et
# `goal_src/jak2|jak3` sont hors : ils ne peuvent ni declarer ni lire un uniforme de notre
# renderer jak1, et les lire doublerait le temps du recensement.
ROOTS = ['game', 'common', 'goal_src/jak1', 'android', 'tools', 'goalc', 'decompiler']
# CORPUS : ou l'on cherche les legendes. Notre couche — renderer, donnees personnalisees, GOAL
# ajoute, pont noyau — et pas les sources traduites de Naughty Dog, qui ne se reecrivent pas.
CORPUS = ['game/graphics', 'common/custom_data', 'goal_src/jak1/pc', 'game/kernel/jak1']
CORPUS_EXT = ('.cpp', '.h', '.hpp', '.glsl', '.vert', '.frag', '.tese', '.tesc', '.comp', '.gc')

def build_world(base):
    """Rend le monde lisible depuis `base` : mots du CODE, noms de fichiers, shaders, gfx, ShaderId."""
    b = Path(base)
    code_words = set()
    basenames = set()
    nfiles = 0
    for r in ROOTS:
        d = b / r
        if not d.is_dir():
            continue
        for p in d.rglob('*'):
            if not p.is_file():
                continue
            basenames.add(p.name)
            if p.suffix not in LC:
                continue
            nfiles += 1
            try:
                t = p.read_text(errors='ignore')
            except Exception:
                continue
            for k, s, l in segments(t, LC[p.suffix], p.suffix in BLOCKED):
                if k == 'code':
                    code_words.update(WORD.findall(s))
    sh = b / 'game/graphics/opengl_renderer/shaders'
    shader_files = {p.name for p in sh.rglob('*') if p.is_file()} if sh.is_dir() else set()
    shader_text = '\n'.join(p.read_text(errors='ignore') for p in sh.rglob('*') if p.is_file()) if sh.is_dir() else ''
    declared = set(re.findall(r'uniform\s+\w+\s+(\w+)', shader_text))
    gfx = b / 'game/graphics/gfx.h'
    gfx_fields = set()
    if gfx.is_file():
        gfx_fields = set(WORD.findall(''.join(
            s for k, s, l in segments(gfx.read_text(errors='ignore'), '//', True) if k == 'code')))
    shid = b / 'game/graphics/opengl_renderer/Shader.h'
    enum = set()
    if shid.is_file():
        enum = set(re.findall(r'^\s*([A-Z][A-Z0-9_]*)\s*=\s*\d+', shid.read_text(errors='ignore'), re.M))
    return dict(code_words=code_words, basenames=basenames, nfiles=nfiles,
                shader_files=shader_files, declared=declared, gfx_fields=gfx_fields, enum=enum)

# ── D3..D6 : LES LEGENDES ───────────────────────────────────────────────────────────────────────
# Le marqueur de PIERRE TOMBALE. Cherche sur le BLOC, jamais sur la ligne.
TOMB = re.compile(r"RETIRE|SUPPRIM|supprim|retir|purge|n'existe\w* plus|plus pousse|plus declare"
                  r"|removed|no longer|part avec|partent avec|ne sont plus|n'est plus|DELETED"
                  r"|deleted|abandonn|disparu|a quitte|A QUITTE|GONE|jamais livre|est parti", re.I)
# `u_<famille>_<nom>` : DEUX segments au moins. Les uniformes a un seul segment (`u_radius`,
# `u_tex`, `u_time`...) sont locaux aux shaders d'AO et d'herbe ; la prose francaise de nos
# sources GOAL utilise la meme forme pour ses vecteurs unitaires (`u_courant - u_modele`), et
# aucune autorite ne permet de les separer. Le seau est publie, pas ignore en silence.
RX_U = re.compile(r'\bu_[a-z][a-z0-9]*_[a-z0-9_]+\b')
RX_U1 = re.compile(r'\bu_[a-z][a-z0-9]*\b')
RX_F = re.compile(r'\b[a-z_][a-z0-9_.-]*\.(?:glsl|vert|frag|tese|tesc|comp)\b')
RX_G = re.compile(r'\bg_global_settings\.([a-z_][a-z0-9_]*)')
RX_P = re.compile(r'\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+\b')
PROGWORD = re.compile(r'program|ShaderId')

def legend_blocks(segs):
    """Regroupe les segments de LEGENDE contigus (lignes consecutives) en BLOCS."""
    out = []; cur = []
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

def scan_legends(base, world):
    """Rend (hits, tombs, single_segment, corpus_files) ; hits = {categorie: [(jeton, fichier, ligne)]}."""
    b = Path(base)
    hits = {'uniforme': [], 'fichier-shader': [], 'champ-gfx': [], 'programme': []}
    tombs = []; single = []; nf = 0
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
                tomb = bool(TOMB.search(' '.join(s for k, s, l in blk)))
                for k, s, l in blk:
                    st = s.lstrip()
                    # une directive #include n'est pas une legende : elle NOMME le fichier qu'elle lit
                    if st.startswith('#include'):
                        continue
                    # une chaine SANS espace est une DONNEE, pas une legende
                    if st.startswith('"') and ' ' not in s:
                        continue
                    def add(cat, tok):
                        (tombs if tomb else hits[cat]).append((tok, rel, l))
                    for m in RX_U.finditer(s):
                        t = m.group(0)
                        if t not in world['declared'] and t not in world['code_words']:
                            add('uniforme', t)
                    for m in RX_U1.finditer(s):
                        t = m.group(0)
                        if '_' in t[2:]:
                            continue
                        if t not in world['declared'] and t not in world['code_words']:
                            single.append((t, rel, l))
                    for m in RX_F.finditer(s):
                        if m.group(0) not in world['shader_files']:
                            add('fichier-shader', m.group(0))
                    for m in RX_G.finditer(s):
                        if m.group(1) not in world['gfx_fields']:
                            add('champ-gfx', m.group(0))
                    if PROGWORD.search(s):
                        for m in RX_P.finditer(s):
                            t = m.group(0)
                            if (t not in world['enum'] and t not in world['code_words']
                                    and not t.startswith('GL_')):
                                add('programme', t)
    return hits, tombs, single, nf

# ── D1 : LES PORTEUSES ET LEURS CONSTANTES DE CONSTRUCTION ──────────────────────────────────────
CARRIER_ROOTS = ['game/graphics', 'common/custom_data', 'game/kernel/jak1']
CARRIER_EXT = ('.cpp', '.h', '.hpp')
HDR = re.compile(r'^\s*(?:static\s+)?(?:inline\s+)?void\s+(?:([A-Za-z_]\w*)::)?([a-z_]\w*)\s*\(')
STORE = re.compile(r'\b(g_\w+)\s*\.\s*store\s*\(\s*(\w+)|(?:^|\s)(g_\w+|m_\w+)\s*=\s*(\w+)\s*;')
CONSTDEF = re.compile(r'constexpr\s+\w+\s+(\w+)\s*=\s*(-?\d+|true|false)\s*;')
LOCALDEF = re.compile(r'const\s+\w+\s+(\w+)\s*=\s*([A-Za-z_][\w:]*|-?\d+|true|false)\s*;')
# Une DEFINITION ou une DECLARATION n'est pas un site d'appel : ses « arguments » sont des
# parametres, que rien ne resout, et les compter rendrait TOUTE porteuse non constante.
NOTCALL = re.compile(r'\b(void|static|virtual|inline)\s+[\w:]*$')
# Le contexte CONDITIONNEL : la ligne decide quelque chose.
COND = re.compile(r'(\?|&&|\|\||==|!=|>=|<=|<|>|&|\||!)')

def code_lines(p, keep_strings=False):
    """Le texte du fichier SANS ses commentaires, ligne a ligne. `keep_strings` garde les chaines :
    une table de cles PUBLIEES ne se lit pas sans elles — sans ce drapeau `{"cle", false}` devient
    `{, false}` et le detecteur rend zero sur une table pleine."""
    t = p.read_text(errors='ignore')
    n = t.count('\n') + 2
    out = [''] * n
    for k, s, l in segments(t, '//', True):
        if k == 'legend' and keep_strings and s.lstrip().startswith('"'):
            k = 'code'
        if k != 'code':
            continue
        ln = l
        for piece in s.split('\n'):
            if ln < n:
                out[ln] += piece
            ln += 1
    return out

def split_args(call):
    depth = 0; cur = ''; out = []
    for ch in call:
        if ch == '(':
            depth += 1
            if depth > 1:
                cur += ch
        elif ch == ')':
            depth -= 1
            if depth == 0:
                out.append(cur)
                return out
            cur += ch
        elif ch == ',' and depth == 1:
            out.append(cur); cur = ''
        else:
            cur += ch
    return []

def scan_carriers(base):
    """Rend (n_porteuses, {variable: (porteuse, valeur)}, sites_de_condition)."""
    b = Path(base)
    files = [p for d in CARRIER_ROOTS for p in sorted((b / d).rglob('*'))
             if (b / d).is_dir() and p.is_file() and p.suffix in CARRIER_EXT]
    CODE = {str(p.relative_to(b)): code_lines(p) for p in files}
    TXT = {f: '\n'.join(l) for f, l in CODE.items()}
    consts = {}
    for f, t in TXT.items():
        for mm in CONSTDEF.finditer(t):
            consts[mm.group(1)] = mm.group(2)

    def resolve(f, expr, depth=0):
        e = expr.strip()
        if re.fullmatch(r'-?\d+|true|false', e):
            return e
        if depth > 3:
            return None
        tail = e.split('::')[-1]
        if tail in consts:
            return consts[tail]
        for mm in LOCALDEF.finditer(TXT.get(f, '')):
            if mm.group(1) == tail:
                return resolve(f, mm.group(2), depth + 1)
        return None

    carriers = {}
    for f, lines in CODE.items():
        for i, l in enumerate(lines):
            m = HDR.match(l)
            if not m:
                continue
            hdr = l; j = i
            while ') {' not in hdr and '){' not in hdr and j - i < 8 and j + 1 < len(lines):
                j += 1; hdr += ' ' + lines[j]
            if ') {' not in hdr and '){' not in hdr:
                continue
            params = hdr[hdr.index('(') + 1:hdr.rindex(')')]
            pn = []
            for a in params.split(','):
                w = WORD.findall(a)
                pn.append(w[-1] if w else None)
            if not any(pn):
                continue
            body = []; k2 = j + 1
            while k2 < len(lines) and lines[k2].strip() != '}' and k2 - j < 40:
                body.append(lines[k2]); k2 += 1
            tgt = {}
            for bline in body:
                for mm in STORE.finditer(bline):
                    var = mm.group(1) or mm.group(3)
                    src = mm.group(2) or mm.group(4)
                    if src in pn:
                        tgt[src] = var
            if tgt:
                carriers[(m.group(2), m.group(1))] = (f, i + 1, pn, tgt)

    const_vars = {}
    for (name, cls), (f, ln, pn, tgt) in sorted(carriers.items()):
        sites = []
        for f2, t in TXT.items():
            for mm in re.finditer(r'\b' + re.escape(name) + r'\s*\(', t):
                if NOTCALL.search(t[max(0, mm.start() - 60):mm.start()]):
                    continue
                a = split_args(t[mm.end() - 1:mm.end() + 400])
                if len(a) != len(pn):
                    continue
                sites.append((f2, a))
        if not sites:
            continue
        for p, var in tgt.items():
            idx = pn.index(p)
            vals = {resolve(f2, a[idx]) for f2, a in sites}
            if len(vals) == 1 and None not in vals:
                const_vars[var] = (name, vals.pop(), len(sites))

    # LES ALIAS LOCAUX. `const int bis = g_cover_bisect.load(...)` transporte la constante ; c'est
    # `bis` que la condition nomme, pas `g_cover_bisect`. Un alias se cherche dans le MEME fichier.
    alias = {}
    for var in const_vars:
        for f, t in TXT.items():
            for mm in re.finditer(r'\b(?:const\s+)?\w+\s+(\w+)\s*=\s*' + re.escape(var)
                                  + r'\s*(?:\.\s*load\s*\([^)]*\))?\s*;', t):
                alias.setdefault(f, set()).add(mm.group(1))

    sites = []
    for f, lines in CODE.items():
        syms = set(const_vars) | alias.get(f, set())
        for i, l in enumerate(lines):
            if not COND.search(l):
                continue
            for s in syms:
                for mm in re.finditer(r'\b' + re.escape(s) + r'\b', l):
                    # Ni la DECLARATION de l'alias, ni la DEFINITION de la variable elle-meme
                    # (`std::atomic<int> g_x{0};` porte un `<` et se faisait compter) ne decident
                    # quoi que ce soit.
                    if re.search(r'\b' + re.escape(s) + r'\s*(=[^=]|\{)', l[mm.start():]):
                        continue
                    sites.append((s, f, i + 1))
    return len(carriers), const_vars, sites

# ── D2 : LES CLES PUBLIEES A VALEUR LITTERALE ───────────────────────────────────────────────────
# L'autorite est la fonction qui CONSTRUIT l'objet publie. On lit son corps, pas tout le fichier :
# une declaration de table sur UNE ligne ferait avaler la suivante par une plage `sed`.
PUBKEY_FILE = 'game/graphics/refset.cpp'
PUBKEY_FN = 'qualification_effective_options'
RX_PUBKEY = re.compile(r'\{\s*"([a-z_][a-z0-9_]*)"\s*,\s*(true|false|-?\d+(?:\.\d+)?f?)\s*\}')

def scan_pubkeys(base):
    p = Path(base) / PUBKEY_FILE
    if not p.is_file():
        return None, []
    lines = code_lines(p, keep_strings=True)
    start = None
    for i, l in enumerate(lines):
        if PUBKEY_FN + '(' in l and 'return' not in l:
            start = i
            break
    if start is None:
        return None, []
    body = []
    depth = 0; seen = False
    for i in range(start, min(len(lines), start + 400)):
        depth += lines[i].count('{') - lines[i].count('}')
        body.append((i + 1, lines[i]))
        if lines[i].count('{'):
            seen = True
        if seen and depth <= 0:
            break
    out = []
    for ln, l in body:
        for mm in RX_PUBKEY.finditer(l):
            out.append((mm.group(1), mm.group(2), ln))
    return len(body), out

# ── LE RECENSEMENT D'AUJOURD'HUI ────────────────────────────────────────────────────────────────
world = build_world('.')
pub('census_root_files', world['nfiles'])
pub('census_code_words', len(world['code_words']))
pub('census_shader_files', len(world['shader_files']))
pub('census_declared_uniforms', len(world['declared']))
pub('census_shaderids', len(world['enum']))
pub('census_gfx_fields', len(world['gfx_fields']))
if world['nfiles'] == 0 or not world['shader_files'] or not world['declared'] or not world['enum']:
    note('monde-illisible')

# LES TEMOINS DE CORPUS. Une porte VIVANTE doit y repondre : a zero, le corpus n'est pas lu et
# « aucune occurrence » ne prouverait rien.
# UN TEMOIN NE PEUT PAS ETRE UNE CHOSE QU'UN ITEM OUVERT DOIT SUPPRIMER
# (census-audit-blind-spots, 2026-09-12). C'etait `u_pbr_mode`, que
# `lib/census/lighting-legacy-purge.sh` liste parmi les 36 uniformes que cet item-la doit
# SUPPRIMER : le jour de la purge, `census_corpus_control` serait tombe a 2/3 et la porte de CE
# recensement serait devenue rouge pour toujours, sans que personne ne l'ait decide.
# `u_rt_light_on` est declare par `shade.glsl`, qu'aucune liste de suppression ne vise.
CTL_UNIFORM = 'u_rt_light_on'       # uniforme bien vivant, declare et pousse
CTL_SHADER = 'tfrag3.frag'          # fichier de shader bien present
CTL_ENUM = 'TFRAG3'                 # programme bien present dans ShaderId
ctl = (1 if CTL_UNIFORM in world['declared'] else 0) \
    + (1 if CTL_SHADER in world['shader_files'] else 0) \
    + (1 if CTL_ENUM in world['enum'] else 0)
pub('census_corpus_control', ctl)
if ctl != 3:
    note('temoin-de-corpus-muet(%d/3)' % ctl)

hits, tombs, single, corpus_files = scan_legends('.', world)
pub('census_corpus_files', corpus_files)
if corpus_files == 0:
    note('corpus-de-legendes-vide')
legend_total = 0
for cat in sorted(hits):
    v = hits[cat]
    legend_total += len(v)
    pub('legend_%s_sites' % cat.replace('-', '_'), len(v))
    pub('legend_%s_list' % cat.replace('-', '_'),
        ','.join(sorted({'%s@%s:%d' % (t, f, l) for t, f, l in v})) or '-')
pub('legend_sites', legend_total)
pub('legend_tombstones', len(tombs))
pub('legend_tombstone_tokens', ','.join(sorted({t for t, f, l in tombs})) or '-')
# Le seau EXCLU, chiffre et nomme : les uniformes a UN seul segment, que rien ne permet de separer
# de la prose mathematique de nos sources GOAL.
pub('legend_uniform_single_segment_excluded', len(single))
pub('legend_uniform_single_segment_list',
    ','.join(sorted({'%s@%s:%d' % (t, f, l) for t, f, l in single})) or '-')

n_carriers, const_vars, cond_sites = scan_carriers('.')
pub('dead_carriers_audited', n_carriers)
pub('dead_carriers_constant', len(const_vars))
pub('dead_carriers_constant_list',
    ','.join('%s=%s(%s,%dsites)' % (v, k[0], k[1], k[2]) for v, k in sorted(const_vars.items())) or '-')
pub('dead_cond_sites', len(cond_sites))
pub('dead_cond_list', ','.join('%s@%s:%d' % (s, f, l) for s, f, l in sorted(cond_sites)) or '-')
if n_carriers == 0:
    note('aucune-porteuse-lue')

pubkey_body, pubkeys = scan_pubkeys('.')
if pubkey_body is None:
    note('table-de-cles-publiees-illisible')
    pubkey_body = 0
pub('dead_pubkey_body_lines', pubkey_body)
pub('dead_pubkey_sites', len(pubkeys))
pub('dead_pubkey_list', ','.join('%s=%s@%d' % (k, v, l) for k, v, l in pubkeys) or '-')

# ── LES CONTROLES SEMES ─────────────────────────────────────────────────────────────────────────
# Les MEMES fonctions, sur un arbre JETABLE ou l'on a seme un cas A PRENDRE et un cas A LAISSER.
# Sans eux, un zero de detecteur aveugle serait indistinguable d'un zero de population propre.
ST_RUN = [0]; ST_FAIL = [0]
def check(cond, label):
    ST_RUN[0] += 1
    if not cond:
        ST_FAIL[0] += 1
        REASONS.append('controle-echoue:' + label)

td = tempfile.mkdtemp()
try:
    def w(rel, txt):
        p = Path(td) / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(txt)
    # le monde jetable : un shader qui declare un uniforme, une enum, un gfx.h
    w('game/graphics/opengl_renderer/shaders/zz_live.frag',
      'uniform float u_zz_live;\nvoid main(){}\n')
    w('game/graphics/opengl_renderer/Shader.h', 'enum class ShaderId {\n  ZZ_LIVE = 0,\n};\n')
    w('game/graphics/gfx.h', 'struct GS {\n  int zz_live_field = 0;\n};\n')
    # Le corpus jetable : quatre legendes A PRENDRE, quatre A LAISSER, une DONNEE, une tombale.
    # AUCUN mot de ce bloc ne doit porter un marqueur de retrait : le marqueur se cherche sur le
    # BLOC, et un seul mot classerait les huit lignes en pierre tombale — le controle se mettrait
    # a passer pour la mauvaise raison.
    w('game/graphics/zz_corpus.cpp', '\n'.join([
        "// cas A : `u_zz_dead` n'apparait dans aucun shader du dossier.",
        '// cas B : `u_zz_live` est bien declare par zz_live.frag.',
        '// cas C : le fichier zz_dead.frag manque au dossier des shaders.',
        '// cas D : le fichier zz_live.frag y figure.',
        '// cas E : g_global_settings.zz_dead_field manque a gfx.h.',
        '// cas F : g_global_settings.zz_live_field y figure.',
        "// cas G : le program ZZ_DEAD_PROG manque a l'enumeration.",
        '// cas H : le program ZZ_LIVE y figure.',
        'const char* zz_table[] = {"u_zz_datum"};',
        '']))
    # Le bloc TOMBALE : il nomme un uniforme mort EN DISANT qu'"'"'il est retire, et le nom tombe sur
    # une ligne qui ne porte pas le marqueur — c'"'"'est exactement pourquoi le marqueur se cherche
    # sur le bloc.
    w('game/graphics/zz_tomb.cpp', '\n'.join([
        '// `u_zz_buried` est RETIRE du depot.',
        '// Cette ligne le nomme encore sans porter le marqueur elle-meme.',
        'void g(){}',
        '']))
    zw = build_world(td)
    zh, zt, zs, znf = scan_legends(td, zw)
    check(znf >= 2, 'corpus-jetable-lu')
    zu = {t for t, f, l in zh['uniforme']}
    check('u_zz_dead' in zu, 'uniforme-mort-pris')
    check('u_zz_live' not in zu, 'uniforme-vivant-laisse')
    check('u_zz_datum' not in zu, 'chaine-sans-espace-traitee-en-donnee')
    zf = {t for t, f, l in zh['fichier-shader']}
    check('zz_dead.frag' in zf, 'fichier-mort-pris')
    check('zz_live.frag' not in zf, 'fichier-vivant-laisse')
    zg = {t for t, f, l in zh['champ-gfx']}
    check('g_global_settings.zz_dead_field' in zg, 'champ-mort-pris')
    check('g_global_settings.zz_live_field' not in zg, 'champ-vivant-laisse')
    zp = {t for t, f, l in zh['programme']}
    check('ZZ_DEAD_PROG' in zp, 'programme-mort-pris')
    check('ZZ_LIVE' not in zp, 'programme-vivant-laisse')
    zbur = {t for t, f, l in zt}
    check('u_zz_buried' in zbur, 'pierre-tombale-exclue')
    check('u_zz_dead' not in zbur, 'legende-vivante-non-classee-tombale')

    # les porteuses, sur un arbre jetable : une constante de construction, une variable
    w('game/kernel/jak1/zz_carrier.cpp', '\n'.join([
        'static std::atomic<int> g_zz_const{0};',
        'static std::atomic<int> g_zz_var{0};',
        'static void zz_publish(int a, int b) {',
        '  g_zz_const.store(a);',
        '  g_zz_var.store(b);',
        '}',
        'void caller1(int v) { zz_publish(7, v); }',
        'void caller2(int v) { zz_publish(7, v); }',
        'void reader() {',
        '  const int c = g_zz_const.load();',
        '  const int d = g_zz_var.load();',
        '  if (c == 3 && d == 3) { return; }',
        '}',
        '']))
    zn, zc, zsit = scan_carriers(td)
    check(zn >= 1, 'porteuse-jetable-lue')
    check('g_zz_const' in zc, 'porteuse-constante-prise')
    check('g_zz_var' not in zc, 'porteuse-variable-laissee')
    check(any(s == 'c' for s, f, l in zsit), 'alias-de-constante-pris')
    check(not any(s == 'd' for s, f, l in zsit), 'alias-de-variable-laisse')

    # la table de cles publiees
    w(PUBKEY_FILE, '\n'.join([
        'Json ' + PUBKEY_FN + '() {',
        '  return {{"zz_dead_key", false}, {"zz_dead_num", 0},',
        '          {"zz_live_key", gs.zz_live_field}};',
        '}',
        '']))
    _, zk = scan_pubkeys(td)
    zkk = {k for k, v, l in zk}
    check('zz_dead_key' in zkk and 'zz_dead_num' in zkk, 'cle-litterale-prise')
    check('zz_live_key' not in zkk, 'cle-calculee-laissee')
finally:
    shutil.rmtree(td, ignore_errors=True)
pub('dead_selftests_run', ST_RUN[0])
pub('dead_selftests_failed', ST_FAIL[0])
if ST_FAIL[0]:
    PENALTY[0] += 1000 * ST_FAIL[0]

# ── LE TEMOIN « AVANT », SUR UN COMMIT EPINGLE ──────────────────────────────────────────────────
# CE BLOC N'ENTRE PAS DANS LA SOMME : c'est un temoin de NON-VACUITE, pas un verdict. Un objet git
# absent le rend muet (`dead_before_read=0`), il ne ferme aucune porte. Mais un zero ici voudrait
# dire que les detecteurs ne mordaient deja pas AVANT l'item, et le vert d'aujourd'hui ne
# vaudrait rien.
pub('dead_before_commit', BEFORE_COMMIT[:10])
before_read = 0; before_total = -1; b_cond = -1; b_leg = -1; b_key = -1
bt = tempfile.mkdtemp()
try:
    paths = list(ROOTS)
    ok = subprocess.run(['git', 'archive', BEFORE_COMMIT] + paths,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if ok.returncode == 0 and ok.stdout:
        tar = subprocess.run(['tar', '-x', '-C', bt], input=ok.stdout,
                             stderr=subprocess.DEVNULL)
        if tar.returncode == 0 and (Path(bt) / 'game/graphics/gfx.h').is_file():
            before_read = 1
            bw = build_world(bt)
            bh, btm, bsg, bnf = scan_legends(bt, bw)
            b_leg = sum(len(v) for v in bh.values())
            _, _, bsit = scan_carriers(bt)
            b_cond = len(bsit)
            _, bk = scan_pubkeys(bt)
            b_key = len(bk)
            before_total = b_leg + b_cond + b_key
finally:
    shutil.rmtree(bt, ignore_errors=True)
pub('dead_before_read', before_read)
pub('dead_before_legend_sites', b_leg)
pub('dead_before_cond_sites', b_cond)
pub('dead_before_pubkey_sites', b_key)
pub('dead_before_sites', before_total)
if before_read == 1 and before_total <= 0:
    note('temoin-avant-a-zero:les-detecteurs-ne-mordaient-deja-pas')

# ── LA SOMME, ET SA POLARITE ────────────────────────────────────────────────────────────────────
TOTAL = legend_total + len(cond_sites) + len(pubkeys) + PENALTY[0]
pub('dead_audit_ran', 1)
pub('dead_penalty', PENALTY[0])
pub('dead_reason', ';'.join(REASONS) if REASONS else '-')
pub('dead_legend_sites', TOTAL)
print('\n'.join(OUT))
PYEOF
exit 0
