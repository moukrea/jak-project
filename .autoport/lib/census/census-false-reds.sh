#!/usr/bin/env bash
# census/census-false-reds.sh — LE RECENSEMENT DES MESURES FABRIQUEES, pour l'item `census-false-reds`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course, sa
# sortie `cle=valeur` rejoignant celle du moteur dans le MEME journal. Il n'ecrit aucun champ de
# `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL COMPTE. `census_unfalsifiable_gates` = le nombre de cles publiees par le recensement
# d'eclairage dont AUCUN etat de ce binaire ne peut changer la valeur. Quatre populations, chacune
# mesuree sur une source differente, chacune avec son denominateur :
#
#   1. PORTES MORTES (mesure du MOTEUR, a l'execution). Une porte dont aucun programme lie ne
#      declare l'uniforme ne peut jamais etre en desaccord a la relecture : son
#      `light_census_rb_bad_<nom>` vaut 0 par construction. Idem pour une porte que plus aucun site
#      du renderer n'enregistre. Le moteur publie `census_engine_dead_gates` avec, par porte,
#      `light_census_gate_progs_<nom>` et `light_census_gate_writes_<nom>`. C'est le defaut qui a
#      ouvert cet item : `u_rt_probe_on` etait la 3e entree de la table et repondait -1 partout.
#
#   2. ENREGISTREURS CONSTANTS (mesure de la SOURCE). Un `lighting_census::gate_x(...)` dont tous
#      les sites d'appel passent le MEME litteral entier ecrit une variable qui ne peut pas varier :
#      tout seau dont la selection demande une autre valeur est INATTEIGNABLE, et toute clause qui
#      teste cette valeur est une TAUTOLOGIE. Un enregistreur sans aucun site d'appel compte aussi.
#
#   3. JETONS MORTS (mesure de la SOURCE). Une entree d'une table de jetons que le recensement
#      cherche dans le TEXTE DES SHADERS, et dont pas une occurrence — code ou commentaire — ne
#      subsiste dans ce corpus. Elle ne peut plus jamais correspondre : elle gonfle un denominateur
#      sans pouvoir toucher au numerateur.
#
#   4. CLES PERIMEES (mesure du JOURNAL DE LA COURSE). Les cles de l'ancien indexage par POSITION
#      (`light_census_rb_bad_2`) et le seau du composite retire (`light_census_D`) ne doivent plus
#      sortir de ce binaire. Une cle renommee qui continue de sortir sous son ancien nom serait
#      exactement la mesure fabriquee qu'on retire. La correspondance avant/apres est publiee sous
#      `census_key_map`, et VERIFIEE ici : ancienne absente, nouvelle presente.
#
# POURQUOI LE ZERO N'EST PAS UN ZERO D'INACTION. Un detecteur branche sur rien rendrait le meme
# zero que quatre populations propres. Les deux detecteurs de SOURCE sont donc joues, dans ce
# meme processus et par les MEMES fonctions, sur des copies JETABLES ou l'on a SEME un cas a
# prendre et un cas a laisser : `census_selftests_failed` doit valoir 0, et chaque echec ajoute au
# compte. Le corpus a son propre temoin (`census_corpus_control`), sans quoi « aucune occurrence »
# serait aussi ce que rendrait un corpus vide.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Source manquante, valeur du moteur absente
# ou non numerique, table illisible, temoin a zero : on publie une valeur NON NULLE qui ferme la
# porte, jamais un zero par silence. Le script sort en 0 meme quand il accuse — c'est le
# validateur qui juge.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "census_audit_ran=0"; exit 1; }
cd "$ROOT" || exit 1

CENSUS_SRC="game/graphics/opengl_renderer/lighting_census.cpp"
SHADE_SRC="game/graphics/opengl_renderer/shade_proof.cpp"
HDR_SRC="game/graphics/opengl_renderer/hdr.cpp"
CENSUS_HDR="game/graphics/opengl_renderer/lighting_census.h"
SHADER_DIR="game/graphics/opengl_renderer/shaders"
CALL_DIR="game/graphics"

