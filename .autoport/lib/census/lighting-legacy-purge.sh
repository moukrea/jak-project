#!/usr/bin/env bash
# census/lighting-legacy-purge.sh — LE RECENSEMENT SUR L'ARTEFACT, pour l'item `lighting-legacy-purge`.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course,
# sa sortie `cle=valeur` rejoignant celle du moteur dans le MEME journal. Il n'ecrit aucun champ
# de `proof.txt` : ni `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# POURQUOI IL EXISTE. Le contrat de l'item exige que les symboles du chemin herite soient a ZERO
# occurrence dans le `libgk.so` livre, et que leurs fichiers source aient quitte l'arbre ET les
# deux CMakeLists. La sonde GL du moteur (`lighting_census.cpp`) ne voit que le programme LIE :
# elle ne voit ni l'arbre, ni les listes de build, ni le blob de shaders fige d'Android. Ce
# script mesure ce que le moteur ne peut pas voir.
#
# LE PIEGE QU'IL NE FAUT PAS RETOMBER DEDANS. Les 43 chaines d'uniformes sont des LITTERAUX de
# `lighting_census.cpp` : elles vivent donc, par construction, dans `libgk.so` et dans `gk`. Un
# compteur qui les chercherait dans ces binaires ferait echouer sa propre porte a jamais. On ne
# les cherche donc QUE dans le blob de shaders Android ; dans les binaires on cherche des noms de
# FICHIERS et de SYMBOLES que le recensement ne porte pas.
#
# POLARITE, NON NEGOCIABLE : TOUT INCONNU VAUT DEFAUT. Artefact manquant, temoin a zero, valeur
# du moteur absente ou non numerique : on publie une valeur NON NULLE qui ferme la porte, jamais
# un zero par silence. Le script sort en 0 meme quand il accuse — c'est le validateur qui juge.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "lighting_legacy_census_ran=0"; exit 1; }
cd "$ROOT" || exit 1

BLOB="build-android/shaders/shaders_android_blob.h"
SO="build-android/lib/arm64-v8a/libgk.so"
GK="build/game/gk"
CENSUS_SRC="game/graphics/opengl_renderer/lighting_census.cpp"

pub(){ printf '%s=%s\n' "$1" "$2"; }

# L'INSTANTANE — il repond a un defaut MESURE le 2026-09-12. La sortie de ce script est APPENDUE
# au journal brut de la course, celui-la meme ou le moteur publie sa propre ligne
# `lighting_legacy_sites=`. Un `tail -1` sur ce journal relit donc le TOTAL DU SCRIPT au lieu de
# la valeur du moteur, et la somme se re-additionne a chaque relecture (mesure : engine_sites=245
# alors que le moteur avait publie 0).
# Un marqueur ecrit sur la sortie standard ne suffirait PAS a s'en proteger : une sortie redirigee
# vers un fichier est bufferisee par BLOCS, donc le marqueur peut ne pas etre encore dans le
# fichier au moment ou on le relit. On prend donc un INSTANTANE du journal AVANT d'ecrire quoi que
# ce soit : ce qu'on ajoute ensuite ne peut pas s'y trouver, quelle que soit la bufferisation.
ENG_SNAP=""
if [ -n "${AUTOPORT_CENSUS_DIR:-}" ]; then
  ENG_SNAP=$(mktemp 2>/dev/null) && cat "$AUTOPORT_CENSUS_DIR"/proof*-engine.log > "$ENG_SNAP" 2>/dev/null
  trap 'rm -f "$ENG_SNAP"' EXIT
fi
# Une cle de TEXTE ne se vide jamais toute seule (`publish_text` garde la derniere valeur) :
# on ecrit "-" quand il n'y a rien a dire, jamais la chaine vide.
REASONS=""
note(){ REASONS="${REASONS:+$REASONS;}$1"; }

# `grep -ac` compte les LIGNES qui portent le motif. C'est la grandeur demandee par l'item : une
# ligne du blob qui nomme un uniforme supprime est une ligne de trop, qu'elle soit du code ou un
# commentaire (le blob Android embarque les commentaires).
# LA FRONTIERE DE JETON, ET POURQUOI ELLE N'EST PAS UN DETAIL. `tex_PBR_S` (echantillonneur
# speculaire, SUPPRIME) est un PREFIXE de `tex_PBR_SHADOW` (la carte d'ombres, qui SURVIT). Un
# `grep -F` naif compte donc le survivant comme un residu et la porte devient INATTEIGNABLE : elle
# resterait rouge quoi qu'on supprime. Meme classe pour `u_pbr_mat` / `u_pbr_mat2`. On exige donc
# que le caractere qui SUIT le nom ne soit ni une lettre, ni un chiffre, ni un souligne.
# `grep -o` compte les OCCURRENCES, pas les lignes : un binaire n'a presque pas de sauts de ligne,
# et un compte par ligne y ecraserait vingt residus en un seul.
hits(){  # hits <fichier> <motif...>
  local f="$1"; shift
  local n=0 m c
  for m in "$@"; do
    c=$(grep -aoE -- "$m([^A-Za-z0-9_]|\$)" "$f" 2>/dev/null | grep -c .) || c=0
    n=$((n + c))
  done
  printf '%s' "$n"
}

