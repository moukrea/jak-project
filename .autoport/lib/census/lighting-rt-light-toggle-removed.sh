#!/usr/bin/env bash
# census/lighting-rt-light-toggle-removed.sh — LA GRANDEUR `rt_light_toggle_defects`.
#
# Le sous-reglage « rt-light » (SPEC-refonte-lumiere §6.2 : RETIRE ; annexe D.4 : `u_rt_light_on`
# devient « un booleen dans le shader » porte par le maitre) choisissait le composite d'eclairage.
# Mesure du 25/09 : 0 poussee non nulle de `u_rt_light_on` sur 22 016 au telephone, 42 160/42 160
# au bureau — le telephone et le PC ne prenaient pas le meme chemin sous le MEME maitre allume.
#
#   rt_light_toggle_defects = rt_light_code_reads          lectures restantes du sous-reglage
#                                                          dans le code (commentaires exclus)
#                           + rt_light_composite_gap       poussees ou la porte du composite
#                                                          differe du maitre (moteur)
#                           + rt_light_unmeasured          1 si l'une des deux moities est muette
#
# L'ECART TELEPHONE/PC SE MESURE SUR LE BUREAU EN Y POSANT LE REGIME DU TELEPHONE. L'item epingle
# `OG_RT_LIGHT=0` (proof_env) avec le maitre allume : c'est exactement l'etat de l'appareil du
# 25/09 (sous-drapeau a 0, maitre a 1). Avec l'ancien code, chaque poussee differait du maitre ;
# si le sous-drapeau ne compose plus rien, l'ecart est nul. Le moteur le compte a la poussee
# (`light_census_gate_master_mismatch_u_lighting_on`), sur un denominateur publie
# (`..._master_on_...`) : un maitre jamais allume rend la mesure VIDE, et comptee comme defaut.
set -u
AP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(cd "$AP/.." && pwd)"
cd "$ROOT" || exit 1
ELOG="${AUTOPORT_CENSUS_DIR:-}/proof-engine.log"

# Le dernier commit AVANT que cet item ne touche au code : le temoin « avant » de la population
# que le correctif vide. Fige ici, jamais lu a HEAD (il s'accuserait lui-meme des le commit).
BEFORE=9f3e64041c

eng(){
  local v=""
  if [ -n "${AUTOPORT_CENSUS_DIR:-}" ] && [ -s "$ELOG" ]; then
    v=$(grep -ao "$1=[0-9]\+" "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2)
  fi
  printf '%s' "${v:--1}"
}

# ---- 1. les lectures restantes, dans l'arbre et au commit temoin ----------------------------
STATIC=$(python3 - "$BEFORE" <<'PY'
import re, subprocess, sys
before = sys.argv[1]
ROOTS = ['game', 'common', 'goalc', 'goal_src/jak1', 'android']
EXT_C = ('.cpp', '.h', '.hpp', '.c', '.cc', '.glsl', '.frag', '.vert', '.java', '.kt')
EXT_GOAL = ('.gc', '.gd')
EXT_HASH = ('.txt', '.cmake')
RETIRED = re.compile(r'u_rt_light_on|recharged_rt_light_enable|\bkRtLight\b|kGateRtLight|'
                     r'gate_rt_light|pc_set_rt_light|pc-set-rt-light!|OG_RT_LIGHT|'
                     r'debug\.opengoal\.rt\.light|"rt\.light"|"rt-light"|\brt_light_on\b')
CONTROL = re.compile(r'\bu_lighting_on\b')

def strip(text, kind):
    """Rend le texte sans commentaires, lignes conservees (un commentaire devient des blancs)."""
    out, i, n = [], 0, len(text)
    line_c = {'c': '//', 'goal': ';', 'hash': '#'}[kind]
    while i < n:
        ch = text[i]
        if ch == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1]); i = j + 1; continue
        if text.startswith(line_c, i):
            j = text.find('\n', i); j = n if j < 0 else j
            i = j; continue
        if kind == 'c' and text.startswith('/*', i):
            j = text.find('*/', i + 2); j = n if j < 0 else j + 2
            out.append('\n' * text.count('\n', i, j)); i = j; continue
        if kind == 'goal' and text.startswith('#|', i):
            j = text.find('|#', i + 2); j = n if j < 0 else j + 2
            out.append('\n' * text.count('\n', i, j)); i = j; continue
        out.append(ch); i += 1
    return ''.join(out)

