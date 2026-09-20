#!/usr/bin/env bash
# census/harness-judge-binary-race-with-builder.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt`.
#
# CE QU'IL MESURE, DANS L'ORDRE DES SIX POINTS DU CONTRAT :
#   1. LE JUGE NE RELIT PLUS LE DISQUE : il compare `sha=` a l'empreinte enregistree PAR LA
#      COURSE, rehachee sur les octets de la copie figee            -> t1
#   2. LE BANC : course jouee, binaire du disque REMPLACE, verdict VERT ; et deux controles —
#      une preuve qui ment sur son empreinte, une preuve sans gel — qui doivent rester ROUGES ;
#      plus le bras d'AVANT, qui dit ce que l'ancienne regle aurait refuse         -> t2
#   3. LES CROCHETS DE RECENSEMENT passent par la meme empreinte figee, ou DISENT qu'ils
#      veulent l'arbre vivant                                                      -> t3
#   4. LE RELEVE des verdicts « n'est pas celui de ... sur le disque » sur 7 jours  -> t4
#   5. LA GARDE DE VERROU apparie pid ET instant de demarrage, jamais `kill -0` seul -> t5
#   6. LE CONSTRUCTEUR n'ecrit JAMAIS pendant une course : la patience expiree attend la course
#      au lieu d'expirer                                                            -> t6
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`. Le denominateur est publie a cote de chaque compte : un
# plancher calibre sur une population vide rendrait vert par cecite.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "judge_binary_race_defects=99"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# Le moissonneur de proof_run.sh ne garde que `^cle=valeur$` SANS espace, et jette une valeur
# vide. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ============================================================== LE BANC, SUR DU CODE REEL =====
BN=$(timeout -k 30 600 bash "$AP/lib/binary_race_selftest.sh" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

defauts=0; pourquoi=""
faute(){ defauts=$((defauts+1)); pourquoi="${pourquoi:+$pourquoi+}$1"; }
est(){ [ "$(n "$1")" = "$2" ] || faute "$3"; }
aumoins(){ local v; v=$(n "$1"); { [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null; } || faute "$3"; }

[ -n "$BN" ] || faute banc-muet
est brs_selftest_ran 1 banc-n-a-pas-tourne

# ------------------------------------- 1. LE JUGE NE RELIT PLUS LE DISQUE --------------------
est brs_a4_juge_lit_le_disque 0 juge-relit-encore-le-disque
est brs_a4_juge_lit_le_gel    1 juge-ne-lit-pas-le-gel
pub jbr_juge_lit_le_disque "$(n brs_a4_juge_lit_le_disque)"
pub jbr_juge_lit_le_gel    "$(n brs_a4_juge_lit_le_gel)"

# ------------------------------------- 2. LE BANC : VERT APRES UN BUILD, ROUGE SI ON MENT ----
est brs_a1_monte 1 bac-a-sable-non-monte
# LA CONDITION DOIT ETRE PRESENTE : sans un disque qui DIFFERE vraiment de ce que la course a
# mesure, « zero plainte » ne dirait rien du tout (les deux bras seraient d'accord).
est brs_a1_disque_a_change 1 le-disque-n-a-pas-change-l-essai-est-vide
est brs_a1_plaintes 0          juge-refuse-une-preuve-juste-apres-un-build
est brs_a1_plaintes_sans_gel 0 juge-ne-voit-pas-le-gel-de-la-course
# LES DEUX CONTROLES : un juge devenu aveugle passerait la jambe ci-dessus sans rien mesurer.
aumoins brs_a2_plaintes 1          controle-empreinte-menteuse-non-detectee
aumoins brs_a3_plaintes_sans_gel 1 controle-preuve-sans-gel-non-detectee
est brs_a1_avant_aurait_refuse 1   bras-d-avant-vide-de-sens
pub jbr_apres_build_plaintes     "$(n brs_a1_plaintes)"
pub jbr_menteuse_plaintes        "$(n brs_a2_plaintes)"
pub jbr_sans_gel_plaintes        "$(n brs_a3_plaintes_sans_gel)"
pub jbr_avant_aurait_refuse      "$(n brs_a1_avant_aurait_refuse)"
pub jbr_sha_course               "$(s brs_a1_sha_course)"
pub jbr_sha_disque_apres_build   "$(s brs_a1_sha_disque)"

# ------------------------------------- 3. LES CROCHETS DE RECENSEMENT ------------------------
# POPULATION : les crochets qui NOMMENT l'un des deux binaires d'une course. DEFAUT : ceux qui ne
# passent ni par `lib/binary_freeze.sh`, ni par une declaration explicite `BINAIRE-VIVANT-VOULU`.
# Un crochet qui veut l'arbre vivant a le droit de l'avoir — a condition de le DIRE dans son code,
# ou la porte le lit. Une liste d'exceptions tenue ici serait une legende, pas une mesure.
c_pop=0; c_sans=0; c_noms=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  c_pop=$((c_pop+1))
  if grep -q 'binary_freeze.sh' "$f" 2>/dev/null || grep -q 'BINAIRE-VIVANT-VOULU' "$f" 2>/dev/null; then
    continue
  fi
  c_sans=$((c_sans+1)); c_noms="${c_noms:+$c_noms,}$(basename "$f")"
done < <(grep -lE 'build-android/lib/arm64-v8a/libgk\.so|build/game/gk' "$AP"/lib/census/*.sh 2>/dev/null | sort)
pub jbr_crochets_population "$c_pop"
pub jbr_crochets_sans_gel   "$c_sans"
pub jbr_crochets_sans_noms  "${c_noms:--}"
[ "$c_pop" -gt 0 ] || faute population-de-crochets-vide
[ "$c_sans" = 0 ]  || faute "crochets-qui-relisent-l-arbre:$c_sans"

# ------------------------------------- 4. LE RELEVE DES VERDICTS DE 7 JOURS ------------------
# La population n'est PAS versionnee (`.gitignore` -> `.autoport/logs/`) : elle vit sur cette
# machine et nulle part ailleurs. Le denominateur — les verdicts LUS — est publie a cote du
# compte. On ne lit QUE `validator-NNN.txt` : les `attempt-*.jsonl` contiennent le TEXTE du
# script du juge recopie par un worker en exploration, pas des verdicts rendus.
REL=$(python3 - <<'PY' 2>/dev/null
import os, re, time
base = '.autoport/logs'
limite = time.time() - 7*86400
motif = re.compile(r"n'est pas celui de \S+ sur le disque")
lus = 0; fichiers = 0; occ = 0; items = set(); essais = set()
for item in sorted(os.listdir(base)) if os.path.isdir(base) else []:
    d = os.path.join(base, item)
    if not os.path.isdir(d):
        continue
    for nom in sorted(os.listdir(d)):
        m = re.fullmatch(r'validator-(\d+)\.txt', nom)
        if not m:
            continue
        p = os.path.join(d, nom)
        try:
            if os.path.getmtime(p) < limite:
                continue
            txt = open(p, errors='replace').read()
        except OSError:
            continue
        lus += 1
        k = len(motif.findall(txt))
        if k:
            fichiers += 1; occ += k; items.add(item); essais.add((item, m.group(1)))
print('lus=%d' % lus)
print('fichiers=%d' % fichiers)
print('occurrences=%d' % occ)
print('items=%d' % len(items))
print('essais=%d' % len(essais))
print('liste=%s' % (','.join(sorted(items)) or '-'))
PY
)
r(){ printf '%s\n' "$REL" | sed -n "s/^$1=//p" | tail -1; }
rl=$(r lus)
pub jbr_releve_verdicts_lus_7j   "${rl:--1}"
pub jbr_releve_fichiers_7j       "$(r fichiers)"
pub jbr_releve_occurrences_7j    "$(r occurrences)"
pub jbr_releve_items_7j          "$(r items)"
pub jbr_releve_essais_debites_7j "$(r essais)"
pub jbr_releve_items_liste       "$(r liste)"
# UN RELEVE SANS DENOMINATEUR N'EST PAS UN RELEVE : un zero lu sur zero verdict est une cecite.
case "${rl:-}" in ''|*[!0-9]*) faute releve-non-mesure ;; *) [ "$rl" -gt 0 ] || faute releve-sans-denominateur ;; esac

# ------------------------------------- 5. LA GARDE DE VERROU ---------------------------------
est brs_b_tenu     1 verrou-tenu-non-reconnu
est brs_b_recycle  0 pid-recycle-pris-pour-un-detenteur
est brs_b_aout     0 marqueur-d-aout-pris-pour-un-detenteur
est brs_b_sans_pid 0 verrou-sans-pid-pris-pour-un-detenteur
# LE BRAS D'AVANT : `kill -0` nu tenait ce meme verrou pour vivant. Sans ce 1, la jambe ci-dessus
# ne dirait pas qu'elle a corrige quoi que ce soit.
est brs_b_avant_kill0_aout 1 bras-d-avant-du-verrou-vide-de-sens
est brs_c_gardes_sans_pidguard 0 gardes-de-verrou-sur-kill-0-nu
aumoins brs_c_verrou_lecteurs 1 population-de-lecteurs-de-verrou-vide
pub jbr_verrou_raison_recycle "$(s brs_b_recycle_raison)"
pub jbr_verrou_raison_aout    "$(s brs_b_aout_raison)"
pub jbr_verrou_lecteurs       "$(n brs_c_verrou_lecteurs)"
pub jbr_verrou_sans_pidguard  "$(n brs_c_gardes_sans_pidguard)"
pub jbr_verrou_avant_kill0    "$(n brs_b_avant_kill0_aout)"

# ------------------------------------- 6. LE CONSTRUCTEUR N'ECRIT PAS SOUS UNE COURSE --------
est brs_c_vue     1 course-en-vol-invisible
est brs_c_recycle 0 course-en-vol-fabriquee-par-un-pid-recycle
est brs_c_mort    0 course-morte-lue-comme-en-vol
est brs_c_garde_encadre 1 la-garde-n-encadre-pas-l-ecriture
est brs_c_motif_cmdline 0 garde-encore-sur-un-motif-de-ligne-de-commande
pub jbr_envol_vue            "$(n brs_c_vue)"
pub jbr_envol_ligne_patience "$(n brs_c_ligne_patience)"
pub jbr_envol_ligne_garde    "$(n brs_c_ligne_garde)"
pub jbr_envol_ligne_install  "$(n brs_c_ligne_install)"

# ============================================================================ LE VERDICT ======
pub judge_binary_race_defects "$defauts"
pub judge_binary_race_why     "${pourquoi:--}"