# ── LES LISTES ────────────────────────────────────────────────────────────────────────────────
# Les 36 uniformes SUPPRIMES par l'essai 8 : les 32 de la pile de matiere, plus les 4 residus de
# l'etage PROFONDEUR DE SURFACE / PBR ISOLATE que les essais precedents avaient laisses declares.
REMOVED_UNIFORMS=(
  u_pbr_mode u_pbr_mat u_pbr_mat2 u_pbr_normal_strength u_pbr_normal_dc
  u_pbr_height_scale u_pbr_height_lambda u_pbr_height_stat u_pbr_spec_intensity
  u_pbr_ambient u_pbr_exposure u_pbr_direct u_pbr_indirect u_pbr_baked_weight
  u_pbr_emissive_str u_pbr_uv_tile u_pbr_uv_per_m u_pbr_light_dir u_pbr_light_color
  u_pbr_sun_dir u_pbr_sun_color u_pbr_world_relight u_pbr_wr_direct u_pbr_wr_indirect
  u_pbr_legacy_shadow tex_PBR_N tex_PBR_R tex_PBR_M tex_PBR_AO tex_PBR_H
  tex_PBR_S tex_PBR_E
  u_pbr_displacement u_pbr_bisect u_pbr_bisect2 u_pbr_tess_active
)
# Les 7 autres noms de `kLegacyUniformNames` : ils completent les 43 du recensement du moteur et
# ne servent qu'a la comparaison de derive ci-dessous.
OTHER_UNIFORMS=(
  u_rt_ambient_on u_rt_ambient_model u_rt_ambient_contrast u_rt_shadow_range
  u_rt_shadow_res u_rt_shadow_residual u_mm_flags
)
# Noms de fichiers et de symboles de la pile PBR. AUCUN n'est une chaine de `lighting_census.cpp`
# : un binaire propre doit donc rendre zero, et ce zero est atteignable.
BIN_SYMBOLS=(
  pbr_fused pbr_helpers pbr_uniforms PbrTestPattern PbrDrawBinder
  SHADE_HOST_LEGACY_PBR pbr_modern tfrag3_tess
)
# Les fichiers source qui doivent avoir QUITTE l'arbre.
SRC_FILES=(
  game/graphics/opengl_renderer/shaders/pbr_fused.glsl
  game/graphics/opengl_renderer/shaders/pbr_helpers.glsl
  game/graphics/opengl_renderer/shaders/pbr_uniforms.glsl
  game/graphics/opengl_renderer/loader/PbrTestPattern.h
  game/graphics/opengl_renderer/loader/PbrTestPattern.cpp
)

# ── 5. LES ARTEFACTS ET LEUR FRAICHEUR ────────────────────────────────────────────────────────
# Sans eux tout le reste est muet : un fichier absent ne peut pas rendre zero « parce que c'est
# propre ». Chaque absence AJOUTE au compte.
PENALTY=0
ARTIFACTS=0
mt(){  # mt <cle> <fichier>
  if [ -f "$2" ]; then
    ARTIFACTS=$((ARTIFACTS + 1))
    pub "lighting_legacy_artifact_$1_mtime" "$(date -u -r "$2" +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
    return 0
  fi
  pub "lighting_legacy_artifact_$1_mtime" "absent"
  note "artefact absent: $2"
  PENALTY=$((PENALTY + 1000))
  return 1
}
mt blob "$BLOB"; HAVE_BLOB=$?
mt so   "$SO";   HAVE_SO=$?
mt gk   "$GK";   HAVE_GK=$?
pub lighting_legacy_artifacts "$ARTIFACTS"

if [ "$ARTIFACTS" -eq 0 ]; then
  # Rien de mesurable du tout : c'est le SEUL cas d'erreur de sortie.
  pub lighting_legacy_sites 9001
  pub lighting_legacy_census_ran 0
  pub lighting_legacy_census_reason "aucun artefact lisible"
  exit 1
fi
pub lighting_legacy_census_ran 1

# ── 1. LE BLOB DE SHADERS ANDROID ─────────────────────────────────────────────────────────────
if [ "$HAVE_BLOB" -eq 0 ]; then
  BLOB_HITS=$(hits "$BLOB" "${REMOVED_UNIFORMS[@]}")
  BLOB_CTL=$(hits "$BLOB" u_rt_light_on u_pbr_shadow_on tex_PBR_SHADOW)