# UNE VALEUR NE PORTE JAMAIS D'ESPACE. Le moissonneur de `proof_run.sh` ne retient que
# `^cle=[^[:space:]]+$` : une raison ecrite en francais serait publiee pour personne. On colle les
# espaces AU POINT DE PUBLICATION, jamais a la main dans chaque appel.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "$2" | tr -s '[:space:]' '_')"; }
REASONS=""
note(){ REASONS="${REASONS:+$REASONS;}$1"; }
PENALTY=0

# L'INSTANTANE DU JOURNAL, PRIS AVANT LA PREMIERE ECRITURE. Notre sortie est APPENDUE au journal
# ou le moteur a publie ses cles : sans instantane, une relecture y retrouverait nos propres
# lignes. Un marqueur ne suffirait pas — une sortie redirigee est bufferisee par BLOCS.
ENG_SNAP=""
if [ -n "${AUTOPORT_CENSUS_DIR:-}" ]; then
  ENG_SNAP=$(mktemp 2>/dev/null) && cat "$AUTOPORT_CENSUS_DIR"/proof*-engine.log > "$ENG_SNAP" 2>/dev/null
  trap 'rm -f "$ENG_SNAP"' EXIT
fi
# La MEME normalisation que `lib/proof_run.sh` (fonction `norm`) : rien n'arrive nu, le journal
# x86 prefixe chaque ligne du temps ecoule. Ancrer sur `^` sans l'enlever, c'est ne rien trouver.
norm_snap(){
  [ -n "$ENG_SNAP" ] && [ -s "$ENG_SNAP" ] || return 0
  sed -E 's/\r$//
          s/^[0-9]{2}-[0-9]{2} [0-9:.]+ +[A-Z]\/[^(]*\( *[0-9]+\): *//
          s/^[[:space:]]*[0-9]+\.[0-9]+[[:space:]]+//
          s/^\[[0-9:]+\] *//' "$ENG_SNAP"
}

# ── LES TABLES, LUES DANS LA SOURCE ─────────────────────────────────────────────────────────────
# Ecrire ces listes ici les ferait DERIVER de celles du moteur en silence : on les lit donc dans
# le texte qui les declare, et on compte la derive entre les deux tables qui doivent coincider.
# `sed -n '/nom\[/,/};/p'` NE CONVIENT PAS : quand la declaration tient sur UNE ligne, la fin de
# plage est cherchee a partir de la ligne SUIVANTE, et la plage avale la table d'apres. Mesure :
# `kGateNames` rendait en plus les onze noms de `kLegacyUniformNames`. On s'arrete donc sur la
# ligne meme ou `};` apparait, celle de depart comprise.
table_of(){  # table_of <fichier> <nom-du-tableau>
  awk -v n="$2" 'index($0, n "[") > 0 && index($0, "{") > 0 { on = 1 }
                 on { print; if (index($0, "};") > 0) exit }' "$1" 2>/dev/null \
    | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"'
}

# ── DETECTEUR 3 : UN JETON QUI N'EXISTE NULLE PART DANS LE CORPUS ───────────────────────────────
# `hits` compte les occurrences (code OU commentaire) dans le corpus de shaders. Un jeton absent
# des DEUX ne peut plus correspondre a rien. `code` est publie a cote : c'est le contexte, pas le
# critere — une table de SURVEILLANCE a le droit de nommer une chose qui n'est plus dans le code,
# a condition que ce binaire la connaisse encore.
tok_hits(){  # tok_hits <repertoire-corpus> <jeton>
  local d="$1" t="$2" n
  n=$(grep -rhoE -- "(^|[^A-Za-z0-9_])$t([^A-Za-z0-9_]|\$)" "$d" 2>/dev/null | grep -c .) || n=0
  printf '%s' "$n"
}
tok_code_hits(){  # occurrences hors lignes dont le premier caractere non blanc ouvre `//`
  local d="$1" t="$2" n
  n=$(grep -rhE -- "(^|[^A-Za-z0-9_])$t([^A-Za-z0-9_]|\$)" "$d" 2>/dev/null \
      | grep -vE '^[[:space:]]*//' | grep -c .) || n=0
  printf '%s' "$n"
}

# ── DETECTEUR 2 : UN ENREGISTREUR DONT TOUS LES SITES PASSENT LE MEME LITTERAL ──────────────────
# Rend "<sites> <sites_litteraux> <verdict>" : verdict 1 = constante de construction ou aucun site.
rec_verdict(){  # rec_verdict <repertoire-appelants> <nom-de-l-enregistreur>
  local d="$1" r="$2" sites=0 lit=0 first="" same=1 arg
  while IFS= read -r arg; do
    [ -n "$arg" ] || continue
    sites=$((sites + 1))
    if printf '%s' "$arg" | grep -qE '^-?[0-9]+$'; then
      lit=$((lit + 1))
      if [ -z "$first" ]; then first="$arg"; elif [ "$arg" != "$first" ]; then same=0; fi
    fi
  done <<EOF
$(grep -rhE -- "lighting_census::$r\(" "$d" --include=*.cpp --include=*.h 2>/dev/null \
  | grep -vE '^[[:space:]]*//' \
  | sed -E "s/.*lighting_census::$r\(([^)]*)\).*/\1/" \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
EOF
  local verdict=0
  if [ "$sites" -eq 0 ]; then
    verdict=1
  elif [ "$lit" -eq "$sites" ] && [ "$same" -eq 1 ]; then
    verdict=1
  fi
  printf '%s %s %s' "$sites" "$lit" "$verdict"
}

# ── 0. LES SOURCES SONT-ELLES LA ────────────────────────────────────────────────────────────────
SRC_OK=1
for f in "$CENSUS_SRC" "$SHADE_SRC" "$HDR_SRC" "$CENSUS_HDR"; do
  if [ ! -f "$f" ]; then
    note "source absente: $f"
    PENALTY=$((PENALTY + 1000))
    SRC_OK=0
  fi
done
CORPUS_FILES=$(find "$SHADER_DIR" -type f \( -name '*.glsl' -o -name '*.frag' -o -name '*.vert' \) 2>/dev/null | grep -c .)
pub census_corpus_files "$CORPUS_FILES"
# LE TEMOIN DU CORPUS. Une porte VIVANTE doit y repondre : a zero, le corpus n'est pas lu et
# « aucune occurrence » ne prouverait rien.
CORPUS_CTL=$(tok_hits "$SHADER_DIR" "u_rt_light_on")
pub census_corpus_control "$CORPUS_CTL"
if [ "$CORPUS_FILES" -eq 0 ] || [ "$CORPUS_CTL" -eq 0 ]; then
  note "corpus de shaders muet (fichiers=$CORPUS_FILES temoin=$CORPUS_CTL)"
  PENALTY=$((PENALTY + 1000))
fi
pub census_audit_ran "$SRC_OK"

# ── 1. LES PORTES MORTES, MESUREES PAR LE MOTEUR ────────────────────────────────────────────────
ENG_DEAD=""
ENG_LINES=0
if [ -n "$ENG_SNAP" ]; then
  ENG_RAW=$(norm_snap | grep -aE '^census_engine_dead_gates=[0-9]+$')
  ENG_LINES=$(printf '%s' "$ENG_RAW" | grep -c .)
  ENG_DEAD=$(printf '%s\n' "$ENG_RAW" | tail -1 | sed 's/^census_engine_dead_gates=//')
fi
pub census_engine_lines "$ENG_LINES"
case "$ENG_DEAD" in
  ''|*[!0-9]*)
    note "census_engine_dead_gates absent ou non numerique dans le journal de la course"
    PENALTY=$((PENALTY + 1000))
    ENG_DEAD=0
    pub census_engine_dead_gates_read -1
    ;;
  *) pub census_engine_dead_gates_read "$ENG_DEAD" ;;
