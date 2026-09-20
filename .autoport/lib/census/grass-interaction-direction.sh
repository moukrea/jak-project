#!/usr/bin/env bash
# census/grass-interaction-direction.sh — LA PORTE DE L'HERBE QUI SE COUCHE DANS LE SENS DU PAS.
#
# CE QUE LA COURSE DE JEU NE PEUT PAS DIRE. La preuve est une course d'AMORCAGE : Jak apparait et
# ne marche pas. Aucune traversee, aucune caisse cassee, aucun fantome relache. Les deux grandeurs
# que le contrat exige — l'angle entre la flexion moyenne et la direction du deplacement, et
# l'ecart de flexion entre le centre du contact et ses bords — n'existent tout simplement pas dans
# une telle course. On les mesure donc HORS LIGNE, sur une traversee scriptee de huit caps.
#
# ET LA PORTE NE MESURE PAS UN MIROIR. L'outil ne recalcule pas la loi : il `#include` LE MEME
# FICHIER que le pilote compile (`shaders/grass_contact_dir.glsl`), derriere `glsl_compat.h`.
# Le MOTEUR publie l'empreinte du texte qu'il a REELLEMENT splice ; ce script la recalcule sur le
# fichier de l'arbre, donc un blob GLES d'Android en retard devient un defaut COMPTE. L'etat
# initial du hachage est celui de `Shader.cpp:162` — 1469598103934665603 et PAS la base du manuel :
# l'essai 1 de `grass-shading` a ete brule a crier « pack en retard » sur un blob conforme au bit.
#
# LE BRAS D'AVANT EST MESURE, PAS SUPPOSE. L'outil rejoue la MEME traversee avec `gcd_speed = 0`,
# c'est-a-dire la loi radiale que cet item remplace, sur les MEMES brins. C'est ce bras qui doit
# rendre une resultante quasi nulle et un biais avant/arriere nul : sans lui, dire « avant, c'etait
# un disque » serait une affirmation, pas une mesure.
#
# LES ACQUIS SONT REPETES, PAS ESPERES. Relevement amorti, pierres tombales, annulation a la casse
# d'une caisse, contact mobile epargne par une tombale statique : le moteur rejoue la machine a
# etats REELLE (memes fonctions, meme constantes, etat local) sur une sequence deterministe, et
# publie ce qu'il a mesure. C'est le seul moyen d'atteindre ces quatre chemins dans une course ou
# personne ne casse rien.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

ARMED=${AUTOPORT_CENSUS_ARMED:-1}
D=${AUTOPORT_CENSUS_DIR:-.autoport/reports/grass-interaction-direction}
ELOG="$D/proof-engine.log"
[ "$ARMED" = 0 ] && ELOG="$D/proof-off-engine.log"