else
  BLOB_HITS=-1; BLOB_CTL=0
fi
pub lighting_legacy_blob_hits "$BLOB_HITS"
pub lighting_legacy_blob_control "$BLOB_CTL"
if [ "$BLOB_CTL" -eq 0 ]; then
  note "temoin blob a zero (u_rt_light_on/u_pbr_shadow_on/tex_PBR_SHADOW introuvables)"
  PENALTY=$((PENALTY + 1000))
fi

# ── 2. LES BINAIRES LIVRES ────────────────────────────────────────────────────────────────────
SO_HITS=0
[ "$HAVE_SO" -eq 0 ] && SO_HITS=$((SO_HITS + $(hits "$SO" "${BIN_SYMBOLS[@]}")))
[ "$HAVE_GK" -eq 0 ] && SO_HITS=$((SO_HITS + $(hits "$GK" "${BIN_SYMBOLS[@]}")))
pub lighting_legacy_so_hits "$SO_HITS"
# LE TEMOIN du binaire : deux modules qui RESTENT. S'ils ne repondent pas, le grep ne lit pas ce
# qu'il croit lire et le zero ci-dessus ne vaut rien.
SO_CTL=0
[ "$HAVE_SO" -eq 0 ] && SO_CTL=$(hits "$SO" lighting_census shade_proof)
pub lighting_legacy_so_control "$SO_CTL"
if [ "$SO_CTL" -eq 0 ]; then
  note "temoin libgk.so a zero (lighting_census/shade_proof introuvables)"
  PENALTY=$((PENALTY + 1000))
fi

# ── 3. LES FICHIERS SOURCE ENCORE DANS L'ARBRE ────────────────────────────────────────────────
SRC_LIVE=0
SRC_NAMES=""
for f in "${SRC_FILES[@]}"; do
  if [ -e "$f" ]; then
    SRC_LIVE=$((SRC_LIVE + 1))
    SRC_NAMES="${SRC_NAMES:+$SRC_NAMES,}$(basename "$f")"
  fi
done
pub lighting_legacy_src_files "$SRC_LIVE"
pub lighting_legacy_src_list "${SRC_NAMES:--}"

# ── 4. LES DEUX CMakeLists ────────────────────────────────────────────────────────────────────
# Les deux listes sont INDEPENDANTES : un fichier retire de l'une et laisse dans l'autre casse le
# lien arm64 ou ressuscite le module. On compte les lignes des deux.
BUILD_REFS=0
for cm in game/CMakeLists.txt android/CMakeLists.txt; do
  if [ -f "$cm" ]; then
    # Le RADICAL, pas le nom complet : `android/CMakeLists.txt` cite les chunks partages sans
    # leur extension (« pbr_uniforms / pbr_helpers / pbr_fused »). Une ligne qui nomme le fichier
    # sans le suffixe le nomme quand meme.
    for f in "${SRC_FILES[@]}"; do
      b=$(basename "$f"); b=${b%.*}
      c=$(grep -acF -- "$b" "$cm" 2>/dev/null) || c=0
      BUILD_REFS=$((BUILD_REFS + c))
    done
  else
    note "CMakeLists absent: $cm"
    PENALTY=$((PENALTY + 1000))
  fi
done
pub lighting_legacy_build_refs "$BUILD_REFS"

# ── 4bis. LE BANC DE TEXTE ────────────────────────────────────────────────────────────────────
# La lecon de l'essai 3 : un residu que PERSONNE ne cherche survit a une porte verte. Les
# libelles des rangees retirees ne sont ni des symboles GOAL ni des uniformes — ce sont des
# entrees d'ENUMERATION de `text-h.gc` et des chaines traduites. Aucune sonde du moteur ne peut
# les voir. Elles atterrissent dans les bancs `*COMMON.TXT` produits par goalc, et c'est la
# qu'on les lit. Seules des chaines DISTINCTIVES sont cherchees : « Displacement », « Low »,
# « Stock » vivent ailleurs dans le jeu et rendraient un faux rouge.
TXT_BANK="out/jak1/iso/0COMMON.TXT"
TXT_STRINGS=(
  "PBR Materials" "Texture Relief" "Specular Intensity" "Mesh Subdivision"
  "Advanced Materials" "Physical material lighting" "isolate normal/parallax"
)
if [ -f "$TXT_BANK" ]; then
  ARTIFACTS=$((ARTIFACTS + 1))
  pub lighting_legacy_artifact_txt_mtime "$(date -u -r "$TXT_BANK" +%Y%m%dT%H%M%SZ 2>/dev/null || echo unknown)"
  TXT_HITS=$(hits "$TXT_BANK" "${TXT_STRINGS[@]}")
  # Le temoin : deux libelles de rangees qui RESTENT dans le sous-menu. A zero, le banc n'est pas
  # celui qu'on croit lire et le zero ci-dessus ne prouve rien.
  TXT_CTL=$(hits "$TXT_BANK" "Ambient Occlusion" "AO Quality")