esac

# ── 2. LES ENREGISTREURS ────────────────────────────────────────────────────────────────────────
# La liste vient des DECLARATIONS de l'en-tete, pas d'ici : une porte ajoutee demain est auditee
# sans que personne n'ait a y penser.
RECORDERS=$(grep -oE '^void (gate_[a-z_]+)\(int v\);' "$CENSUS_HDR" 2>/dev/null \
            | sed -E 's/^void (gate_[a-z_]+)\(int v\);/\1/' | sort -u)
REC_N=0; REC_DEAD=0
for r in $RECORDERS; do
  read -r sites lit verdict <<EOF
$(rec_verdict "$CALL_DIR" "$r")
EOF
  REC_N=$((REC_N + 1))
  REC_DEAD=$((REC_DEAD + verdict))
  pub "census_rec_${r}_sites" "$sites"
  pub "census_rec_${r}_literal_sites" "$lit"
  [ "$verdict" -eq 0 ] || note "enregistreur constant: $r ($sites site(s), $lit litteral/aux)"
done
pub census_recorders_audited "$REC_N"
pub census_recorders_dead "$REC_DEAD"
if [ "$REC_N" -eq 0 ]; then
  note "aucun enregistreur lu dans $CENSUS_HDR"
  PENALTY=$((PENALTY + 1000))