T=$(mktemp -d "${TMPDIR:-/tmp}/grass-int.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT
die(){ printf 'census grass-interaction-direction: %s\n' "$*" >&2; exit 1; }

DEF=0
term(){ # term <nom> <valeur 0|1>
  printf 'grass_int_term_%s=%s\n' "$1" "$2"
  DEF=$((DEF + $2))
}

# =====================================================================================
# A. LA TRAVERSEE SCRIPTEE — termes 1 et 2 du contrat
# =====================================================================================
bash .autoport/lib/build_x86.sh --target grass_bake > "$T/build.log" 2>&1 \
  || die "build_x86.sh --target grass_bake a rendu $? (voir $T/build.log)"
BIN=build/tools/grass_bake/grass_bake
[ -x "$BIN" ] || die "$BIN absent apres la porte."

TOOL_RC=0
if [ -s out/jak1/fr3/training.fr3 ]; then
  "$BIN" training --preset medium --interaction-census > "$T/tool.out" 2> "$T/tool.err" || TOOL_RC=$?
else
  TOOL_RC=66
fi
echo "grass_int_tool_rc=$TOOL_RC"
grep '^intx_' "$T/tool.out" > "$T/tool.kv" 2>/dev/null
cat "$T/tool.kv" 2>/dev/null
cat "$T/tool.err" >&2 2>/dev/null

kv(){ # $1 = cle intx_* ; rend la valeur ou la chaine vide
  awk -F= -v k="$1" '$1==k{v=$2} END{printf "%s", v}' "$T/tool.kv" 2>/dev/null
}
# comparaison flottante par python : `[ ]` ne sait pas lire 0.37514
fcmp(){ python3 -c "
import sys
a,op,b=sys.argv[1],sys.argv[2],sys.argv[3]
try: a=float(a); b=float(b)
except ValueError: sys.exit(2)          # une valeur absente n'est pas 'vraie', elle est MUETTE
ok={'lt':a<b,'gt':a>b,'le':a<=b,'ge':a>=b}[op]
sys.exit(0 if ok else 1)" "$1" "$2" "$3"; }
bad(){ # bad <nom> <a> <op> <b> : defaut si la comparaison est VRAIE, defaut aussi si MUET (rc 2)
  fcmp "$2" "$3" "$4"; local r=$?
  if [ "$r" = 0 ]; then term "$1" 1; elif [ "$r" = 1 ]; then term "$1" 0; else term "$1" 1; fi
}

if [ "$TOOL_RC" != 0 ]; then
  term tool_failed 1
else
  term tool_failed 0
  # --- population : un zero sur une population vide serait vert et MUET
  bad blades_empty      "$(kv intx_blades_total)"    le 0
  bad steps_unmeasured  "$(kv intx_steps_measured)"  le 0
  bad contacts_empty    "$(kv intx_contacts_total)"  le 0
  bad terms_unmeasured  "$(kv intx_terms_measured)"  lt 5
  bad lat_center_empty  "$(kv intx_lat_center_n)"    le 0
  bad lat_edge_empty    "$(kv intx_lat_edge_n)"      le 0
  bad angle_all_undef   "$(kv intx_angle_undefined)" ge "$(kv intx_steps_measured)"
  # --- TERME 1 : LA FLEXION SUIT LE MOUVEMENT
  bad angle_over_cap    "$(kv intx_angle_mean_deg)"  gt "$(kv intx_angle_cap_deg)"
  bad angle_max_sideways "$(kv intx_angle_max_deg)"  gt 90
  bad resultant_short   "$(kv intx_resultant)"       lt "$(kv intx_resultant_floor)"
  bad s_bias_short      "$(kv intx_s_bias)"          lt "$(kv intx_s_bias_floor)"
  # le bras d'avant, MESURE : il doit etre rond (resultante et biais quasi nuls)
  RATIO_MIN=$(python3 -c "print(float('$(kv intx_off_resultant)') * float('$(kv intx_resultant_ratio)'))" 2>/dev/null || echo "")
  bad resultant_ratio_short "$(kv intx_resultant)"   lt "$RATIO_MIN"
  bad radial_arm_not_round  "$(python3 -c "print(abs(float('$(kv intx_off_s_bias)')))" 2>/dev/null || echo "")" \
                            gt "$(kv intx_radial_aniso_tol)"
  # --- TERME 2 : LE DEGAGEMENT LATERAL EXISTE
  # La grandeur litterale du contrat, gardee...
  bad lat_delta_short   "$(kv intx_lat_delta)"       lt "$(kv intx_lat_delta_floor)"
  # ...mais elle ne DISCRIMINE PAS : mesuree sur la loi radiale que cet item remplace, elle rend
  # 0,498 contre 0,518. Une porte verte sous les DEUX regimes ne mesure rien. On exige donc qu'elle
  # depasse celle du bras d'avant, et surtout on lit la grandeur APPARIEE ci-dessous.
  bad lat_delta_not_better "$(kv intx_lat_delta)"    le "$(kv intx_off_lat_delta)"
  # L'ECART AU DISQUE, BRIN A BRIN. Sous la loi radiale les deux poussees sont LA MEME FONCTION,
  # donc cet ecart vaut exactement zero : c'est le « ecart nul = on ecrase encore en rond » du
  # contrat, pris au mot. Son controle n'est pas une tolerance, c'est une identite.
  bad lat_excess_short  "$(kv intx_lat_excess_delta)" lt "$(kv intx_lat_excess_floor)"
  bad radial_pairing_broken "$(python3 -c "print(abs(float('$(kv intx_off_lat_excess_delta)')))" 2>/dev/null || echo "")" \
                            gt 0.000001
  bad paired_empty      "$(kv intx_paired_blades)"        le 0
  bad excess_center_empty "$(kv intx_lat_excess_center_n)" le 0
  bad excess_edge_empty "$(kv intx_lat_excess_edge_n)"    le 0
fi

# =====================================================================================
# B. LE MODELE QUE LE PILOTE A COMPILE EST-IL CELUI DE L'ARBRE ?
# =====================================================================================
BASE_MOTEUR=1469598103934665603    # Shader.cpp:162 — l'etat initial que le moteur utilise VRAIMENT
BASE_MANUEL=14695981039346656037   # la base FNV-1a du manuel — diagnostic, jamais la comparaison
fnv(){ python3 - "$1" "$2" <<'PY'
import sys
h = int(sys.argv[2])
for b in open(sys.argv[1], 'rb').read():
    h = ((h ^ b) * 0x100000001b3) & 0xffffffffffffffff
print(h)
PY
}
CHUNK=game/graphics/opengl_renderer/shaders/grass_contact_dir.glsl
TREE_FNV=$(fnv "$CHUNK" "$BASE_MOTEUR" 2>/dev/null || echo -1)
TREE_FNV_STD=$(fnv "$CHUNK" "$BASE_MANUEL" 2>/dev/null || echo -1)
echo "grass_int_tree_contact_fnv=$TREE_FNV"
echo "grass_int_tree_contact_fnv_std=$TREE_FNV_STD"
echo "grass_int_fnv_basis=$BASE_MOTEUR"

eng(){ # $1 = cle publiee par le moteur ; rend -1 si absente
  local v=""
  [ -s "$ELOG" ] && v=$(grep -ao "$1=[0-9]\+" "$ELOG" 2>/dev/null | tail -1 | cut -d= -f2)
  printf '%s' "${v:--1}"
}
echo "grass_int_engine_log=${ELOG:--}"

E_FNV=$(eng grass_int_contact_fnv)
echo "grass_int_engine_contact_fnv_seen=$E_FNV"
T1=1; [ "$E_FNV" = "$TREE_FNV" ] && T1=0
term model_stale "$T1"
WHY=aucune
if [ "$T1" != 0 ]; then
  if [ "$E_FNV" = "-1" ]; then WHY=moteur-muet
  elif [ "$E_FNV" = "$TREE_FNV_STD" ]; then WHY=base-de-hachage-divergente
  else WHY=pack-gles-en-retard; fi
fi
echo "grass_int_model_stale_why=$WHY"

# =====================================================================================
# C. TERME 4 — AUCUNE LECTURE DE TABLEAU D'UNIFORMES A INDEX DYNAMIQUE (sur l'APPAREIL)
# =====================================================================================
E_DYN=$(eng grass_int_dyn_index_reads)
E_DYNP=$(eng grass_int_dyn_index_reads_preproc)
E_READS=$(eng grass_int_index_reads)
E_MACRO=$(eng grass_int_macros_expanded)
E_SCAN=$(eng grass_int_shaders_scanned)
E_ARRAYS=$(eng grass_int_uniform_arrays)
for k in dyn_index_reads dyn_index_reads_preproc index_reads macros_expanded shaders_scanned uniform_arrays; do
  printf 'grass_int_seen_%s=%s\n' "$k" "$(eng grass_int_$k)"
done
term dyn_index_reads        "$([ "$E_DYN" = 0 ] && echo 0 || echo 1)"
# LES TROIS DENOMINATEURS. Un zero de lectures dynamiques ne vaut que si le scanner a VU quelque
# chose : sans eux, un scanner qui n'a jamais tourne rendrait le meme zero triomphal.
term scan_blind_shaders     "$([ "$E_SCAN" != -1 ] && [ "$E_SCAN" -ge 2 ] 2>/dev/null && echo 0 || echo 1)"
term scan_blind_reads       "$([ "$E_READS" != -1 ] && [ "$E_READS" -gt 0 ] 2>/dev/null && echo 0 || echo 1)"
term scan_blind_macros      "$([ "$E_MACRO" != -1 ] && [ "$E_MACRO" -gt 0 ] 2>/dev/null && echo 0 || echo 1)"
term scan_blind_arrays      "$([ "$E_ARRAYS" != -1 ] && [ "$E_ARRAYS" -gt 0 ] 2>/dev/null && echo 0 || echo 1)"

# =====================================================================================
# D. TERME 3 — LES QUATRE ACQUIS, REPETES SUR L'APPAREIL
# =====================================================================================
for k in reh_ran reh_capped reh_terms_measured reh_ease_in_frames reh_ease_out_frames \
         reh_ease_out_max_step_milli reh_ease_monotonic reh_tomb_bans reh_tomb_ban_at_7900ms \
         reh_tomb_free_at_8050ms reh_break_tombstones reh_break_ease_frames \
         reh_break_first_drop_milli reh_static_banned reh_moving_survives \
         reh_dir_err_deg reh_dir_speed_milli reh_dir_unit_milli \
         engine_cull_entries engine_tramp_entries engine_class_overlap \
         engine_dir_uloc_ok engine_tier engine_dir_enabled engine_dir_frames \
         engine_dir_speed_max_milli engine_dir_unit_milli engine_hits; do
  printf 'grass_int_seen_%s=%s\n' "$k" "$(eng grass_int_$k)"
done
# Trois comparateurs, et leur sens est dans leur NOM : une porte dont le garde est inverse est
# verte sur le defaut qu'elle cherche. `-1` = le moteur n'a rien publie = MUET = defaut, jamais 0.
eq(){ # defaut si la cle differe de la valeur attendue
  local v; v=$(eng "grass_int_$2")
  term "$1" "$([ "$v" = "$3" ] && echo 0 || echo 1)"
}
atmost(){ # defaut si la cle DEPASSE le plafond
  local v; v=$(eng "grass_int_$2")
  term "$1" "$([ "$v" != -1 ] && [ "$v" -le "$3" ] 2>/dev/null && echo 0 || echo 1)"; }
atleast(){ # defaut si la cle est SOUS le plancher
  local v; v=$(eng "grass_int_$2")
  term "$1" "$([ "$v" != -1 ] && [ "$v" -ge "$3" ] 2>/dev/null && echo 0 || echo 1)"; }

eq acquis_rehearsal_absent  reh_ran 1
eq acquis_rehearsal_capped  reh_capped 0
atleast acquis_terms_unmeasured reh_terms_measured 7   # 7 phases : moins de 7 = une phase MUETTE
# relevement amorti : 0,25 s de montee et 0,6 s de descente a 60 img/s, et AUCUN a-coup
eq acquis_ease_in           reh_ease_in_frames 15
eq acquis_ease_out          reh_ease_out_frames 36
eq acquis_ease_monotonic    reh_ease_monotonic 1
atmost acquis_ease_snap     reh_ease_out_max_step_milli 60
# pierres tombales : 8 s, mesurees des DEUX cotes de la frontiere
eq acquis_tomb_bans         reh_tomb_bans 5
eq acquis_tomb_ban_before   reh_tomb_ban_at_7900ms 1
eq acquis_tomb_free_after   reh_tomb_free_at_8050ms 1
# annulation a la casse d'une caisse : tombale posee, et relevement amorti et non instantane
eq acquis_break_tombstone   reh_break_tombstones 1
eq acquis_break_ease        reh_break_ease_frames 36
atmost acquis_break_snap    reh_break_first_drop_milli 60
# acteurs caches contre acteurs aplatis : une tombale statique n'atteint pas un contact mobile
eq acquis_static_banned     reh_static_banned 1
eq acquis_moving_survives   reh_moving_survives 1
# et, sur la course vivante, les deux familles restent disjointes
eq acquis_class_overlap     engine_class_overlap 0
# le cap derive sur l'appareil suit bien la marche scriptee, et il est UNITAIRE
atmost acquis_dir_err       reh_dir_err_deg 5
eq acquis_dir_unit          reh_dir_unit_milli 1000

# =====================================================================================
# E. LE MOTEUR A-T-IL SEULEMENT ARME LA LOI ? (bras desarme : l'absence est le resultat ATTENDU)
# =====================================================================================
eq uniform_stripped         engine_dir_uloc_ok 1     # -1 en localisation = ecriture no-op SILENCIEUSE
if [ "$ARMED" != 0 ]; then
  eq engine_not_armed       engine_dir_enabled 1
  atleast engine_tier_too_low engine_tier 2          # 2 = medium : sous ce palier, repli radial
else
  # DESARME, L'ABSENCE EST LE RESULTAT ATTENDU — et c'est un verdict d'EFFET, pas une inaction :
  # la loi doit etre eteinte, et la ligne FEATURE doit rendre hits=0.
  eq engine_still_armed     engine_dir_enabled 0
fi

# =====================================================================================
# LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, tous publies un par un.
# =====================================================================================
echo "grass_int_terms=$DEF"
echo "grass_interaction_defects=$DEF"
exit 0
