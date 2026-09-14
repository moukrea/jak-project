#!/usr/bin/env bash
# lib/build_freshness_selftest.sh — LE BANC DE `lib/build_x86.sh`.
#
# IL MESURE UN COMPORTEMENT, PAS UN TEXTE. Chaque jambe seme un etat dans un arbre ninja
# JETABLE, fait jouer LE VRAI ninja et LA VRAIE PORTE (`lib/build_x86.sh`, jamais une copie de
# sa logique), et publie ce qui en sort. Deux jambes sur trois portent leur CONTROLE : un objet
# qu'on abime ET un objet voisin qu'on laisse tranquille, sinon « tout recompile » et « ce que
# j'ai abime recompile » se lisent pareil.
#
# CE QU'IL REPRODUIT, ET POURQUOI CES DEUX ETATS-LA (mesure du 12/09 sur `build/`, archivee dans
# `lib/census/capture-build-tree-reinvalidates-itself/avant-explain.txt`) : les 335 aretes qu'une
# construction SANS EDITION relancait se repartissaient en exactement deux motifs de ninja —
#   320 x  « stored deps info out of date for 'X' »   -> jambe B : enregistrement plus VIEUX que l'objet
#    11 x  « deps for 'X' are missing »               -> jambe C : AUCUN enregistrement
# Le banc seme ces deux etats-la, et rien d'autre.
#
# LA JAMBE A EST UN CONTROLE NEGATIF SUR NINJA LUI-MEME : un journal abime EN QUEUE se repare
# tout seul au chargement suivant (152 octets -> 148, l'avertissement disparait). C'est la raison
# pour laquelle cette panne n'avait jamais ete vue : le mode de corruption ordinaire est
# invisible. Celui de `build/` ne se reparait PAS — meme taille a trois chargements successifs,
# 2 831 988 octets a 15:43, 15:44, 15:45 — et c'est ce qui l'a rendu permanent.
#
# Sortie : `cle=valeur` sur la sortie standard. `-1` = la jambe n'a pas pu conclure ; jamais 0,
# qui passerait une porte `== 0` en silence.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "bf_banc_ran=0"; exit 1; }
PORTE="$ROOT/.autoport/lib/build_x86.sh"
[ -x "$PORTE" ] || [ -f "$PORTE" ] || { echo "bf_banc_ran=0"; exit 1; }

# Un nom FIXE, jamais `mktemp -d` : la porte refuse un dossier dont le nom contient `build-arm64`
# ou `build-android`, et un nom tire au hasard peut tomber sur n'importe quoi.
T="${TMPDIR:-/tmp}/autoport-build-freshness-$$"
rm -rf "$T"; mkdir -p "$T" || { echo "bf_banc_ran=0"; exit 1; }
trap 'rm -rf "$T"' EXIT

pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }
# Combien d'aretes ninja jouerait-il, sans rien jouer.
aretes(){ ninja -C "$T" -n app 2>/dev/null | grep -cE '^\[[0-9]+/[0-9]+\]' || true; }
# Le meme compte, mais restreint a un objet nomme : c'est ce qui separe « a recompile CE
# fichier » de « a tout recompile ».
arete_de(){ ninja -C "$T" -n app 2>/dev/null | grep -cE "^\[[0-9]+/[0-9]+\] CC $1\$" || true; }
motif(){ ninja -C "$T" -n -d explain app 2>&1 >/dev/null | grep -c "$1" || true; }

semer(){
  cat > "$T/h.h" <<'EOF'
#define K 1
EOF
  printf '#include "h.h"\nint a(void){return K;}\n'         > "$T/a.c"
  printf '#include "h.h"\nint b(void){return K+1;}\n'       > "$T/b.c"
  printf '#include "h.h"\nint c(void){return K+2;}\n'       > "$T/c.c"
  printf 'int a(void);int b(void);int c(void);\nint main(void){return a()+b()+c();}\n' > "$T/m.c"
  cat > "$T/build.ninja" <<'EOF'
rule cc
  command = gcc -MD -MF $out.d -c $in -o $out
  description = CC $out
  depfile = $out.d
  deps = gcc
rule link
  command = gcc $in -o $out
  description = LINK $out
build a.o: cc a.c
build b.o: cc b.c
build c.o: cc c.c
build m.o: cc m.c
build app: link a.o b.o c.o m.o
EOF
  ninja -C "$T" app >/dev/null 2>&1
}

semer || { echo "bf_banc_ran=0"; exit 1; }
pub bf_banc_ran 1
pub bf_ninja "$(ninja --version 2>/dev/null)"

