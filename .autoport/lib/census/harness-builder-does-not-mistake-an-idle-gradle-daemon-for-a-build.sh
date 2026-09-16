#!/usr/bin/env bash
# census/harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build.sh — LE VERDICT.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il n'ecrit aucun champ de `proof.txt` : sa sortie `cle=valeur` rejoint celle du moteur dans le
# meme journal, moissonnee par la meme regle. Une valeur VIDE ou qui porte un ESPACE est perdue
# par cette regle : tout passe par `pub`, qui colle les espaces.
#
# LES QUATRE POINTS DU LIVRABLE, chacun avec son terme :
#   1. LE COUT D'AVANT EST CHIFFRE   -> lib/builder_silence_cost.py, sur le journal du
#      constructeur. Le plus long silence qui couvre un commit livrable, et le nombre de tours
#      passes sans un mot. NON NULS : « je n'ai rien trouve » ne demontre pas l'absence de
#      defaut, il demontre que l'instrument n'a rien vu.
#   2. UN DEMON GRADLE INACTIF N'EST PAS UN BUILD -> lib/builder_guard_selftest.sh, qui fait
#      naitre de VRAIS processus et execute la VRAIE garde decoupee du fichier livre.
#   3. AUCUN TICK MUET               -> lib/builder_mute_census.py, sur le texte de la boucle :
#      la propriete est verifiee sur les 100 % des sorties, pas sur celles qu'une course emprunte.
#   4. LE TEMOIN A DEUX BRAS         -> les deux decisions du banc, cote a cote, sur le MEME
#      demon inactif : la garde livree autorise le build, l'ancienne regle fait `continue` et
#      tue la patience de 20 min.
#
# POLARITE : INCONNU = DEFAUT. Chaque temoin manquant, muet ou degenere AJOUTE au compte. Sans
# cela, une porte `== 0` sur un nettoyage serait verte par INACTION.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "builder_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1
ID="${AUTOPORT_CENSUS_ID:-harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build}"
ARMED="${AUTOPORT_CENSUS_ARMED:-1}"
D="${AUTOPORT_CENSUS_DIR:-$AP/reports/$ID}"
REG="$AP/logs/builder-ticks.tsv"

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr ' \t\n' '___')"; }
penalite=0; pourquoi=""
faute(){ penalite=$((penalite+1)); pourquoi="${pourquoi:+$pourquoi+}$1"; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0` sans rien avoir mesure.
n(){ local v=${1:-}; case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

# ================================================== 1. LE COUT D'AVANT, DANS LE JOURNAL =======
COUT=$(python3 "$AP/lib/builder_silence_cost.py" 2>/dev/null) || COUT=""
c(){ printf '%s\n' "$COUT" | sed -n "s/^$1=//p" | tail -1; }
C_OCTETS=$(n "$(c cost_log_bytes)")
C_TICKS=$(n "$(c cost_ticks_total)")
C_DERNIER=$(n "$(c cost_last_silence_s)")
C_PIRE=$(n "$(c cost_max_silence_s)")
C_COMMITS=$(n "$(c cost_max_silence_pending_commits)")
C_MUETS=$(n "$(c cost_max_silence_mute_ticks)")
C_LONGS=$(n "$(c cost_silences_over_7h)")
C_WIP=$(n "$(c cost_wip_motif_identique)")
t_cout=0
[ -n "$COUT" ] || { t_cout=$((t_cout+1)); faute instrument-de-cout-muet; }
[ "$C_OCTETS" -ge 1000000 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute journal-trop-maigre; }
[ "$C_TICKS" -ge 100 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute trop-peu-de-ticks-lus; }
# LE CHIFFRE QUE LE LIVRABLE NOMME : « le plus LONG silence ... >= 7 h le 16/09 ». C'est le PIRE
# qui est juge, jamais le plus RECENT : le plus recent retrecit des que le correctif tourne, et
# une porte posee dessus rougirait le jour ou le defaut disparait. Mesure : apres le redemarrage
# du constructeur sur le code corrige, le dernier silence est tombe a 790 s — et la porte, posee
# sur lui, a rendu 2 alors que rien n'avait cede.
[ "$C_PIRE" -ge 25200 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute pire-silence-sous-7h; }
[ "$C_LONGS" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute aucun-episode-de-sept-heures; }
[ "$C_PIRE" -ge "$C_DERNIER" ] 2>/dev/null || { t_cout=$((t_cout+1)); faute pire-silence-incoherent; }
[ "$C_COMMITS" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute aucun-commit-livrable-en-attente; }
[ "$C_MUETS" -ge 1 ] 2>/dev/null || { t_cout=$((t_cout+1)); faute aucun-tick-muet-compte; }
# Le litteral WIP de l'instrument est-il TOUJOURS celui du script juge ? Une divergence
# gonflerait le cout en prenant des checkpoints pour des livraisons.
[ "$C_WIP" = 1 ] || { t_cout=$((t_cout+1)); faute motif-wip-derive; }

# ========================================= 2 et 4. LA GARDE, ET SES DEUX BRAS =================
ST=$(bash "$AP/lib/builder_guard_selftest.sh" 2>/dev/null); ST_RC=$?
s(){ printf '%s\n' "$ST" | sed -n "s/^$1=//p" | tail -1; }
t_garde=0
[ "$ST_RC" = 0 ] || { t_garde=$((t_garde+1)); faute "banc-rc$ST_RC"; }
[ "$(n "$(s bgb_selftest_ran)")" = 1 ] || { t_garde=$((t_garde+1)); faute banc-muet; }
JAMBES=$(n "$(s bgb_legs_failed)")
if [ "$JAMBES" -ge 0 ] 2>/dev/null; then t_garde=$((t_garde + JAMBES))
else t_garde=$((t_garde+1)); faute jambes-non-comptees; fi
# LES TROIS CLASSEMENTS QUI PORTENT TOUT, relus un par un : un total a zero ne dit pas QUI a tenu.
[ "$(s bgb_demon_idle_neuve)"    = "busy=0,hard=0,idle=1" ] || { t_garde=$((t_garde+1)); faute demon-inactif-mal-classe; }
[ "$(s bgb_gradle_client_neuve)" = "busy=1,hard=1,idle=0" ] || { t_garde=$((t_garde+1)); faute client-gradle-mal-classe; }
[ "$(s bgb_demon_actif_neuve)"   = "busy=1,hard=1,idle=0" ] || { t_garde=$((t_garde+1)); faute demon-actif-mal-classe; }
# LES DEUX BRAS, SUR LE MEME DEMON INACTIF. Sans eux, « les deux bras au vert » serait vrai aussi
# le jour ou la condition testee n'existe plus, et l'ablation ne mesurerait rien.
[ "$(s bgb_livre_decision)" = "build-autorise" ]      || { t_garde=$((t_garde+1)); faute bras-livre-ne-batit-pas; }
[ "$(s bgb_off_decision)"   = "continue-sans-build" ] || { t_garde=$((t_garde+1)); faute bras-off-ne-bloque-plus; }
[ "$(n "$(s bgb_off_patience_morte)")" = 1 ]          || { t_garde=$((t_garde+1)); faute patience-toujours-vivante-sous-l-ancienne-regle; }
[ "$(n "$(s bgb_vieille_regle_bloque_a_tort)")" -ge 2 ] 2>/dev/null \
  || { t_garde=$((t_garde+1)); faute ablation-vide-l-ancienne-regle-ne-bloque-plus; }
# LE BANC NE LAISSE RIEN DERRIERE LUI. Sa premiere version faisait naitre ses temoins dans une
# substitution de commande : le `trap` du parent ne voyait aucun pid et QUATRE processus
# survivaient a chaque passage — dont un `ninja` que la garde du vrai constructeur aurait pris
# pour un build, et un brûleur de CPU. Le banc tue et RECOMPTE ; le reliquat est juge ici.
[ "$(n "$(s bgb_temoins_nes)")" = 4 ]     || { t_garde=$((t_garde+1)); faute temoins-non-tous-nes; }
[ "$(n "$(s bgb_temoins_restants)")" = 0 ] || { t_garde=$((t_garde+1)); faute temoins-du-banc-survivants; }

# =========================================== 3. AUCUN TICK MUET, SUR LE TEXTE DE LA BOUCLE ====
MC=$(python3 "$AP/lib/builder_mute_census.py" 2>/dev/null) || MC=""
m(){ printf '%s\n' "$MC" | sed -n "s/^$1=//p" | tail -1; }
M_MUETS=$(n "$(m builder_mute_continues)")
M_NUS=$(n "$(m builder_unthrottled_continues)")
M_TOTAL=$(n "$(m builder_continues_total)")
M_INTERNES=$(n "$(m builder_inner_loops)")
M_AV_MUETS=$(n "$(m builder_mute_continues_before)")
M_AV_NUS=$(n "$(m builder_unthrottled_continues_before)")
t_muet=0
[ "$(n "$(m mute_census_ran)")" = 1 ] || { t_muet=$((t_muet+1)); faute recensement-de-texte-muet; }
if [ "$M_MUETS" -ge 0 ] 2>/dev/null; then t_muet=$((t_muet + M_MUETS))
else t_muet=$((t_muet+1)); faute sorties-muettes-non-comptees; fi
if [ "$M_NUS" -ge 0 ] 2>/dev/null; then t_muet=$((t_muet + M_NUS))
else t_muet=$((t_muet+1)); faute sorties-non-etranglees-non-comptees; fi
# LE PLANCHER DE VACUITE : un recensement qui ne trouve aucune sortie ne surveille rien.
[ "$M_TOTAL" -ge 10 ] 2>/dev/null || { t_muet=$((t_muet+1)); faute boucle-sans-sortie-recensee; }
# Une boucle imbriquee rendrait la regle FAUSSE : un `continue` y viserait la boucle interne.
[ "$M_INTERNES" = 0 ] || { t_muet=$((t_muet+1)); faute boucle-imbriquee-la-regle-ne-tient-plus; }
# L'INSTRUMENT SAIT-IL VOIR LE DEFAUT ? S'il rend zero sur le fichier D'AVANT, il rend zero sur
# tout, et le vert d'aujourd'hui ne vaut rien.
[ "$M_AV_MUETS" -ge 1 ] 2>/dev/null || { t_muet=$((t_muet+1)); faute avant-sans-sortie-muette; }
[ "$M_AV_NUS" -ge 1 ] 2>/dev/null   || { t_muet=$((t_muet+1)); faute avant-sans-sortie-bavarde; }

# ============================================ LE REGISTRE, ET SON DETECTEUR CONTROLE ==========
# Le registre `logs/builder-ticks.tsv` est append-only et vit hors des repertoires qu'une course
# efface. C'est LUI qui dit que le correctif TOURNE, et pas seulement qu'il est sur le disque :
# bash garde l'inode d'origine ouvert, donc un `auto_build_apk.sh` corrige pendant que son demon
# tourne continue d'executer l'ANCIEN texte, sans que rien ne le signale. `builder_tick_record`
# ecrit son `$$` en colonne 2 ; une ligne dont le pid est un `auto_build_apk.sh` VIVANT est la
# seule preuve que le tour muet a disparu pour de bon.
# Un registre vide est donc un DEFAUT, pas une abstention : le constructeur ne tourne pas, ou il
# tourne sous l'ancien code — c'est exactement la panne de cet item.
compte_registre(){          # $1 = TSV -> RG_N= RG_CAUSES= RG_IDLE=
  awk -F'\t' '
    { n++; c[$3]++ }
    $3=="build-en-cours" && $6+0 >= 1 { idle++ }   # un tour ou un demon inactif a ete ecarte
    END { printf "RG_N=%d\nRG_CAUSES=%d\nRG_IDLE=%d\n", n+0, length(c), idle+0 }
  ' "$1"
}
RG_N=0; RG_CAUSES=0; RG_IDLE=0; RG_LIVE=0; RG_FRESH=-1
if [ -s "$REG" ]; then
  eval "$(compte_registre "$REG")"
  RG_FRESH=$(( $(date +%s) - $(cut -f1 "$REG" | tail -1) ))
  for p in $(cut -f2 "$REG" | sort -un); do
    case "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" in
      *auto_build_apk.sh*) RG_LIVE=$((RG_LIVE+1)) ;;
    esac
  done
fi
t_reg=0
[ "$RG_N" -ge 1 ] 2>/dev/null    || { t_reg=$((t_reg+1)); faute registre-vide-aucun-tour-consigne; }
[ "$RG_CAUSES" -ge 1 ] 2>/dev/null || { t_reg=$((t_reg+1)); faute aucune-cause-nommee; }
[ "$RG_LIVE" -ge 1 ] 2>/dev/null || { t_reg=$((t_reg+1)); faute aucun-constructeur-vivant-a-ecrit-le-registre; }
CTL=$(mktemp "${TMPDIR:-/tmp}/bldreg.XXXXXX") || CTL=""
CTL_N=-1; CTL_CAUSES=-1; CTL_IDLE=-1
if [ -n "$CTL" ]; then
  printf '1000\t111\tbuild-en-cours\t0\t0\t1\tdeadbee\tun_demon_inactif_ecarte\n'  > "$CTL"
  printf '1001\t111\tbuild-en-cours\t2\t2\t0\tdeadbee\tdeux_compilateurs\n'       >> "$CTL"
  printf '1002\t111\twip\t-\t-\t-\tdeadbee\tcheckpoint\n'                        >> "$CTL"
  eval "$(compte_registre "$CTL" | sed 's/^/CTL_/')"
  CTL_N=${CTL_RG_N:--1}; CTL_CAUSES=${CTL_RG_CAUSES:--1}; CTL_IDLE=${CTL_RG_IDLE:--1}
  rm -f "$CTL"
fi
[ "$CTL_N" = 3 ]      || { t_reg=$((t_reg+1)); faute controle-registre-mal-compte; }
[ "$CTL_CAUSES" = 2 ] || { t_reg=$((t_reg+1)); faute controle-causes-mal-comptees; }
[ "$CTL_IDLE" = 1 ]   || { t_reg=$((t_reg+1)); faute controle-demon-inactif-non-detecte; }
# Le banc a fait ecrire la VRAIE `say_cause` dans un registre jetable : 5 appels -> 5 lignes,
# 3 seulement au journal. C'est l'effet, mesure, pas une absence.
[ "$(n "$(s bgb_registre_lignes)")" = 5 ] || { t_reg=$((t_reg+1)); faute registre-etrangle-a-tort; }
[ "$(n "$(s bgb_journal_lignes)")" = 3 ]  || { t_reg=$((t_reg+1)); faute journal-mal-etrangle; }

# ========================================================================= LE VERDICT =========
TOTAL=$((t_cout + t_garde + t_muet + t_reg + penalite))
pub builder_silent_skips "$TOTAL"
pub builder_terms "cout$t_cout+garde$t_garde+muet$t_muet+registre$t_reg+penalite$penalite${pourquoi:+:$pourquoi}"

# LES GRANDEURS BRUTES : une porte qui ne publie que son total ne dit pas ce qui a cede.
pub builder_cost_last_silence_s "$C_DERNIER"
pub builder_cost_max_silence_mute_ticks "$C_MUETS"
pub builder_cost_max_silence_commits "$C_COMMITS"
pub builder_cost_silences_over_7h "$C_LONGS"
pub builder_cost_last_silence_commits "$(c cost_last_silence_pending_commits)"
pub builder_cost_max_silence_s "$C_PIRE"
pub builder_cost_ticks_read "$C_TICKS"
pub builder_mute_continues "$M_MUETS"
pub builder_unthrottled_continues "$M_NUS"
pub builder_continues_total "$M_TOTAL"
pub builder_mute_continues_before "$M_AV_MUETS"
pub builder_unthrottled_continues_before "$M_AV_NUS"
pub builder_before_commit "$(m builder_before_commit)"
pub builder_idle_daemon_verdict "$(s bgb_demon_idle_neuve)"
pub builder_idle_daemon_old_verdict "$(s bgb_demon_idle_vieille)"
pub builder_arm_delivered "$(s bgb_livre_decision)"
pub builder_arm_off "$(s bgb_off_decision)"
pub builder_registry "$REG"
pub builder_registry_lines "$RG_N"
pub builder_registry_causes "$RG_CAUSES"
pub builder_registry_idle_skips "$RG_IDLE"
pub builder_registry_live_writers "$RG_LIVE"
pub builder_registry_fresh_s "$RG_FRESH"
pub builder_registry_ctl_lines "$CTL_N"
pub builder_registry_ctl_idle "$CTL_IDLE"
pub builder_live_gradle_daemons "$(s bgb_demons_gradle_vivants)"
pub builder_bench_witnesses_left "$(s bgb_temoins_restants)"
pub builder_armed "$ARMED"
pub builder_census_ran "$([ -n "$COUT" ] && [ -n "$ST" ] && [ -n "$MC" ] && echo 1 || echo 0)"

# Les bruts des trois instruments, sous un prefixe a eux : le moissonneur garde la DERNIERE
# valeur d'une cle, et un relai homonyme d'un terme du verdict l'ecraserait.
printf '%s\n' "$COUT" | sed -n 's/^\([a-z_][a-z0-9_]*\)=/blc_\1=/p'
printf '%s\n' "$ST"   | sed -n 's/^\([a-z_][a-z0-9_]*\)=/bls_\1=/p'
printf '%s\n' "$MC"   | sed -n 's/^\([a-z_][a-z0-9_]*\)=/blm_\1=/p'

# LES OCTETS JUGES. `auto_build_apk.sh` n'est sous aucun des quatre repertoires que
# `lib/verdict_sources.sh` epingle (`lib|validators|acquis|tests`) : il ne peut pas etre gele par
# la porte de fraicheur. C'est donc son EMPREINTE, publiee ici, qui dit quels octets ont ete juges.
for f in auto_build_apk.sh lib/builder_guard_selftest.sh lib/builder_silence_cost.py \
         lib/builder_mute_census.py lib/fixtures/gradle-cmdlines.tsv lib/census/$ID.sh; do
  k="bl_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done

exit 0
