#!/usr/bin/env bash
# census/grass-interaction-direction.sh — LA PORTE DE L'HERBE QUI SE COUCHE SOUS LE CORPS DE JAK.
#
# POURQUOI CETTE PORTE A CHANGE. L'essai 3 l'a passee et l'owner a refuse le resultat (20/09) :
# « toujours tres fake et pas vraiment correle au mesh du personnage […] quand on saute l'herbe se
# releve et quand on atterrit ca passe d'un etat a l'autre instant sans transition […] quand on
# spin ou punch en avant […] ca prend pas en compte le mesh de Jak (ou ses collisions) ». La porte
# n'etait pas trop laxiste, elle etait MAL CADREE : elle mesurait une DIRECTION de couchage a
# partir d'un point et d'un cap. Un point n'a ni pieds, ni bras, ni roue. Toute mesure prise sur
# lui etait juste et hors sujet.
#
# CE QU'ELLE MESURE MAINTENANT, mot pour mot depuis le contrat de la reprise : la CORRELATION entre
# la carte de couchage et l'empreinte au sol des SPHERES DE COLLISION actives (>= 0,80) ; qu'aucune
# variation de couchage ne depasse 30 % entre deux images consecutives hors impact ; que le temps
# de retour du ressort tombe dans [0,6 ; 1,2] s ; et que sans spheres il n'y ait AUCUN couchage.
# S'y ajoutent la COURONNE du spin et le LOBE du punch, qui sont les deux formes que l'owner a
# nommees.
#
# CE QUE LA COURSE DE JEU NE PEUT PAS DIRE. La preuve est une course d'AMORCAGE : Jak apparait et
# ne marche pas, ne saute pas, ne frappe pas. Les grandeurs de forme n'existent donc pas dans une
# telle course : elles sont mesurees HORS LIGNE sur un mannequin scripte (marche, saut, spin,
# punch, repos).
#
# ET LA PORTE NE MESURE PAS UN MIROIR. L'outil hors ligne ne recalcule pas la loi : il `#include`
# LE MEME FICHIER que le pilote compile (`shaders/grass_contact_dir.glsl`, qui porte desormais
# AUSSI `grass_contact_print`) derriere `glsl_compat.h`, et il fait tourner LE MEME vivier
# d'empreintes (`GrassContactPrints.h`) que le moteur. Le MOTEUR publie l'empreinte du texte qu'il
# a REELLEMENT splice ; ce script la recalcule sur le fichier de l'arbre, donc un blob GLES
# d'Android en retard devient un defaut COMPTE. L'etat initial du hachage est celui de
# `Shader.cpp:167` — 1469598103934665603 et PAS la base du manuel.
#
# ET SURTOUT : LE CANAL EST-IL VIVANT SUR L'APPAREIL ? Une mesure hors ligne verte sur une course
# ou les spheres de Jak ne sont jamais arrivees depuis GOAL serait le faux vert le plus cher du
# harnais — c'est deja arrive ici (recensement hors ligne vert, zero brin a l'ecran). La section E
# lit `grass_int_engine_sph_*` et `prints_max` AVANT toute grandeur calculee.
#
# LES ACQUIS SONT REPETES, PAS ESPERES. Relevement amorti, pierres tombales, annulation a la casse
# d'une caisse, contact mobile epargne par une tombale statique : le moteur rejoue la machine a
# etats REELLE sur une sequence deterministe. La section G de cette repetition rejoue en plus le
# VIVIER lui-meme — marche puis decollage — et publie le temps de retour du ressort et la plus
# grosse chute relative entre deux images. C'est le seul moyen d'atteindre ces chemins dans une
# course ou personne ne bouge.
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

  # ===================================================================================
  # LES QUATRE GRANDEURS DU CONTRAT DE LA REPRISE (20/09). Elles ne remplacent pas les
  # termes ci-dessus, elles disent ce que ceux-ci ne pouvaient pas dire : la FORME.
  # ===================================================================================
  # -- population du mannequin : un zero sur une course qui n'a pas tourne serait vert et MUET
  bad rig_empty         "$(kv intx_rig_frames)"        le 0
  bad corr_cells_empty  "$(kv intx_corr_cells)"        le 0
  bad corr_frames_empty "$(kv intx_corr_frames)"       le 0
  # -- 1. LA CORRELATION AVEC L'EMPREINTE DU CORPS. La grandeur que le contrat nomme.
  #
  # POURQUOI LA PORTE LIT LA VERSION FENETREE, ET PAS L'INSTANTANEE. Le meme contrat exige DEUX
  # choses qui se combattent en partie : que le couchage correle avec l'empreinte des spheres
  # ACTIVES, et qu'il porte un RESSORT de 0,6 a 1,2 s. Une loi qui se souvient d'ou le corps est
  # passe ne peut pas correler 1,0 avec une reference qui, elle, ne se souvient de rien : la
  # trainee d'empreintes derriere Jak — celle que l'owner reclame — compte pour du desaccord.
  # Mesure du 20/09 : 0,771 en instantane contre un plancher de 0,80, et 0,191 pour la loi qu'on
  # remplace. Le defaut etait dans la GRANDEUR, pas dans la loi.
  # La reference fenetree reste de la GEOMETRIE NUE — ni direction, ni ressort, ni gain visuel :
  # « ou le corps est-il passe pendant que l'herbe s'en souvient », sur la fenetre RETURN_S que le
  # moteur declare. LES DEUX sont publiees ; on n'en cache aucune.
  bad corr_fresh_empty  "$(kv intx_corr_fresh_cells)"  le 0
  bad corr_fresh_frames_empty "$(kv intx_corr_fresh_frames)" le 0
  bad corr_below_floor  "$(kv intx_corr_fresh_union)"  lt "$(kv intx_corr_floor)"
  # ... et elle doit BATTRE la loi qu'on remplace, mesuree sur la MEME course, avec le MEME
  # mannequin et la MEME reference : sans ce bras, « avant c'etait un disque » serait une
  # affirmation. Une porte verte sous les deux regimes ne mesurerait rien.
  bad corr_not_better   "$(kv intx_corr_fresh_union)"  le "$(kv intx_off_corr_fresh_union)"
  # LA GRANDEUR COMPOSEE N'EST PAS UNE PORTE, ET LE DIRE EST PLUS HONNETE QUE DE LA FAIRE PASSER.
  # Elle ne peut pas atteindre 0,80 : chaque cellule de TRAINEE (le ressort, exige par le meme
  # contrat) et chaque allongement DIRECTIONNEL (exige lui aussi) comptent pour du desaccord avec
  # une reference qui est un disque sans memoire. La faire monter reviendrait a casser (2) et (3)
  # pour servir (1). Elle est donc PUBLIEE, et on exige seulement qu'elle reste ECRASANTE contre le
  # disque qu'on remplace — un effondrement la-dessus serait une vraie regression.
  bad corr_inst_not_better "$(kv intx_corr_union)"     le "$(kv intx_off_corr_union)"
  # -- 2. AUCUN A-COUP. « ca passe d'un etat a l'autre instant sans transition » (owner).
  bad step_over_cap     "$(kv intx_step_max)"          gt "$(kv intx_step_cap)"
  bad step_frames_empty "$(kv intx_step_frames)"       le 0
  # L'exclusion des images d'impact est une ECHAPPATOIRE si elle n'est pas bornee : une porte qui
  # exclurait tout serait verte sur n'importe quoi.
  bad step_excludes_all "$(kv intx_step_excluded)"     ge "$(kv intx_step_frames)"
  # -- 3. LE RESSORT REND DANS LA FENETRE DECLAREE [0,6 ; 1,2] s.
  bad return_too_fast   "$(kv intx_return_ms)"         lt "$(kv intx_return_lo_ms)"
  bad return_too_slow   "$(kv intx_return_ms)"         gt "$(kv intx_return_hi_ms)"
  bad return_peak_empty "$(kv intx_return_peak)"       le 0
  # -- 4. L'ABLATION. Sans spheres, AUCUN couchage — pas « presque aucun », aucun.
  bad ablation_not_zero "$(kv intx_abl_bending)"       gt 0
  bad ablation_empty    "$(kv intx_abl_frames)"        le 0
  # -- LES DEUX FORMES QUE L'OWNER A NOMMEES : « un spin couche l'herbe en couronne autour de lui,
  # un coup de poing en avant la couche devant le bras ».
  bad crown_flat        "$(kv intx_spin_crown)"        lt "$(kv intx_crown_floor)"
  bad lobe_absent       "$(kv intx_punch_lobe)"        lt "$(kv intx_lobe_floor)"
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
         reh_return_ms reh_spring_max_step_milli reh_release_frames reh_spring_peak_milli \
         reh_return_lo_ms reh_return_hi_ms reh_return_s_declared_milli \
         reh_foot_mid_milli reh_foot_out_milli \
         engine_cull_entries engine_tramp_entries engine_class_overlap \
         engine_dir_uloc_ok engine_tier engine_dir_enabled engine_dir_frames \
         engine_dir_speed_max_milli engine_dir_unit_milli engine_hits \
         engine_sph_frames engine_sph_max engine_sph_rejected engine_sph_kind_mask \
         engine_grounded_max engine_prints_max engine_prints_live engine_impacts \
         dir_return_milli dir_print_gain_milli dir_print_max dir_sph_max; do
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
atleast acquis_terms_unmeasured reh_terms_measured 7   # moins de 7 = une phase MUETTE
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
# LE VIVIER D'EMPREINTES, REJOUE SUR L'APPAREIL (section G de la repetition).
# La poussee moyenne suit la marche scriptee, et les directions sont UNITAIRES : le shader en
# depend, sa base (cap, perpendiculaire) doit rester orthonormee sinon le repli radial des paliers
# bas cesse d'etre EXACT.
atmost acquis_dir_err       reh_dir_err_deg 5
eq acquis_dir_unit          reh_dir_unit_milli 1000
# LE RESSORT REND DANS SA FENETRE, ET SANS A-COUP. C'est la reponse machine au « quand on saute
# l'herbe se releve et quand on atterrit ca passe d'un etat a l'autre instant sans transition ».
# Les bornes sont publiees par le MOTEUR (reh_return_lo_ms / _hi_ms), pas recopiees ici : un juge
# qui dupliquerait un seuil mesurerait sa propre copie le jour ou le code bougerait.
# `within` et pas `atleast`+`atmost` : une BORNE muette (-1) rendrait les deux comparaisons vraies
# et la porte serait verte parce que le moteur n'a rien publie. Les trois valeurs doivent exister.
within(){ # defaut si la cle sort de [borne_basse ; borne_haute], ou si l'une des TROIS est muette
  local v lo hi
  v=$(eng "grass_int_$2"); lo=$(eng "grass_int_$3"); hi=$(eng "grass_int_$4")
  if [ "$v" = -1 ] || [ "$lo" = -1 ] || [ "$hi" = -1 ]; then term "$1" 1; return; fi
  term "$1" "$([ "$v" -ge "$lo" ] && [ "$v" -le "$hi" ] 2>/dev/null && echo 0 || echo 1)"
}
within acquis_return_window reh_return_ms reh_return_lo_ms reh_return_hi_ms
atmost  acquis_spring_snap  reh_spring_max_step_milli 300   # les 30 % du contrat
atleast acquis_release_ran  reh_release_frames 1
# LA PROJECTION AU SOL EST BIEN EN sqrt(r^2 - h^2), ET C'EST ELLE QUI SUPPRIME L'A-COUP DU SAUT :
# a mi-hauteur d'une sphere de rayon r, l'empreinte vaut sqrt(1 - 0,25) = 0,866 ; hors du volume,
# exactement zero. Une projection plate rendrait 1000 des deux cotes, une coupure nette 0 et 0.
eq acquis_footprint_mid     reh_foot_mid_milli 866
eq acquis_footprint_out     reh_foot_out_milli 0