# ============================================================ A. L'ARBRE SAIN SE TAIT ========
# Sans ce controle, un « 0 arete » apres reparation ne prouverait rien : il faut savoir que
# l'instrument sait dire 0 sur un arbre qui va bien.
pub bf_a_sain_2e_passe "$(aretes)"

# ====================================== B. ENREGISTREMENT PLUS VIEUX QUE L'OBJET (320 cas) ===
# `touch a.o` place l'objet APRES son enregistrement de dependances, exactement l'etat des 320
# objets de `build/` le 12/09. `b.o` est le controle qu'on laisse tranquille.
touch "$T/a.o"
pub bf_b_abime_recompile   "$(arete_de a.o)"
pub bf_b_temoin_recompile  "$(arete_de b.o)"
pub bf_b_motif_ninja       "$(motif 'stored deps info out of date')"
ninja -C "$T" app >/dev/null 2>&1
pub bf_b_apres_reconstruction "$(aretes)"

# ================================================ C. AUCUN ENREGISTREMENT (11 cas) ===========
# On efface le journal : plus personne n'a d'enregistrement. Le controle n'est plus un objet
# voisin — il n'y en a pas — mais la SORTIE de la jambe : une reconstruction rend le silence.
rm -f "$T/.ninja_deps"
pub bf_c_sans_journal_aretes "$(aretes)"
pub bf_c_motif_ninja         "$(motif 'deps for')"
BF_REBUILD_START=$(date +%s%N)
ninja -C "$T" app >/dev/null 2>&1
BF_REBUILD_RC=$?
BF_REBUILD_NS=$(( $(date +%s%N) - BF_REBUILD_START ))
pub bf_c_apres_reconstruction "$(aretes)"
# Le gain courant porte sur ce meme petit arbre et cette meme invocation du banc.
# La capture du 12/09 reste une mesure historique du jeu, pas une reference de performance.
BF_NOOP_START=$(date +%s%N)
ninja -C "$T" app >/dev/null 2>&1
BF_NOOP_RC=$?
BF_NOOP_NS=$(( $(date +%s%N) - BF_NOOP_START ))
pub bf_c_rebuild_ns "$BF_REBUILD_NS"
pub bf_c_noop_ns "$BF_NOOP_NS"
pub bf_c_rebuild_rc "$BF_REBUILD_RC"
pub bf_c_noop_rc "$BF_NOOP_RC"
pub bf_c_gain_population_objets "$(ninja -C "$T" -t targets all | grep -c ': cc$')"

# ============================== D. CONTROLE NEGATIF SUR NINJA : la corruption ORDINAIRE ======
# Elle se repare toute seule. C'est le controle qui dit pourquoi celle de `build/` etait
# speciale, et il ne coute rien.
AV=$(stat -c %s "$T/.ninja_deps" 2>/dev/null || echo 0)
printf '\377\377\377\177' >> "$T/.ninja_deps"
W1=$(ninja -C "$T" -n app 2>&1 >/dev/null | grep -c 'premature end of file' || true)
W2=$(ninja -C "$T" -n app 2>&1 >/dev/null | grep -c 'premature end of file' || true)
AP=$(stat -c %s "$T/.ninja_deps" 2>/dev/null || echo 0)
pub bf_d_queue_avertit_1 "$W1"
pub bf_d_queue_avertit_2 "$W2"
pub bf_d_queue_retrecit  "$( [ "$AP" -le "$AV" ] && echo 1 || echo 0 )"

# ============================ E. LA PORTE DETECTE ET REPARE UN JOURNAL CASSE =================
# On recasse, et c'est LA PORTE qui juge — pas le banc. Son `bx_deps_corrupt_before` doit valoir
# 1 (le detecteur mord), et la construction suivante doit rendre un arbre muet.
printf '\377\377\377\177' >> "$T/.ninja_deps"
P1=$(bash "$PORTE" --dir "$T" --target app -j 2 2>/dev/null)
g(){ printf '%s\n' "$1" | sed -n "s/^$2=//p" | tail -1; }
pub bf_e_porte_a_vu_casse "$(g "$P1" bx_deps_corrupt_before)"
pub bf_e_porte_recompacte "$(g "$P1" bx_deps_recompacted)"
P2=$(bash "$PORTE" --dir "$T" --target app -j 2 2>/dev/null); RC2=$?
pub bf_e_2e_passe_aretes  "$(g "$P2" bx_edges)"
pub bf_e_2e_passe_travail "$(g "$P2" bx_residual_work)"
pub bf_e_2e_passe_rc      "$RC2"

