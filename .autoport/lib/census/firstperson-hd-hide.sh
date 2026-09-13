#!/usr/bin/env bash
# census/firstperson-hd-hide.sh — LES DEUX TERMES QUE LE MOTEUR NE PEUT PAS PRODUIRE.
#
# Le contrat de l'item demande quatre choses. Deux vivent dans une image et sortent du moteur
# (les pixels, le temoin de masquage). Les deux autres vivent dans l'HISTOIRE du depot :
#
#   1. LE COUPABLE EST NOMME. Pas recopie d'un rapport : DERIVE ici, par `git log -S`, et chaque
#      affirmation le concernant est un compte falsifiable a cote de son denominateur.
#   3. RIEN D'AUTRE NE CASSE. Les trois acquis que l'owner interdit de casser (pas de temps fixe,
#      interpolation d'animation, etirement des modeles HD) ont chacun une REGION de code. On
#      publie l'empreinte de chaque region AVANT (au commit de base, ancre sur un MARQUEUR de mon
#      propre changement, jamais sur une date) et MAINTENANT. Egales = ce changement-ci n'a pas
#      touche l'acquis. Une empreinte est une grandeur produite par le code, pas une promesse.
#
# CE QU'IL NE FAIT PAS. Il ne juge aucun pixel, ne lit pas l'appareil, n'ecrit rien dans proof.txt
# (`lib/proof_run.sh` filtre `proof_feature_*` et `proof_census_*` au point de production). Sa
# sortie est `cle=valeur`, une par ligne, SANS ESPACE dans la valeur — proof.txt jette toute
# ligne dont la valeur en porte un.
#
# `grep -c`, JAMAIS `grep -q`. Sous `pipefail`, `grep -q` sort en 141 (SIGPIPE) sur un gros
# fichier qui PORTE le motif : la condition devient fausse la ou elle devrait etre vraie.
set -uo pipefail
export LC_ALL=C
cd "$(git rev-parse --show-toplevel)" || exit 1