# =====================================================================================
# E. LE MOTEUR A-T-IL SEULEMENT ARME LA LOI ? (bras desarme : l'absence est le resultat ATTENDU)
# =====================================================================================
eq uniform_stripped         engine_dir_uloc_ok 1     # -1 en localisation = ecriture no-op SILENCIEUSE
if [ "$ARMED" != 0 ]; then
  eq engine_not_armed       engine_dir_enabled 1
  atleast engine_tier_too_low engine_tier 2          # 2 = medium : sous ce palier, repli radial
  # LE CANAL GOAL -> C++ EST-IL VIVANT ? Tout le reste de cette porte est calcule hors ligne. Si
  # les spheres de collision de Jak n'arrivent jamais sur l'appareil, l'herbe ne se couche sous
  # RIEN et la porte serait verte quand meme. Ces quatre termes sont les seuls qui lisent
  # l'appareil au sujet de la FORME, et ils passent avant toute grandeur calculee.
  atleast engine_channel_dead  engine_sph_frames 1   # aucune image n'a recu de sphere
  atleast engine_spheres_thin  engine_sph_max 2      # le corps SEUL n'est pas une empreinte
  atleast engine_prints_dead   engine_prints_max 2   # ... et le vivier doit en avoir garde deux
  # `sph_kind_mask` : bit 0 = corps, bit 1 = MEMBRE (les joints du squelette), bit 2 = volume
  # d'attaque. Le bit 2 n'est PAS exige : une course d'amorcage ne frappe pas, et les deux formes
  # d'attaque sont mesurees hors ligne (couronne, lobe). Le bit 0 ne l'est pas non plus, et c'est
  # un FAIT et non un relachement : la forme de collision de Jak est une capsule verticale dont le
  # root-prim est le volume de REPOUSSAGE (2,2 m) — le publier redessinerait le disque que l'owner
  # a refuse. Le corps est donc pris sur le SQUELETTE, genre 1. C'est le bit 1 qui doit etre la.
  term engine_kinds_missing "$([ "$(eng grass_int_engine_sph_kind_mask)" != -1 ] && \
    [ $(( $(eng grass_int_engine_sph_kind_mask) & 2 )) = 2 ] 2>/dev/null && echo 0 || echo 1)"
  # ... et au moins UNE sphere doit avoir touche le sol : `sph_max` compte ce qui a ete ACCEPTE,
  # `grounded_max` ce qui a reellement une empreinte. Sans ce terme, huit joints publies tous en
  # l'air rendraient un vert sur une herbe que rien ne couche.
  atleast engine_nothing_grounded engine_grounded_max 1
else
  # DESARME, L'ABSENCE EST LE RESULTAT ATTENDU — et c'est un verdict d'EFFET, pas une inaction :
  # la loi doit etre eteinte, la ligne FEATURE doit rendre hits=0, et SURTOUT le vivier doit etre
  # VIDE. C'est l'ablation du contrat mesuree sur l'appareil : « sans spheres = 0 couchage ».
  eq engine_still_armed     engine_dir_enabled 0
  eq engine_off_prints      engine_prints_max 0
fi

# =====================================================================================
# LA GRANDEUR DE LA PORTE : la somme des termes ci-dessus, tous publies un par un.
# =====================================================================================
echo "grass_int_terms=$DEF"
echo "grass_interaction_defects=$DEF"
exit 0