def kind_of(p):
    if p.endswith(EXT_C): return 'c'
    if p.endswith(EXT_GOAL): return 'goal'
    if p.endswith(EXT_HASH) or p.endswith('CMakeLists.txt'): return 'hash'
    return None

def scan(files, read):
    reads, ctl, comments, where = 0, 0, 0, []
    for p in files:
        k = kind_of(p)
        if not k: continue
        raw = read(p)
        if raw is None: continue
        code = strip(raw, k)
        for ln, (rl, cl) in enumerate(zip(raw.split('\n'), code.split('\n')), 1):
            h = len(RETIRED.findall(cl))
            reads += h
            if h: where.append('%s:%d' % (p, ln))
            comments += len(RETIRED.findall(rl)) - h
            ctl += len(CONTROL.findall(cl))
    return reads, ctl, comments, where

def git(*a):
    return subprocess.run(['git', *a], capture_output=True, text=True, errors='replace').stdout

now_files = [f for f in git('ls-files', '--', *ROOTS).split('\n') if f]
def read_now(p):
    try: return open(p, encoding='utf-8', errors='replace').read()
    except OSError: return None
r, c, m, w = scan(now_files, read_now)
print('rt_light_code_files_scanned=%d' % sum(1 for f in now_files if kind_of(f)))
print('rt_light_code_reads=%d' % r)
print('rt_light_code_reads_list=%s' % (','.join(w[:20]) or 'aucune'))
print('rt_light_comment_mentions=%d' % m)
print('rt_light_scan_control=%d' % c)
# Le temoin AVANT : les memes regles sur les fichiers qui portaient un nom retire au commit fige.
cand = [l.split(':', 1)[1] for l in git('grep', '-lE', RETIRED.pattern.replace('\\b', ''), before,
                                         '--', *ROOTS).split('\n') if ':' in l]
rb, _, _, _ = scan(cand, lambda p: git('show', '%s:%s' % (before, p)))
print('rt_light_code_reads_before=%d' % rb)
PY
)
PYRC=$?
printf '%s\n' "$STATIC"
kv(){ printf '%s\n' "$STATIC" | sed -n "s/^$1=//p" | tail -1; }
READS=$(kv rt_light_code_reads); CTL=$(kv rt_light_scan_control)

# ---- 2. l'ecart de composite, compte par le moteur a la poussee -----------------------------
WRITES=$(eng light_census_gate_writes_u_lighting_on)
NONZERO=$(eng light_census_gate_nonzero_u_lighting_on)
MASTER_ON=$(eng light_census_gate_master_on_u_lighting_on)
GAP=$(eng light_census_gate_master_mismatch_u_lighting_on)
echo "rt_light_gate_writes=$WRITES"
echo "rt_light_gate_nonzero=$NONZERO"
echo "rt_light_gate_master_on=$MASTER_ON"
echo "rt_light_composite_gap=$GAP"

UNMEASURED=0; WHY=""
[ "$PYRC" -eq 0 ] && [ -n "$READS" ] || { UNMEASURED=1; WHY="${WHY}scan-en-echec,"; READS=0; }
[ "${CTL:-0}" -gt 0 ] 2>/dev/null || { UNMEASURED=1; WHY="${WHY}temoin-u_lighting_on-absent,"; }
for v in "$WRITES" "$MASTER_ON" "$GAP"; do
  [ "$v" -ge 0 ] 2>/dev/null || { UNMEASURED=1; WHY="${WHY}moteur-muet,"; break; }
done
[ "$MASTER_ON" -gt 0 ] 2>/dev/null || { UNMEASURED=1; WHY="${WHY}maitre-jamais-allume,"; }
[ "$GAP" -ge 0 ] 2>/dev/null || GAP=0
echo "rt_light_unmeasured=$UNMEASURED"
echo "rt_light_unmeasured_why=${WHY:-aucune}"
echo "rt_light_toggle_defects=$(( READS + GAP + UNMEASURED ))"
exit 0