fi

# ── 3. LES JETONS DES TABLES CHERCHEES DANS LE TEXTE DES SHADERS ────────────────────────────────
GATE_TOKENS=$(table_of "$SHADE_SRC" kGateTokens)
COMP_TOKENS=$(table_of "$HDR_SRC" kCompressionTokens)
TOK_N=0; TOK_DEAD=0; TOK_DEAD_LIST=""
for t in $GATE_TOKENS $COMP_TOKENS; do
  TOK_N=$((TOK_N + 1))
  h=$(tok_hits "$SHADER_DIR" "$t")
  c=$(tok_code_hits "$SHADER_DIR" "$t")
  pub "census_tok_${t}_hits" "$h"
  pub "census_tok_${t}_code" "$c"
  if [ "$h" -eq 0 ]; then
    TOK_DEAD=$((TOK_DEAD + 1))
    TOK_DEAD_LIST="${TOK_DEAD_LIST:+$TOK_DEAD_LIST,}$t"
  fi
done
pub census_tokens_audited "$TOK_N"
pub census_tokens_dead "$TOK_DEAD"
pub census_tokens_dead_list "${TOK_DEAD_LIST:--}"
if [ "$TOK_N" -eq 0 ]; then
  note "aucune table de jetons lue (kGateTokens/kCompressionTokens)"
  PENALTY=$((PENALTY + 1000))
fi
# Le detecteur de compression du moteur dit lui-meme s'il voit quelque chose : un detecteur aveugle
# rendrait `tonemap_sites_shader=0` sans qu'aucun shader n'ait ete lu.
HDR_WIT=$(norm_snap | grep -aE '^hdr_compression_detector_ok=[0-9]+$' | tail -1 | sed 's/^.*=//')
case "${HDR_WIT:-}" in
  1) ;;
  '') note "hdr_compression_detector_ok absent du journal"; PENALTY=$((PENALTY + 1000)) ;;
  *) note "detecteur de compression aveugle (hdr_compression_detector_ok=$HDR_WIT)"; PENALTY=$((PENALTY + 1000)) ;;
esac
pub census_hdr_detector_ok "${HDR_WIT:--1}"

# ── 3bis. LA DERIVE ENTRE LES DEUX TABLES DE PORTES ─────────────────────────────────────────────
# `kGateNames` (lighting_census) et `kGateTokens` (shade_proof) nomment les MEMES portes. Elles
# derivent en silence : un nom retire d'un cote et laisse de l'autre recree exactement le defaut
# de cet item dans l'instrument voisin.
GATE_NAMES=$(table_of "$CENSUS_SRC" kGateNames)
DRIFT=$( { printf '%s\n' $GATE_NAMES | sed 's/^/A /'; printf '%s\n' $GATE_TOKENS | sed 's/^/B /'; } \
         | awk 'NF==2{c[$2]=c[$2] $1} END{n=0; for (k in c) if (c[k] !~ /A/ || c[k] !~ /B/) n++; print n+0}')
case "$DRIFT" in ''|*[!0-9]*) DRIFT=9002; note "derive des tables illisible" ;; esac
pub census_gate_table_drift "$DRIFT"
pub census_gate_names "$(printf '%s\n' $GATE_NAMES | grep -c .)"
pub census_gate_tokens "$(printf '%s\n' $GATE_TOKENS | grep -c .)"

