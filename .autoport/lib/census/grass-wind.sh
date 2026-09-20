#!/usr/bin/env bash
# grass-wind — LE RECENSEMENT. Il MESURE, il n'ecrit aucun fichier, il publie sur stdout
# une `cle=valeur` par ligne (proof_run.sh:1599 ne moissonne que cette forme, et jette toute
# valeur contenant une espace).
#
# CE QU'IL MESURE, ET OU. Les quatre termes du contrat sont des grandeurs de la LOI de vent.
# La loi vit dans UN SEUL texte, `shaders/grass_wind.glsl`, que le pilote splice dans
# `grass.vert` et que `GrassBakeCore.cpp` `#include` : l'outil hors ligne mesure donc le texte
# que l'appareil compile, pas une recopie. Ce que l'outil ne peut PAS voir — que l'appareil ait
# bien ce texte-la, que l'uniforme d'ablation existe, que des brins soient reellement animes —
# est lu dans le journal de la course, dans les cles que seul le moteur ecrit.
#
# LES SEUILS NE SONT PAS ICI. Ils sont des `constexpr` de GrassBakeCore.h, imprimes par l'outil
# qui mesure et relus tels quels : un seuil recopie dans le juge derive du code mesure et rend
# la porte fausse en silence.
set -u

AP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT="$(cd "$AP/.." && pwd)"
cd "$ROOT" || exit 0

ARMED="${AUTOPORT_CENSUS_ARMED:-1}"
ELOG="${AUTOPORT_CENSUS_DIR:-}/proof-engine.log"

# Le commit AVANT cet item : l'ancre du temoin de non-regression de `grass_occ`. Ancre sur un
# marqueur fige, jamais sur HEAD — lu a `HEAD:` le temoin s'accuse lui-meme des le commit.
OCC_BASE="b7e7c5acb3"

emit(){ printf '%s=%s\n' "$1" "$2"; }