# ================== F. LA PORTE REFUSE UN BINAIRE PLUS VIEUX QU'UNE DE SES ENTREES ===========
# LES DEUX BRAS, sinon la porte serait verte par INACTION. Bras SAIN d'abord : l'arbre sort de
# E, propre, la porte doit rendre 0 et `bx_bin_fresh=1`. Puis le bras ABIME : on vieillit le
# binaire d'une heure — aucune source ne bouge, seul l'horodatage ment, exactement comme le
# `gk` de 14:36:03 en face d'un `libruntime.a` de 14:43:15.
S=$(bash "$PORTE" --dir "$T" --target app --check-only 2>/dev/null); RCS=$?
pub bf_f_sain_rc    "$RCS"
pub bf_f_sain_frais "$(g "$S" bx_bin_fresh)"
touch -d '-1 hour' "$T/app"
A=$(bash "$PORTE" --dir "$T" --target app --check-only 2>/dev/null); RCA=$?
pub bf_f_perime_rc    "$RCA"
pub bf_f_perime_frais "$(g "$A" bx_bin_fresh)"
pub bf_f_perime_retard "$(g "$A" bx_bin_lag_s)"

# ---- F BIS. LE MEME DEFAUT DANS LA MEME SECONDE. `stat -c %Y` arrondit : un lien saute dont
# l'entree est reecrite 0,4 s plus tard porte le MEME horodatage entier que le binaire, et la
# comparaison `-ge` le declare frais. Ce n'est pas une hypothese — la porte D'AVANT est rejouee
# plus bas sur l'etat seme ici et rend `bf_f_infrasec_avant_rc=0`. Les horodatages sont POSES,
# jamais attendus : `touch -d '@<epoch>.<ns>'` rend la jambe deterministe au lieu de la faire
# dependre d'une course contre la seconde qui tourne.
# LES DEUX BRAS, dans la MEME seconde : le binaire ECRIT APRES ses entrees (il est frais, la
# porte doit laisser passer) puis une entree ecrite APRES le binaire (elle ne l'est plus). Sans
# le premier, une porte qui refuserait tout ecart infra-seconde serait verte sur le second.
for f in a.o b.o c.o m.o; do touch -d '@1700000000.100000000' "$T/$f"; done
touch -d '@1700000000.500000000' "$T/app"
SS=$(bash "$PORTE" --dir "$T" --target app --check-only 2>/dev/null); RCSS=$?
pub bf_f_infrasec_sain_rc    "$RCSS"
pub bf_f_infrasec_sain_frais "$(g "$SS" bx_bin_fresh)"
touch -d '@1700000000.900000000' "$T/a.o"
SD=$(bash "$PORTE" --dir "$T" --target app --check-only 2>/dev/null); RCSD=$?
pub bf_f_infrasec_perime_rc    "$RCSD"
pub bf_f_infrasec_perime_frais "$(g "$SD" bx_bin_fresh)"
pub bf_f_infrasec_retard_ns    "$(g "$SD" bx_bin_lag_ns)"
# CE QUE LA SECONDE ENTIERE EN DISAIT : les deux bras y portent le MEME horodatage, donc l'ancien
# comparateur ne pouvait pas les separer. Publie a cote, il dit POURQUOI la jambe existe.
pub bf_f_infrasec_retard_s     "$(g "$SD" bx_bin_lag_s)"
# LE TEMOIN D'AVANT, et il n'est pas facultatif : sans lui, « la porte sort en 4 » est vert par
# CONSTRUCTION des qu'on l'a ecrit, et rien ne dit que le defaut existait. On fait jouer LA PORTE
# D'AVANT — celle du commit NOMME `14ba12bd23`, jamais `HEAD:`, qui s'accuserait lui-meme des le
# commit qui corrige — sur EXACTEMENT l'etat seme ci-dessus. Elle doit rendre 0 et `frais=1`.
# LA POPULATION EST PUBLIEE A COTE : une reference disparue rend un script VIDE, que `bash` sort
# en 0 — soit le chiffre meme qu'on attend. `bf_f_infrasec_avant_octets` separe « la porte
# d'avant a laisse passer » de « il n'y avait aucune porte a jouer ».
BF_INFRASEC_AVANT_REF=14ba12bd23
git -C "$ROOT" show "$BF_INFRASEC_AVANT_REF:.autoport/lib/build_x86.sh" > "$T/porte-avant.sh" 2>/dev/null
PA=$(bash "$T/porte-avant.sh" --dir "$T" --target app --check-only 2>/dev/null); RCPA=$?
pub bf_f_infrasec_avant_ref     "$BF_INFRASEC_AVANT_REF"
pub bf_f_infrasec_avant_octets  "$(stat -c %s "$T/porte-avant.sh" 2>/dev/null || echo 0)"
pub bf_f_infrasec_avant_rc      "$RCPA"
pub bf_f_infrasec_avant_frais   "$(g "$PA" bx_bin_fresh)"