pub(){ printf '%s=%s\n' "$1" "$2"; }
# Une valeur sans espace, toujours : les espaces deviennent des soulignes, le vide devient `-`.
pubs(){ local v="${2:-}"; v=${v//[[:space:]]/_}; printf '%s=%s\n' "$1" "${v:--}"; }
sha16(){ sha256sum 2>/dev/null | cut -c1-16; }

HD=goal_src/jak1/pc/jak-hd.gc

# ─── 1. LE COUPABLE, DERIVE ───────────────────────────────────────────────────────────────────
# Le correctif d'aout se reconnait a ce qu'il a AJOUTE : le miroir de visibilite lisant les deux
# bits `(draw-status hidden no-anim)` au lieu du seul `hidden`. Le coupable se reconnait a ce
# qu'il a AJOUTE a son tour : la garde `__pc-npcf-fix-armed?` autour de ce meme terme. Les deux
# se derivent du CONTENU par `git log -S`, dans l'ordre chronologique — aucune date, aucun sha
# ecrit a la main.
FIX=$(git log --reverse --format=%h -S'(draw-status hidden no-anim)' -- "$HD" 2>/dev/null | head -1)
CULP=$(git log --reverse --format=%h -S'__pc-npcf-fix-armed?' -- "$HD" 2>/dev/null | head -1)
pubs firstperson_hd_fix_commit "${FIX:-}"
pubs firstperson_hd_culprit_commit "${CULP:-}"
pubs firstperson_hd_fix_date "$([ -n "${FIX:-}" ] && git log -1 --format=%ad --date=short "$FIX" 2>/dev/null)"
pubs firstperson_hd_culprit_date "$([ -n "${CULP:-}" ] && git log -1 --format=%ad --date=short "$CULP" 2>/dev/null)"
pubs firstperson_hd_culprit_item "$([ -n "${CULP:-}" ] && git log -1 --format=%s "$CULP" 2>/dev/null | sed -n 's/^\[autoport\/\([^]]*\)\].*/\1/p')"

# Les comptes qui rendent ces deux noms FALSIFIABLES. Chacun avec son denominateur : « 1 sur 1 »
# et « 1 sur 40 » ne disent pas la meme chose d'un `git log -S`.
pub firstperson_hd_fix_candidates "$(git log --format=%h -S'(draw-status hidden no-anim)' -- "$HD" 2>/dev/null | grep -c . || true)"
pub firstperson_hd_culprit_candidates "$(git log --format=%h -S'__pc-npcf-fix-armed?' -- "$HD" 2>/dev/null | grep -c . || true)"
# Le correctif d'aout AJOUTE bien le terme `no-anim` au predicat du miroir.
pub firstperson_hd_fix_adds_noanim "$([ -n "${FIX:-}" ] && git show "$FIX" -- "$HD" 2>/dev/null | grep -cE '^\+.*draw-status hidden no-anim' || echo 0)"
# Le coupable RETIRE un predicat `th` non garde et le REMPLACE par un predicat garde.
pub firstperson_hd_culprit_drops_th "$([ -n "${CULP:-}" ] && git show "$CULP" -- "$HD" 2>/dev/null | grep -cE '^-.*\(th \(if \(or dhid' || echo 0)"
pub firstperson_hd_culprit_adds_guard "$([ -n "${CULP:-}" ] && git show "$CULP" -- "$HD" 2>/dev/null | grep -cE '^\+.*__pc-npcf-fix-armed\?' || echo 0)"
# LA RAISON, MESUREE : le pont rend 1 par defaut, donc `(zero? ...)` est FAUX dans le binaire
# livre et la branche `no-anim` ne s'execute plus jamais hors ablation.
pub firstperson_hd_guard_returns_one_by_default \
  "$(sed -n '/^s32 pc_npcf_fix_armed()/,/^}/p' game/kernel/jak1/kmachine.cpp 2>/dev/null | grep -cE 'return autoport_proof::armed\(\) \? 1 : 0;' || true)"
# Le nombre de commits qui ont touche jak-hd.gc entre les deux : la distance, pas une impression.
if [ -n "${FIX:-}" ] && [ -n "${CULP:-}" ]; then
  pub firstperson_hd_commits_between "$(git log --format=%h "$FIX".."$CULP" -- "$HD" 2>/dev/null | grep -c . || true)"
else
  pub firstperson_hd_commits_between -1
fi

# ─── 2. LE COMMIT DE BASE, ANCRE SUR UN MARQUEUR ──────────────────────────────────────────────
# « AVANT » lu a `HEAD:` s'accuse lui-meme des que le travail est commite. On ancre sur le
# MARQUEUR de ce changement-ci (`fp1p?`, le nom de la liaison qui lit l'etat premiere personne) :
# le premier commit qui l'introduit est le mien, son parent est la base. Le commit retenu est
# PUBLIE — c'est lui qu'on relit, pas une date.
MINE=$(git log --reverse --format=%H -S'fp1p?' -- "$HD" 2>/dev/null | head -1)
BASE=""
[ -n "$MINE" ] && BASE=$(git rev-parse --short "$MINE^" 2>/dev/null)
# Pas encore commite : la base est HEAD, et l'arbre de travail porte le changement.
[ -n "$BASE" ] || BASE=$(git rev-parse --short HEAD 2>/dev/null)
pubs firstperson_hd_base_commit "$BASE"
pubs firstperson_hd_base_anchored_on "$([ -n "$MINE" ] && echo marqueur-fp1p || echo head-arbre-sale)"

# ─── 3. LES TROIS ACQUIS, PAR EMPREINTE DE REGION ─────────────────────────────────────────────
# Une region = les lignes d'un fichier qui portent les marqueurs de l'acquis, dans l'ordre. Deux
# fichiers de l'item (jak-hd.gc, Merc2.cpp) sont EDITES par ce changement : comparer leur fichier
# entier ne dirait rien. La region, elle, dit si l'acquis lui-meme a bouge.
region_sha(){ # <commit|WT> <fichier> <motif-etendu>
  local rev="$1" f="$2" pat="$3"
  if [ "$rev" = WT ]; then
    grep -hE "$pat" "$f" 2>/dev/null | sha16
  else
    git show "$rev:$f" 2>/dev/null | grep -hE "$pat" 2>/dev/null | sha16
  fi
}
region_lines(){ local rev="$1" f="$2" pat="$3"
  if [ "$rev" = WT ]; then grep -hcE "$pat" "$f" 2>/dev/null || true
  else git show "$rev:$f" 2>/dev/null | grep -hcE "$pat" 2>/dev/null || true; fi
}

UNCH=0; TOT=0
acquis(){ # <cle> <fichier> <motif>
  local key="$1" f="$2" pat="$3" a b n
  a=$(region_sha "$BASE" "$f" "$pat"); b=$(region_sha WT "$f" "$pat")
  n=$(region_lines WT "$f" "$pat")
  TOT=$((TOT+1))
  pubs "firstperson_hd_acquis_${key}_before" "$a"
  pubs "firstperson_hd_acquis_${key}_after"  "$b"
  pub  "firstperson_hd_acquis_${key}_lines"  "${n:-0}"
  if [ -n "$a" ] && [ "$a" = "$b" ] && [ "${n:-0}" -gt 0 ] 2>/dev/null; then
    UNCH=$((UNCH+1)); pub "firstperson_hd_acquis_${key}_unchanged" 1
  else
    pub "firstperson_hd_acquis_${key}_unchanged" 0
  fi
}

# (a) pas de temps fixe — `tick_worst_dev_pct_x100` sort d'ici.
acquis fixed_tick game/graphics/fixed_tick.cpp '.'
# (b) interpolation d'animation / jitter — `anim_sweep_defects` sort d'ici.
acquis render_pace game/graphics/render_pace.cpp '.'
# (c) etirement HD, moitie GOAL : le reciblage et sa sonde, DANS le fichier que je modifie.
acquis hd_stretch_goal "$HD" 'hd-root-scan!|\*hd-stretch-arm\*|\*hd-stretch-t0\*|__pc-hd-proof|fill-jak-hd-bones!|st-warm'
# (d) etirement HD, moitie GPU : les compteurs HDLEN de Merc2, DANS le fichier que je modifie.
acquis hd_stretch_gpu game/graphics/opengl_renderer/foreground/Merc2.cpp 's_hdlen|HDLEN|merc2_hd_stretch|merc2_hd_skel_joint'

pub firstperson_hd_acquis_regions_total "$TOT"
pub firstperson_hd_acquis_regions_unchanged "$UNCH"

# ─── 4. LE MASQUAGE EXISTE-T-IL DANS LE CODE, AVANT ET APRES ? ────────────────────────────────
# Le terme AVANT doit etre NON NUL du bon cote : au commit de base, AUCUN chemin vivant ne masque
# les compagnons du joueur en premiere personne — c'est l'etat que l'owner a signale. Un zero des
# deux cotes voudrait dire que la sonde ne voit rien, pas que le defaut est corrige.
pub firstperson_hd_paths_before "$(git show "$BASE:$HD" 2>/dev/null | grep -cE 'first-person-mode' || true)"
pub firstperson_hd_paths_after  "$(grep -cE 'first-person-mode' "$HD" 2>/dev/null || true)"
exit 0