# --- ce que seul le MOTEUR peut ecrire ; -1 = MUET, distinct de zero ------------------------
eng(){
  local v=""
  if [ -n "${AUTOPORT_CENSUS_DIR:-}" ] && [ -s "$ELOG" ]; then
    v=$(grep -ao "$1=[0-9]\+" "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2)
  fi
  printf '%s' "${v:--1}"
}

# --- l'outil hors ligne ----------------------------------------------------------------------
BUILD_RC=0
"$AP/lib/build_x86.sh" --target grass_bake >/dev/null 2>&1 || BUILD_RC=$?
emit grass_wind_tool_build_rc "$BUILD_RC"
TOOL="$ROOT/build/tools/grass_bake/grass_bake"
if [ ! -x "$TOOL" ]; then
  emit grass_wind_tool_present 0
  emit grass_wind_defects 99
  exit 0
fi
emit grass_wind_tool_present 1

LEVELS="training beach village1"
RAW="${AUTOPORT_CENSUS_DIR:-/tmp}/.gwind.raw.$$"
: > "$RAW"
for L in $LEVELS; do
  OUT=$("$TOOL" --fr3-dir out/jak1/fr3 --preset medium --wind-census "$L" 2>/dev/null)
  printf '%s\n' "$OUT" | sed -n 's/^gwind_/'"$L"'\t/p' >> "$RAW"
done

# --- le verdict hors ligne, terme par terme ---------------------------------------------------
# Chaque terme est publie SEPAREMENT, avec la valeur du regime REMPLACE a cote : « elle est
# maximale aujourd'hui » et « aujourd'hui nul » doivent se LIRE, pas se supposer. Une grandeur
# NON MESUREE (999999) compte OUVERTE : ce n'est pas 0, deliberement.
OFFOUT=$(python3 - "$RAW" "$LEVELS" <<'PYEOF'
import sys
raw, levels = sys.argv[1], sys.argv[2].split()
d = {}
for line in open(raw, encoding='utf-8', errors='replace'):
    p = line.rstrip('\n').split('\t', 1)
    if len(p) != 2 or '=' not in p[1]:
        continue
    k, v = p[1].split('=', 1)
    d.setdefault(p[0], {})[k] = v

def num(lv, k, dflt=None):
    try:
        return float(d[lv][k])
    except Exception:
        return dflt

out = []
terms = 0
gated = 0
for lv in levels:
    if lv not in d:
        out.append(('grass_wind_%s_measured' % lv, '0'))
        continue
    blades = num(lv, 'blades_total', 0.0) or 0.0
    tmeas = num(lv, 'terms_measured', 0.0) or 0.0
    out.append(('grass_wind_%s_blades_total' % lv, '%d' % blades))
    out.append(('grass_wind_%s_blades_sampled' % lv, '%d' % (num(lv, 'blades_sampled', 0) or 0)))
    out.append(('grass_wind_%s_clumps_sampled' % lv, '%d' % (num(lv, 'clumps_sampled', 0) or 0)))
    out.append(('grass_wind_%s_terms_measured' % lv, '%d' % tmeas))
    if blades <= 0:
        # pas d'herbe sur ce niveau : rien a mesurer, donc rien a juger. Dit, pas tu.
        out.append(('grass_wind_%s_gated' % lv, '0'))
        continue
    gated += 1
    out.append(('grass_wind_%s_gated' % lv, '1'))
    checks = [
        ('dispersion',   'dir_dispersion', 'dir_dispersion_off', 'max', 'ceil_dispersion'),
        ('tip_lag',      'tip_lag_ms',     'tip_lag_ms_off',     'min', 'floor_tip_lag_ms'),
        ('corr_in',      'corr_in_clump',  'corr_in_clump_off',  'min', 'floor_corr_in'),
        ('corr_between', 'corr_between',   'corr_between_off',   'max', 'ceil_corr_between'),
        ('tip_step',     'tip_step_max',   'tip_step_off',       'max', 'ceil_tip_step'),
        ('head_drift',   'head_span_deg',  'head_span_deg_off',  'min', 'floor_head_span_deg'),
    ]
    nomeas = num(lv, 'no_measurement', 999999.0)
    for name, key, okey, sense, tkey in checks:
        v = num(lv, key)
        o = num(lv, okey)
        thr = num(lv, tkey)
        out.append(('grass_wind_%s_%s' % (lv, name), '%.4f' % v if v is not None else 'absent'))
        out.append(('grass_wind_%s_%s_before' % (lv, name), '%.4f' % o if o is not None else 'absent'))
        out.append(('grass_wind_%s_%s_threshold' % (lv, name), '%.4f' % thr if thr is not None else 'absent'))
        if v is None or thr is None or v == nomeas:
            bad = 1
        elif sense == 'max':
            bad = 1 if v > thr else 0
        else:
            bad = 1 if v < thr else 0
        out.append(('grass_wind_term_%s_%s' % (lv, name), '%d' % bad))
        terms += bad
    still = num(lv, 'blades_still', -1.0)
    bad = 1 if (still is None or still < 0 or still > 0) else 0
    out.append(('grass_wind_term_%s_still' % lv, '%d' % bad)); terms += bad
    bad = 1 if tmeas != 6 else 0
    out.append(('grass_wind_term_%s_terms_measured' % lv, '%d' % bad)); terms += bad
    for pk in ('pairs_in_clump', 'pairs_between'):
        pv = num(lv, pk, 0.0) or 0.0
        out.append(('grass_wind_%s_%s' % (lv, pk), '%d' % pv))
        bad = 1 if pv <= 0 else 0
        out.append(('grass_wind_term_%s_%s' % (lv, pk), '%d' % bad)); terms += bad

out.append(('grass_wind_levels_gated', '%d' % gated))
# UNE PORTE VIDE EST UNE PORTE FAUSSE : aucun niveau juge = defaut, pas un zero.
out.append(('grass_wind_term_gate_empty', '1' if gated <= 0 else '0'))
if gated <= 0:
    terms += 1
out.append(('grass_wind_offline_terms', '%d' % terms))
for k, v in out:
    print('%s=%s' % (k, v))
PYEOF
)
printf '%s\n' "$OFFOUT"
OFFLINE_TERMS=$(printf '%s\n' "$OFFOUT" | sed -n 's/^grass_wind_offline_terms=//p' | tail -1)
[ -n "$OFFLINE_TERMS" ] || OFFLINE_TERMS=99

# --- l'empreinte du texte : l'appareil compile-t-il CE fichier ? ------------------------------
HOST_FNV=$(python3 - "$ROOT/game/graphics/opengl_renderer/shaders/grass_wind.glsl" <<'PYEOF'
import sys
h = 1469598103934665603
for b in open(sys.argv[1], 'rb').read():
    h = ((h ^ b) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
print(h)
PYEOF
)
emit grass_wind_host_model_fnv "$HOST_FNV"

# --- ce que le moteur, seul, peut dire --------------------------------------------------------
ENG_TERMS=0
if [ "$ARMED" != "0" ]; then
  E_FNV=$(eng grass_wind_model_fnv)
  E_ULOC=$(eng grass_wind_engine_uloc_ok)
  E_BLADES=$(eng grass_wind_engine_blades)
  E_REGIME=$(eng grass_wind_engine_regime)
  E_JAK=$(eng grass_wind_occ_jak_samples)
  E_OBJ=$(eng grass_wind_occ_object_samples)
  emit grass_wind_engine_model_fnv "$E_FNV"
  emit grass_wind_engine_uloc_ok "$E_ULOC"
  emit grass_wind_engine_blades "$E_BLADES"
  emit grass_wind_engine_regime "$E_REGIME"
  emit grass_wind_occ_jak_samples "$E_JAK"
  emit grass_wind_occ_object_samples "$E_OBJ"
  # le pack GLES de l'appareil est-il en retard sur le fichier ?
  T=1; [ "$E_FNV" = "$HOST_FNV" ] && T=0
  emit grass_wind_term_model_fresh "$T"; ENG_TERMS=$((ENG_TERMS + T))
  # un uniforme retire par le compilateur rend -1 et son ecriture est un no-op SILENCIEUX
  T=1; [ "$E_ULOC" = "1" ] && T=0
  emit grass_wind_term_uloc "$T"; ENG_TERMS=$((ENG_TERMS + T))
  # des brins ont-ils reellement ete animes ?
  T=1; [ "$E_BLADES" != "-1" ] && [ "$E_BLADES" -gt 0 ] 2>/dev/null && T=0
  emit grass_wind_term_engine_blades "$T"; ENG_TERMS=$((ENG_TERMS + T))
  # la course a-t-elle bien tourne sous le regime de CET item ?
  T=1; [ "$E_REGIME" = "1" ] && T=0
  emit grass_wind_term_engine_regime "$T"; ENG_TERMS=$((ENG_TERMS + T))
  # RISQUE A MESURER, PAS A SUPPOSER : `grass_occ::publish()` est partage avec `foliage-wind`.
  # Ses sources n'ont pas bouge depuis l'ancre, et ses grandeurs vivantes sont LUES, pas supposees.
  OCCD=$(git diff --numstat "$OCC_BASE" -- \
           game/graphics/opengl_renderer/GrassOccluders.h \
           game/graphics/opengl_renderer/GrassOccluders.cpp \
           game/graphics/opengl_renderer/shaders/vegetation_contact.glsl 2>/dev/null | wc -l)
  emit grass_wind_occ_anchor "$OCC_BASE"
  emit grass_wind_occ_sources_changed "$OCCD"
  T=1; [ "$OCCD" = "0" ] && T=0
  emit grass_wind_term_occ_sources "$T"; ENG_TERMS=$((ENG_TERMS + T))
  # muet des deux cotes = non mesure = ouvert
  T=1; [ "$E_JAK" != "-1" ] && [ "$E_OBJ" != "-1" ] && T=0
  emit grass_wind_term_occ_measured "$T"; ENG_TERMS=$((ENG_TERMS + T))
else
  emit grass_wind_engine_terms_skipped 1
fi
emit grass_wind_engine_terms "$ENG_TERMS"

# LA GRANDEUR DE LA PORTE : la somme des termes, tous publies separement ci-dessus.
emit grass_wind_defects "$((OFFLINE_TERMS + ENG_TERMS))"
rm -f "$RAW"
exit 0