else
  pub lighting_legacy_artifact_txt_mtime "absent"
  note "banc de texte absent: $TXT_BANK"
  PENALTY=$((PENALTY + 1000))
  TXT_HITS=0; TXT_CTL=0
fi
pub lighting_legacy_txt_hits "$TXT_HITS"
pub lighting_legacy_txt_control "$TXT_CTL"
if [ "$TXT_CTL" -eq 0 ] && [ -f "$TXT_BANK" ]; then
  note "temoin du banc de texte a zero (Ambient Occlusion / AO Quality introuvables)"
  PENALTY=$((PENALTY + 1000))
fi

# ── 6. LA DERIVE ENTRE LA TABLE DU MOTEUR ET CELLE DE CE SCRIPT ───────────────────────────────
# Une table qui derive de son script est une porte qui MENT : le moteur chercherait des noms que
# le recensement d'artefact ignore, ou l'inverse. On relit `kLegacyUniformNames` dans la source et
# on compte les noms presents d'un seul cote.
DRIFT=$(
  {
    sed -n '/kLegacyUniformNames\[\] = {/,/^};/p' "$CENSUS_SRC" 2>/dev/null |
      grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"' | sort -u | sed 's/^/SRC /'
    printf '%s\n' "${REMOVED_UNIFORMS[@]}" "${OTHER_UNIFORMS[@]}" | sort -u | sed 's/^/SH /'
  } | awk '{c[$2]=c[$2] " " $1} END {n=0; for (k in c) if (c[k] !~ /SRC/ || c[k] !~ /SH/) n++; print n+0}'
)
case "$DRIFT" in ''|*[!0-9]*) DRIFT=9002; note "derive de table illisible" ;; esac
pub lighting_legacy_list_drift "$DRIFT"
# Le denominateur de la derive : combien de noms chaque cote porte. Un zero des deux cotes
# rendrait une derive nulle qui ne prouve rien.
SRC_N=$(sed -n '/kLegacyUniformNames\[\] = {/,/^};/p' "$CENSUS_SRC" 2>/dev/null |
        grep -coE '"[A-Za-z_][A-Za-z0-9_]*"')
pub lighting_legacy_list_src_names "${SRC_N:-0}"
pub lighting_legacy_list_sh_names "$(( ${#REMOVED_UNIFORMS[@]} + ${#OTHER_UNIFORMS[@]} ))"
if [ "${SRC_N:-0}" -eq 0 ]; then
  note "kLegacyUniformNames illisible dans $CENSUS_SRC"
  PENALTY=$((PENALTY + 1000))
fi

# ── 7. LA SOMME, ET SA POLARITE ───────────────────────────────────────────────────────────────
# La valeur du moteur se lit dans le journal BRUT de la course. Absente ou non numerique = la
# course n'a pas publie sa part : la porte doit etre ROUGE, jamais verte par silence.
ENG=""
if [ -n "$ENG_SNAP" ]; then
  # On lit l'INSTANTANE pris avant la premiere ecriture, jamais le journal vivant.
  # `ENG_LINES` publie le denominateur : zero ligne du moteur est un SILENCE, pas un zero.
  ENG_RAW=$(grep -ahE '^lighting_legacy_sites=[0-9]+$' "$ENG_SNAP" 2>/dev/null | tr -d '\r')
  ENG_LINES=$(printf '%s' "$ENG_RAW" | grep -c . )
  ENG=$(printf '%s\n' "$ENG_RAW" | tail -1 | sed 's/^lighting_legacy_sites=//')
  pub lighting_legacy_engine_lines "${ENG_LINES:-0}"
fi
case "$ENG" in
  ''|*[!0-9]*)
    pub lighting_legacy_engine_sites -1
    note "valeur moteur absente ou non numerique"
    pub lighting_legacy_sites 9001
    pub lighting_legacy_census_reason "${REASONS:--}"
    exit 0
    ;;
esac
pub lighting_legacy_engine_sites "$ENG"

BLOB_TERM=$BLOB_HITS
[ "$BLOB_TERM" -lt 0 ] && BLOB_TERM=0   # l'absence du blob est deja comptee en PENALTY
SITES=$((ENG + BLOB_TERM + SO_HITS + SRC_LIVE + BUILD_REFS + TXT_HITS + DRIFT + PENALTY))
pub lighting_legacy_sites "$SITES"
pub lighting_legacy_census_penalty "$PENALTY"
pub lighting_legacy_census_reason "${REASONS:--}"
exit 0