# ── 4. LES CLES PERIMEES ET LA CORRESPONDANCE AVANT/APRES ───────────────────────────────────────
# Une valeur de proof.txt ne peut porter AUCUN espace : elle serait jetee a la publication.
pub census_key_map "light_census_rb_bad_0>light_census_rb_bad_u_rt_light_on,light_census_rb_bad_1>light_census_rb_bad_u_pbr_mode,light_census_rb_bad_2>RETIREE,light_census_rb_bad_3>light_census_rb_bad_u_pbr_shadow_on,light_census_D>RETIREE,lc_free_D>RETIREE,lc_orig_D>RETIREE,lc_rech_D>RETIREE,lc_orig_light_D>RETIREE"
STALE=0; STALE_LIST=""
for k in light_census_rb_bad_0 light_census_rb_bad_1 light_census_rb_bad_2 light_census_rb_bad_3 \
         light_census_D lc_free_D lc_orig_D lc_rech_D lc_orig_light_D; do
  n=$(norm_snap | grep -acE "^$k=" ) || n=0
  if [ "$n" -gt 0 ]; then
    STALE=$((STALE + 1))
    STALE_LIST="${STALE_LIST:+$STALE_LIST,}$k"
  fi
done
pub census_stale_keys "$STALE"
pub census_stale_list "${STALE_LIST:--}"
[ "$STALE" -eq 0 ] || note "cles perimees encore publiees: $STALE_LIST"
# La contrepartie : les cles NEUVES doivent sortir, une par porte de la table du moteur. Un zero
# ici voudrait dire que la course n'a pas publie le recensement du tout.
NEW_OK=0
for g in $GATE_NAMES; do
  n=$(norm_snap | grep -acE "^light_census_rb_bad_$g=") || n=0
  [ "$n" -gt 0 ] && NEW_OK=$((NEW_OK + 1))
done
pub census_new_keys "$NEW_OK"
GATE_N=$(printf '%s\n' $GATE_NAMES | grep -c .)
if [ "$NEW_OK" -ne "$GATE_N" ]; then
  note "cles neuves manquantes ($NEW_OK sur $GATE_N)"
  PENALTY=$((PENALTY + 1000))
fi

# ── 5. LES CONTROLES SEMES ──────────────────────────────────────────────────────────────────────
# Les MEMES fonctions, sur des copies JETABLES ou l'on a seme un cas A PRENDRE et un cas A LAISSER.
# Sans elles, un zero de detecteur aveugle serait indistinguable d'un zero de population propre.
ST_RUN=0; ST_FAIL=0
TD=$(mktemp -d 2>/dev/null) || TD=""
if [ -n "$TD" ]; then
  mkdir -p "$TD/shaders" "$TD/call"
  printf 'uniform int u_zz_live_token;\nvoid main(){ float k = ZZ_LIVE; }\n' > "$TD/shaders/fake.glsl"
  # jetons : un absent du corpus (a PRENDRE), un present (a LAISSER)
  ST_RUN=$((ST_RUN + 1)); [ "$(tok_hits "$TD/shaders" u_zz_dead_token)" -eq 0 ] || ST_FAIL=$((ST_FAIL + 1))
  ST_RUN=$((ST_RUN + 1)); [ "$(tok_hits "$TD/shaders" u_zz_live_token)" -gt 0 ] || ST_FAIL=$((ST_FAIL + 1))
  # enregistreurs : un site a litteral unique (a PRENDRE), un site a argument variable (a LAISSER)
  printf 'void f(){\n  lighting_census::gate_zz_dead(0);\n  lighting_census::gate_zz_dead(0);\n}\n' > "$TD/call/dead.cpp"
  printf 'void g(){ lighting_census::gate_zz_live(v); }\n' > "$TD/call/live.cpp"
  read -r _s _l v1 <<EOF
$(rec_verdict "$TD/call" gate_zz_dead)
EOF
  ST_RUN=$((ST_RUN + 1)); [ "$v1" -eq 1 ] || ST_FAIL=$((ST_FAIL + 1))
  read -r _s _l v2 <<EOF
$(rec_verdict "$TD/call" gate_zz_live)
EOF
  ST_RUN=$((ST_RUN + 1)); [ "$v2" -eq 0 ] || ST_FAIL=$((ST_FAIL + 1))
  # un enregistreur que PERSONNE n'appelle doit aussi etre pris
  read -r _s _l v3 <<EOF