# ========== G. LA PORTE EST-ELLE LA SEULE ENTREE, ET L'ORDRE LA NOMME-T-IL ? =================
# LES QUATRE JAMBES CI-DESSUS MESURENT LA PORTE. Aucune ne mesure ce qui OBLIGE a y passer : si
# la regle de `hooks/pre-tool.sh` disparaissait, ou si l'ordre permanent continuait de prescrire
# la commande qu'elle refuse, `build_reinvalidation_defects` resterait a 0 pendant que le defaut
# revient — vert par INACTION. C'est le cas mesure de l'essai 1 : la garde refusait deja
# `cmake --build build`, et le banc de la garde (`tests/harness/test_pretool_guard.sh:20`) ET
# l'ordre injecte dans le prompt de CHAQUE worker (`orchestrator.py`) le prescrivaient encore.
#
# ON FAIT JOUER LA VRAIE GARDE, sur sa vraie entree (le JSON d'un appel d'outil), et sur les
# DEUX BRAS : ce qu'elle doit refuser, et ce qu'elle doit laisser passer. Un seul bras serait
# tenu par une garde qui refuse tout.
garde(){
  printf '{"tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(printf '%s' "$1" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))' 2>/dev/null)" \
    | bash "$ROOT/.autoport/hooks/pre-tool.sh" >/dev/null 2>&1
  echo $?
}
pub bf_g_refuse_cmake   "$(garde 'cmake --build build --target gk -j8')"
pub bf_g_refuse_ninja   "$(garde 'ninja -C build gk -j8')"
# LES CONTROLES : la porte elle-meme, l'arbre arm64 (la regle ne vise QUE le bureau, sinon elle
# casserait le seul chemin de l'appareil) et l'essai a vide, qui ne construit rien.
pub bf_g_laisse_porte   "$(garde 'bash .autoport/lib/build_x86.sh --target gk')"
pub bf_g_laisse_arm64   "$(garde 'cmake --build build-android --target gk -j')"
pub bf_g_laisse_avide   "$(garde 'ninja -C build -n gk')"

# L'ORDRE PERMANENT. Le bloc « BUILD & DELIVERY EFFICIENCY » d'`orchestrator.py` est recopie dans
# le prompt de chaque essai : c'est le POINT DE PRODUCTION de la commande qu'un worker tape. On
# mesure qu'il NOMME la porte, et on publie le nombre de lignes lues — un bloc introuvable rend
# une population nulle, jamais un vert.
ORD=$(sed -n '/## BUILD & DELIVERY EFFICIENCY/,/## PROOF ECONOMY/p' "$ROOT/.autoport/orchestrator.py" 2>/dev/null)
pub bf_g_ordre_lignes "$(printf '%s' "$ORD" | grep -c . || true)"
pub bf_g_ordre_nomme_porte "$(printf '%s' "$ORD" | grep -c 'lib/build_x86\.sh' || true)"

# LE TEMOIN D'AVANT. Sans lui, « l'ordre nomme la porte » ne prouve que l'etat du jour : une
# presence est verte par construction des qu'on l'a ecrite. On relit le MEME bloc, avec la MEME
# commande, sur l'etat HERITE — et il rend 0. L'ancre est un COMMIT NOMME et PUBLIE, jamais
# `HEAD:` : lu a `HEAD:`, un temoin d'avant s'accuse lui-meme des le commit qui le corrige.
# `a1b3c45da7` est le commit de l'essai 1 : il avait livre la porte ET la garde, et l'ordre y
# prescrivait encore la commande que la garde refuse.
BF_AVANT_REF=a1b3c45da7
ORD_AV=$(git -C "$ROOT" show "$BF_AVANT_REF:.autoport/orchestrator.py" 2>/dev/null \
         | sed -n '/## BUILD & DELIVERY EFFICIENCY/,/## PROOF ECONOMY/p')
pub bf_g_ordre_avant_ref    "$BF_AVANT_REF"
pub bf_g_ordre_avant_lignes "$(printf '%s' "$ORD_AV" | grep -c . || true)"
pub bf_g_ordre_avant_nomme  "$(printf '%s' "$ORD_AV" | grep -c 'lib/build_x86\.sh' || true)"
