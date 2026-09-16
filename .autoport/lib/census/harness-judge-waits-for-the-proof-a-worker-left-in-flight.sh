#!/usr/bin/env bash
# census/harness-judge-waits-for-the-proof-a-worker-left-in-flight.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt` : ni
# `sha`, ni `frames`, ni `crash`, qui sortent de la machine.
#
# CE QU'IL MESURE, DANS L'ORDRE DES QUATRE POINTS DU LIVRABLE :
#   1. LE COUT D'AVANT, CHIFFRE sur les journaux archives : les essais fermes de force apres
#      leur `result` et dont le juge a ensuite lu « proof.txt absent »          -> t_cout
#   2. LE JUGE ATTEND : course vue par le PROCESSUS ou par le VERROU, aucun signal envoye,
#      attente bornee, PID et attente publies                                   -> t_attend
#   3. LA FERMETURE N'EMPORTE PAS LA COURSE : meme `killpg`, meme instant — attachee elle
#      meurt, detachee elle survit et sa preuve arrive                          -> t_survit
#   4. LES DEUX BRAS COTE A COTE, l'ablation etant l'ABSENCE de la couche        -> t_bras
#
# DEUX SOURCES, ET ELLES NE SE RECOUVRENT PAS. Le banc `lib/inflight_selftest.py` leve le bloc
# de decision de `orchestrator.py` entre ses marqueurs et le fait tourner sur de VRAIS
# processus ; le recensement d'archive, lui, ne mesure que ce qui a DEJA eu lieu. L'un dit que
# le correctif marche, l'autre dit combien le defaut a coute.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`.
#
# CE QUI EST PUBLIE SANS ETRE COMPTE, ET POURQUOI. La consigne dit « au moins 3 le 16/09 » :
# les journaux disent 1 ce jour-la (ao-prepass-tie-alpha 15). `ao-prepass-tie-alpha` 14 n'a pas
# ete ferme de force (`abort_reason` vide, le juge l'avait ATTENDUE, 364 s) et
# `perf-mips2c-neon` 10 l'a ete mais sa course etait en `setsid` : sa preuve existe. Le cout
# reel n'est pas dans une journee, il est dans l'archive : 14 essais sur 24. On publie les
# deux — `cout_perdus_le_16_09` a cote de `cout_perdus` — plutot que de fabriquer un 3.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "envol_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE, et jette une valeur
# VIDE. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ============================================================== LE BANC, HUIT JAMBES REELLES ==
BN=$(timeout -k 30 600 python3 "$AP/lib/inflight_selftest.py" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9.-]*) echo -1 ;; *) echo "${v%%.*}" ;; esac; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
eqs(){ [ "$(s "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ [ "$(n "$1")" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
le(){ local v; v=$(n "$1"); [ "$v" != -1 ] && [ "$v" -le "$2" ] 2>/dev/null && echo 0 || echo 1; }
entre(){ local v; v=$(n "$1")
         [ "$v" != -1 ] && [ "$v" -ge "$2" ] && [ "$v" -le "$3" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne
for j in attend avant sanscourse setsid autreitem plafond verrou verrouperime; do
  [ "$(n "${j}_tue")" != -1 ] || faute "jambe-$j-muette"
  [ "$(s "${j}_panne")" = "" ] || faute "jambe-$j-en-panne"
  [ "$(n "${j}_garde_du_banc")" = 0 ] || faute "jambe-$j-finie-par-la-garde-du-banc"
done

# ======================================== 1. LE COUT D'AVANT, LU SUR LES JOURNAUX ARCHIVES ====
# La population n'est PAS versionnee (`.gitignore:177 -> .autoport/logs/`) : elle vit sur cette
# machine et nulle part ailleurs. Le denominateur — le nombre de journaux LUS — est publie a
# cote du compte : un plancher calibre sur une population vide rendrait vert par cecite.
ARCH=$(python3 - <<'PY' 2>/dev/null
import json, glob, os, re
from collections import Counter
fichiers = sorted(glob.glob('.autoport/logs/*/attempt-*.jsonl'))
pop = []
for p in fichiers:
    item = os.path.basename(os.path.dirname(p)); nnn = os.path.basename(p)[8:11]
    for ligne in open(p, errors='replace'):
        if '"attempt_end"' not in ligne:
            continue
        try:
            ev = json.loads(ligne)
        except Exception:
            continue
        if ev.get('event') == 'attempt_end' and ev.get('abort_reason') == 'post-result':
            pop.append((item, nnn, p, ev.get('ended_at') or ''))
perdus, presents, sans = [], [], []
for item, nnn, p, fin in pop:
    v = '.autoport/logs/%s/validator-%s.txt' % (item, nnn)
    if not os.path.exists(v):
        sans.append((item, nnn)); continue
    t = open(v, errors='replace').read()
    # LES DEUX PHRASES QUE LE CONTRAT NOMME, et elles ne disent pas la meme chose : la premiere
    # est l'absence de preuve, la seconde est le juge qui a VU une course ecrire et a refuse
    # quand meme (generic.sh nomme puis appelle `bad`).
    (perdus if ('proof.txt absent ou vide' in t or 'COURSE EN VOL' in t) else presents).append(
        (item, nnn, fin))
LANCE = re.compile(r'\.autoport/lib/proof_run\.sh\s+\S+\s+(?:device|x86)')
tab = Counter()
for item, nnn, p, fin in pop:
    mode = 'indetermine'
    for ligne in open(p, errors='replace'):
        if 'proof_run.sh' not in ligne:
            continue
        try:
            ev = json.loads(ligne)
        except Exception:
            continue
        brut = json.dumps(ev)
        for m in re.finditer(r'"command"\s*:\s*"((?:[^"\\]|\\.)*)"', brut):
            cmd = m.group(1).replace('\\"', '"')
            if not LANCE.search(cmd):
                continue
            if re.search(r'\b(setsid|nohup)\b', cmd):
                mode = 'detache'
            elif '"run_in_background":true' in brut.replace(' ', ''):
                mode = 'clibg'
            else:
                mode = 'premierplan'
    tab[(mode, 'perdu' if (item, nnn) in [(i, j) for i, j, _ in perdus] else 'present')] += 1
par_item = Counter(i for i, _, _ in perdus)
print('cout_journaux_lus=%d' % len(fichiers))
print('cout_population=%d' % len(pop))
print('cout_perdus=%d' % len(perdus))
print('cout_presents=%d' % len(presents))
print('cout_sans_verdict=%d' % len(sans))
print('cout_items_touches=%d' % len(par_item))
print('cout_perdus_le_16_09=%d' % sum(1 for _, _, f in perdus if f.startswith('2026-09-16')))
print('cout_par_item=%s' % ('+'.join('%s:%d' % kv for kv in sorted(par_item.items())) or '-'))
for mode in ('clibg', 'detache', 'premierplan', 'indetermine'):
    print('cout_%s_perdus=%d' % (mode, tab[(mode, 'perdu')]))
    print('cout_%s_presents=%d' % (mode, tab[(mode, 'present')]))
PY
)
a(){ printf '%s\n' "$ARCH" | sed -n "s/^$1=//p" | tail -1; }
an(){ local v; v=$(a "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
age(){ local v; v=$(an "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
[ -n "$ARCH" ] || faute recensement-d-archive-muet

t_cout=0
# LE DENOMINATEUR D'ABORD : un plancher calibre sur une population vide est un faux vert.
t_cout=$((t_cout + $(age cout_journaux_lus 100)))
t_cout=$((t_cout + $(age cout_population 3)))
# LE COUT, NON NUL — 14 essais le 16/09 au soir, sur 24 fermetures forcees.
t_cout=$((t_cout + $(age cout_perdus 3)))
t_cout=$((t_cout + $(age cout_items_touches 3)))
# ET LA COHERENCE DE LA PARTITION : perdus + presents + sans verdict = la population.
SOMME=$(( $(an cout_perdus) + $(an cout_presents) + $(an cout_sans_verdict) ))
[ "$SOMME" = "$(an cout_population)" ] || t_cout=$((t_cout + 1))

# ============================== 2. LE JUGE ATTEND LA COURSE, ET IL DIT CE QU'IL ATTEND ========
t_attend=0
# LA JAMBE PRINCIPALE : course de 75 s vue par le PROCESSUS, attendue, preuve PRESENTE, et la
# fermeture arrive APRES la course — pas a 45 s.
t_attend=$((t_attend + $(ge attend_pid_vu 1)))
t_attend=$((t_attend + $(eqs attend_vu_par processus)))
t_attend=$((t_attend + $(ge attend_holds 5)))
t_attend=$((t_attend + $(ge attend_attendu_s 20)))
t_attend=$((t_attend + $(eq attend_course_finie_vue 1)))
t_attend=$((t_attend + $(eq attend_preuve_presente 1)))
t_attend=$((t_attend + $(ge attend_tue_a_s 70)))
# LE SECOND TEMOIN, LE VERROU : un ecrivain que le processus ne peut pas nommer (ni le nom du
# script, ni l'argument) est vu quand meme, et sa preuve arrive.
t_attend=$((t_attend + $(eqs verrou_vu_par verrou)))
t_attend=$((t_attend + $(ge verrou_attendu_s 10)))
t_attend=$((t_attend + $(eq verrou_preuve_presente 1)))
# LE MEME PID, NOMME PUIS MUET — un verrou qui nomme un cadavre retiendrait le juge a chaque
# essai jusqu'a la borne.
t_attend=$((t_attend + $(eqs verrouvif_vu_par verrou)))
t_attend=$((t_attend + $(eq verrouvif_est_le_dormeur 1)))
t_attend=$((t_attend + $(eqs verroumort_vu_par -)))
t_attend=$((t_attend + $(eq verroumort_fichier_toujours_la 1)))
t_attend=$((t_attend + $(eq verrouperime_pid_vu 0)))
t_attend=$((t_attend + $(entre verrouperime_tue_a_s 45 55)))
# L'ATTENTE EST BORNEE. Plafond a 10 s sur une course de 75 s : on ferme, on ne relance rien.
t_attend=$((t_attend + $(eq plafond_plafond_atteint 1)))
t_attend=$((t_attend + $(le plafond_attendu_s 15)))
t_attend=$((t_attend + $(entre plafond_tue_a_s 50 62)))
t_attend=$((t_attend + $(eq plafond_item_reel 540)))
t_attend=$((t_attend + $(eq plafond_defaut_x86 240)))
t_attend=$((t_attend + $(eq plafond_defaut_appareil 300)))
t_attend=$((t_attend + $(eq plafond_marge 120)))
t_attend=$((t_attend + $(eq plafond_sur_valeur_illisible 240)))
# LA POPULATION DE CONTROLE : un VRAI `proof_run.sh` d'un AUTRE item ne retient pas ce juge-ci.
t_attend=$((t_attend + $(eq autreitem_pid_vu 0)))
t_attend=$((t_attend + $(entre autreitem_tue_a_s 45 55)))
# LA DETECTION NE SE MATCHE PAS ELLE-MEME. Argument par argument : 0. Motif sur la ligne
# entiere — ce qu'un `pkill -f` aurait pris : 1. Le defaut evite est CHIFFRE, pas promis.
t_attend=$((t_attend + $(eq selfmatch_par_argument 0)))
t_attend=$((t_attend + $(eq selfmatch_par_motif_de_ligne 1)))
t_attend=$((t_attend + $(eq selfmatch_cible_vivante 1)))
# LE SITE D'APPEL EST DANS LA PRODUCTION, PAS DANS UNE REGION MORTE. Noeud d'AST, pas un grep :
# un grep compterait la docstring.
t_attend=$((t_attend + $(eq site_appels 1)))
t_attend=$((t_attend + $(eq site_definitions 1)))
t_attend=$((t_attend + $(eq site_dans_le_test_post_result 1)))
t_attend=$((t_attend + $(eq site_appel_avant_le_kill 1)))
# ET LE JUGE LE DIT : trois phrases distinctes, toutes nommant un PID.
t_attend=$((t_attend + $(ge journal_dit_attend 2)))
t_attend=$((t_attend + $(ge journal_dit_finie 1)))
t_attend=$((t_attend + $(ge journal_dit_borne 1)))
t_attend=$((t_attend + $(ge journal_nomme_un_pid 4)))

# ================== 3. LA FERMETURE N'EMPORTE PAS UNE COURSE DETACHEE ========================
t_survit=0
# LA MEME FERMETURE, AU MEME INSTANT, SUR DEUX COURSES QUI NE DIFFERENT QUE PAR `setsid`.
t_survit=$((t_survit + $(entre setsid_tue_a_s 45 55)))
t_survit=$((t_survit + $(eq setsid_course_vivante_apres_kill 1)))
t_survit=$((t_survit + $(eq setsid_preuve_presente 1)))
t_survit=$((t_survit + $(entre avant_tue_a_s 45 55)))
t_survit=$((t_survit + $(eq avant_course_vivante_apres_kill 0)))
t_survit=$((t_survit + $(eq avant_preuve_presente 0)))
# ET SOUS LA COUCHE ARMEE, QUAND LA BORNE TRANCHE : la course detachee survit aussi.
t_survit=$((t_survit + $(eq plafond_course_vivante_apres_kill 1)))
t_survit=$((t_survit + $(eq plafond_preuve_presente 1)))
# LA MEME LOI, LUE SUR LES ARCHIVES ET PAS SEULEMENT DANS LE BAC A SABLE : les courses lancees
# par le `run_in_background` de la CLI restent dans le groupe du worker et meurent avec lui ;
# les `setsid`/`nohup` en rechappent.
t_survit=$((t_survit + $(age cout_clibg_perdus 3)))
t_survit=$((t_survit + $(age cout_detache_presents 3)))

# ============================================ 4. LES DEUX BRAS, ET L'ABLATION EST L'ABSENCE ===
t_bras=0
# LE BRAS D'AVANT NE CONTIENT PAS CE QU'IL ABLATE. Un drapeau a zero laisserait vivre les sites
# non gates ; ici la couche n'est pas desarmee, elle n'est pas la.
t_bras=$((t_bras + $(eq bloc_avant_nomme_la_couche 0)))
t_bras=$((t_bras + $(eq bloc_apres_nomme_la_couche 1)))
t_bras=$((t_bras + $(eq bloc_avant_tue 1)))
t_bras=$((t_bras + $(eq bloc_avant_contient_continue 0)))
t_bras=$((t_bras + $(ge bloc_apres_lignes 8)))
# ET CE BRAS EST BIEN LE CODE QUI TOURNAIT LE 16/09 : confronte, ligne a ligne, au blob que
# `lib/ablation_anchor.sh` designe — le dernier commit sans le marqueur. Jamais `HEAD:`.
t_bras=$((t_bras + $(eq avant_derive_egale_le_blob 1)))
t_bras=$((t_bras + $(eq avant_blob_porte_le_marqueur 0)))
t_bras=$((t_bras + $(eq apres_egale_le_blob 0)))
t_bras=$((t_bras + $(ge avant_blob_octets 10000)))
t_bras=$((t_bras + $(ge avant_blob_lignes 3)))
# LES DEUX VERDICTS COTE A COTE, SUR LA MEME COURSE DE 75 s :
#   arme   -> attendu 30 s, preuve PRESENTE  (jambe attend, comptee en t_attend)
#   absent -> ferme a 45 s, preuve ABSENTE   (jambe avant)
t_bras=$((t_bras + $(eq avant_pid_vu 0)))
t_bras=$((t_bras + $(eq avant_holds 0)))
t_bras=$((t_bras + $(eq avant_preuve_octets 0)))
# ET LA FERMETURE A 45 s NE BOUGE PAS QUAND AUCUNE COURSE NE VIT (livrable 4b).
t_bras=$((t_bras + $(eq sanscourse_pid_vu 0)))
t_bras=$((t_bras + $(eq sanscourse_holds 0)))
t_bras=$((t_bras + $(entre sanscourse_tue_a_s 45 55)))
t_bras=$((t_bras + $(eq site_stall_s 45)))

# ======================================= COMBIEN DE TEMOINS ONT VRAIMENT ETE LUS ? ===========
# UNE SOMME A ZERO SUR DES TERMES AVEUGLES EST LE FAUX VERT LE PLUS CHER. La liste ci-dessous
# est le contrat de ce verdict : chaque cle qu'un terme interroge. Une cle absente compte deja
# pour un defaut (les comparateurs rendent 1 sur -1) ; ici on publie COMBIEN ont ete lues, et
# on NOMME celles qui manquent — un total de 0 sur 0 temoin ne prouve rien.
# La recherche se fait par filtrage de motif, SANS TUBE : `grep -q` sous `pipefail` rend 141
# sur un SIGPIPE et la condition devient fausse sur une population qui PORTE le motif.
TEMOINS="apres_egale_le_blob attend_attendu_s attend_course_finie_vue attend_holds
attend_pid_vu attend_preuve_presente attend_tue_a_s attend_vu_par autreitem_pid_vu
autreitem_tue_a_s avant_blob_lignes avant_blob_octets avant_blob_porte_le_marqueur
avant_course_vivante_apres_kill avant_derive_egale_le_blob avant_holds avant_pid_vu
avant_preuve_octets avant_preuve_presente avant_tue_a_s bloc_apres_lignes
bloc_apres_nomme_la_couche bloc_avant_contient_continue bloc_avant_nomme_la_couche
bloc_avant_tue journal_dit_attend journal_dit_borne journal_dit_finie journal_nomme_un_pid
plafond_attendu_s plafond_course_vivante_apres_kill plafond_defaut_appareil plafond_defaut_x86
plafond_item_reel plafond_marge plafond_plafond_atteint plafond_preuve_presente
plafond_sur_valeur_illisible plafond_tue_a_s sanscourse_holds sanscourse_pid_vu
sanscourse_tue_a_s selfmatch_cible_vivante selfmatch_par_argument selfmatch_par_motif_de_ligne
setsid_course_vivante_apres_kill setsid_preuve_presente setsid_tue_a_s site_appel_avant_le_kill
site_appels site_dans_le_test_post_result site_definitions site_stall_s verrou_attendu_s
verroumort_fichier_toujours_la verroumort_vu_par verrouperime_pid_vu verrouperime_tue_a_s
verrou_preuve_presente verrouvif_est_le_dormeur verrouvif_vu_par verrou_vu_par
cout_clibg_perdus cout_detache_presents cout_items_touches cout_journaux_lus cout_perdus
cout_population"
TOUT=$(printf '\n%s\n%s\n' "$BN" "$ARCH")
LUS=0; NTEMOINS=0; MANQUANTS=""
for k in $TEMOINS; do
  NTEMOINS=$((NTEMOINS+1))
  case "$TOUT" in
    *"
$k="*) LUS=$((LUS+1)) ;;
    *) MANQUANTS="${MANQUANTS:+$MANQUANTS+}$k" ;;
  esac
done

TOTAL=$((t_cout + t_attend + t_survit + t_bras + penalty))

# ======================================================================== CE QUI EST PUBLIE ==
# LE BANC A-T-IL MESURE ? Une sortie non vide ne suffit pas : il PUBLIE sa panne, et une panne
# publiee lue comme « il a tourne » serait le mensonge le plus facile de ce fichier.
pub envol_census_ran "$([ "$(n banc_ran)" = 1 ] && echo 1 || echo 0)"
pub envol_banc_panne "$(s banc_panne)"
pub inflight_kill_defects "$TOTAL"
pub inflight_defects_terms \
  "cout$t_cout+attend$t_attend+survit$t_survit+bras$t_bras+penalite$penalty${why:+:$why}"
pub envol_t_cout "$t_cout"
pub envol_t_attend "$t_attend"
pub envol_t_survit "$t_survit"
pub envol_t_bras "$t_bras"
pub envol_witness_penalty "$penalty"
pub envol_terms_measured "$LUS"
pub envol_terms_total "$NTEMOINS"
pub envol_terms_missing "${MANQUANTS:--}"

# 1. LE COUT D'AVANT — la population, sa partition, et la journee que la consigne citait.
for k in cout_journaux_lus cout_population cout_perdus cout_presents cout_sans_verdict \
         cout_items_touches cout_perdus_le_16_09 cout_par_item \
         cout_clibg_perdus cout_clibg_presents cout_detache_perdus cout_detache_presents \
         cout_premierplan_perdus cout_premierplan_presents \
         cout_indetermine_perdus cout_indetermine_presents; do
  pub "envol_$k" "$(a "$k")"
done
# LA POPULATION N'EST PAS VERSIONNEE : un autre arbre ne rendrait pas le meme compte, et le
# dire fait partie du chiffre.
pub envol_cout_population_versionnee \
  "$(git -C "$ROOT" check-ignore -q .autoport/logs && echo 0 || echo 1)"

# 2/3/4. LES BRUTS DU BANC, sous un prefixe a eux : le moissonneur garde la DERNIERE valeur
# d'une cle, et un homonyme ecraserait un terme du verdict.
printf '%s\n' "$BN" | awk -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
   gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "envol_bn_%s=%s\n", k, $0}'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in orchestrator.py lib/inflight_selftest.py lib/ablation_anchor.sh \
         lib/census/harness-judge-waits-for-the-proof-a-worker-left-in-flight.sh; do
  k="envol_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