$(rec_verdict "$TD/call" gate_zz_absent)
EOF
  ST_RUN=$((ST_RUN + 1)); [ "$v3" -eq 1 ] || ST_FAIL=$((ST_FAIL + 1))
  rm -rf "$TD"
else
  note "aucun repertoire temporaire : controles non joues"
  PENALTY=$((PENALTY + 1000))
fi
pub census_selftests_run "$ST_RUN"
pub census_selftests_failed "$ST_FAIL"
[ "$ST_FAIL" -eq 0 ] || { note "controles semes en echec: $ST_FAIL"; PENALTY=$((PENALTY + 1000)); }

# ── 5bis. LE RECENSEMENT « AVANT », SUR UN COMMIT EPINGLE ───────────────────────────────────────
# Un zero d'aujourd'hui ne dit pas d'ou l'on vient. Les MEMES detecteurs de source sont donc joues
# sur l'arbre TEL QU'IL ETAIT avant cet item. Le commit est EPINGLE, jamais `HEAD` : un temoin
# « avant » lu a HEAD devient faux a la seconde ou l'on commite, et se met a dire zero.
# CE BLOC N'ENTRE PAS DANS LA SOMME : c'est un temoin de non-vacuite, pas un verdict. Un objet git
# absent le rend muet (`census_before_read=0`), il ne ferme aucune porte.
BEFORE_COMMIT=8e74d2d3e976aec61ef9fb3f7e6b4952bf921d8a
pub census_before_commit "$(printf '%s' "$BEFORE_COMMIT" | cut -c1-10)"
BEFORE_READ=0; B_REC=-1; B_TOK=-1; B_DRIFT=-1
BT=$(mktemp -d 2>/dev/null) || BT=""
if [ -n "$BT" ] && git archive "$BEFORE_COMMIT" "$CALL_DIR" 2>/dev/null | tar -x -C "$BT" 2>/dev/null; then
  if [ -f "$BT/$CENSUS_HDR" ] && [ -f "$BT/$SHADE_SRC" ] && [ -f "$BT/$HDR_SRC" ]; then
    BEFORE_READ=1
    B_REC=0
    for r in $(grep -oE '^void (gate_[a-z_]+)\(int v\);' "$BT/$CENSUS_HDR" \
               | sed -E 's/^void (gate_[a-z_]+)\(int v\);/\1/' | sort -u); do
      read -r _bs _bl bv <<EOF
$(rec_verdict "$BT/$CALL_DIR" "$r")
EOF
      B_REC=$((B_REC + bv))
    done
    B_TOK=0
    for t in $(table_of "$BT/$SHADE_SRC" kGateTokens) $(table_of "$BT/$HDR_SRC" kCompressionTokens); do
      [ "$(tok_hits "$BT/$SHADER_DIR" "$t")" -eq 0 ] && B_TOK=$((B_TOK + 1))
    done
    B_DRIFT=$( { table_of "$BT/$CENSUS_SRC" kGateNames | sed 's/^/A /'
                 table_of "$BT/$SHADE_SRC" kGateTokens | sed 's/^/B /'; } \
               | awk 'NF==2{c[$2]=c[$2] $1} END{n=0; for (k in c) if (c[k] !~ /A/ || c[k] !~ /B/) n++; print n+0}')
  fi
  rm -rf "$BT"
fi
pub census_before_read "$BEFORE_READ"
pub census_before_recorders_dead "$B_REC"
pub census_before_tokens_dead "$B_TOK"
pub census_before_drift "$B_DRIFT"
if [ "$BEFORE_READ" -eq 1 ]; then
  pub census_before_source_defects "$((B_REC + B_TOK + B_DRIFT))"
else
  pub census_before_source_defects -1
fi

# ── 6. LA SOMME, ET SA POLARITE ─────────────────────────────────────────────────────────────────
TOTAL=$((ENG_DEAD + REC_DEAD + TOK_DEAD + DRIFT + STALE + PENALTY))
pub census_unfalsifiable_gates "$TOTAL"
pub census_penalty "$PENALTY"
pub census_reason "${REASONS:--}"
exit 0
