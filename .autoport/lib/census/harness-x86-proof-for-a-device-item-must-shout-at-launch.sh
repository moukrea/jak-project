#!/usr/bin/env bash
# census/harness-x86-proof-for-a-device-item-must-shout-at-launch.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Sa sortie `cle=valeur` rejoint celle du moteur. Il n'ecrit aucun champ de `proof.txt` : ni
# `sha`, ni `frames`, ni les `proof_census_*` qui disent qu'il a tourne — ils sortent de la
# machine, et elle JETTE toute ligne `proof_*` venue d'ici.
#
# LES QUATRE POINTS DU LIVRABLE, DANS L'ORDRE :
#   1. LE COUT D'AVANT, CHIFFRE sur les verdicts archives : ceux dont un constat est
#      « l'item exige l'appareil, la preuve est en source=x86 », par item et par date  -> t_cout
#   2. L'AVERTISSEMENT EXISTE : il sort AVANT le moteur, il nomme le refus a venir et il dit
#      quoi faire — refaire la derniere course en `device`                      -> t_avert
#   3. LE TERME, FABRIQUE DES DEUX COTES : sans le correctif la course n'est pas prevenue,
#      avec, elle l'est                                                          -> t_terme
#   4. LE CONTROLE NEGATIF : un item SANS `device=1` publie 0 et n'ecrit pas un mot -> t_ctrl
#   +  LE SITE D'APPEL est dans la production et il est AVANT le moteur           -> t_site
#
# DEUX SOURCES, ET ELLES NE SE RECOUVRENT PAS. `lib/x86_device_warning_selftest.sh` leve le bloc
# de decision de `proof_run.sh` entre ses marqueurs et le fait tourner sur de VRAIS items du
# backlog, dans les deux bras ; le recensement d'archive, lui, ne mesure que ce qui a DEJA eu
# lieu. L'un dit que le correctif marche, l'autre dit combien le defaut a coute.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte, et `-1` (cle
# absente) ne passe aucune porte `== 0`. Sans cette polarite une porte `== 0` serait verte par
# INACTION : il suffirait que rien ne tourne.
#
# AUCUNE LECTURE D'HORODATAGE DE FICHIER. Les dates viennent du CONTENU des journaux d'essai
# (`attempt_start.started_at`), pas d'un `stat` : un mtime de journal dit quand la machine l'a
# touche, pas quand l'essai a eu lieu.
set -uo pipefail
export LC_ALL=C

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "x86_warn_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

# LE MOISSONNEUR DE proof_run.sh NE GARDE QUE `^cle=valeur$` SANS ESPACE, et jette une valeur
# VIDE. On colle les espaces ICI, au point de publication, et le vide devient `-`.
pub(){ printf '%s=%s\n' "$1" "$(printf '%s' "${2:--}" | tr -s '[:space:]' '_')"; }

# ==================================================================== LE BANC, DEUX BRAS =====
BN=$(timeout -k 15 300 bash "$AP/lib/x86_device_warning_selftest.sh" 2>/dev/null)
s(){ printf '%s\n' "$BN" | sed -n "s/^$1=//p" | tail -1; }
n(){ local v; v=$(s "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

penalty=0; why=""
faute(){ penalty=$((penalty+1)); why="${why:+$why+}$1"; }
eq(){ [ "$(n "$1")" = "$2" ] && echo 0 || echo 1; }
ge(){ local v; v=$(n "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
lt(){ local a b; a=$(n "$1"); b=$(n "$2")
      [ "$a" != -1 ] && [ "$b" != -1 ] && [ "$a" -lt "$b" ] 2>/dev/null && echo 0 || echo 1; }

[ -n "$BN" ] || faute banc-muet
[ "$(n banc_ran)" = 1 ] || faute banc-n-a-pas-tourne

# ================== 1. LE COUT D'AVANT, LU SUR LES VERDICTS ARCHIVES DE CE JUGE ==============
# La population n'est PAS versionnee (`.gitignore` exclut `.autoport/logs/`) : elle vit sur
# cette machine et nulle part ailleurs. Le denominateur — le nombre de verdicts LUS — est publie
# a cote du compte : un plancher calibre sur une population vide rendrait vert par cecite.
ARCH=$(python3 - <<'PY' 2>/dev/null
import glob, json, os, re, sys
from collections import Counter
sys.path.insert(0, ".autoport/lib/census")
import anchor as A

# LA PHRASE EST CELLE DE `validators/generic.sh`, ET ON VERIFIE QU'ELLE Y EST ENCORE. DIRECTIVES
# 5 interdit de le modifier pour qu'il l'expose : on l'EPINGLE, et le jour ou il reformule
# l'ecart se voit au lieu de rendre un zero silencieux.
PHRASE = "l'item exige l'appareil, la preuve est en source="
juge = open('.autoport/validators/generic.sh', encoding='utf-8', errors='replace').read()
print('cout_phrase_dans_le_juge=%d' % A.ws_count(juge, PHRASE))

def date_de(item, num):
    # LA DATE SORT DU CONTENU DU JOURNAL D'ESSAI, jamais d'un horodatage de fichier.
    p = '.autoport/logs/%s/attempt-%s.jsonl' % (item, num)
    try:
        with open(p, encoding='utf-8', errors='replace') as fh:
            for ligne in fh:
                try:
                    ev = json.loads(ligne)
                except Exception:
                    continue
                if ev.get('event') == 'attempt_start' and ev.get('started_at'):
                    return str(ev['started_at'])[:10]
                break
    except OSError:
        pass
    return '?'

fichiers = sorted(glob.glob('.autoport/logs/*/validator-*.txt'))
print('cout_journaux_lus=%d' % len(fichiers))

generic = echecs = 0
touches = []
par_item = Counter(); par_jour = Counter(); par_source = Counter()
for p in fichiers:
    txt = open(p, encoding='utf-8', errors='replace').read()
    # LA POPULATION EST CELLE DE CE JUGE-CI : les journaux des validateurs SUPPRIMES depuis
    # (phases numerotees, `RESULT: PASS`) ne portent pas ce critere et noieraient le taux.
    if 'constat(s) ci-dessus' not in txt and not re.search(r'\[\S+ ok\] source=', txt):
        continue
    generic += 1
    refus = [l for l in txt.splitlines() if re.search(r'\[\S+ FAIL\]', l)]
    if refus:
        echecs += 1
    hit = [l for l in refus if PHRASE in l]
    if not hit:
        continue
    item = os.path.basename(os.path.dirname(p))
    num = re.sub(r'\D', '', os.path.basename(p))
    jour = date_de(item, num)
    src = hit[0].split(PHRASE, 1)[1].strip() or '?'
    par_item[item] += 1
    par_jour[jour] += 1
    par_source[src] += 1
    touches.append('%s:%s:%s' % (item, num, jour))

print('cout_generic=%d' % generic)
print('cout_echecs=%d' % echecs)
print('cout_verdicts=%d' % len(touches))
print('cout_items=%d' % len(par_item))
print('cout_jours=%d' % len(par_jour))
print('cout_hud_eco_gauge=%d' % par_item.get('hud-eco-gauge', 0))
print('cout_part_des_echecs_pour_mille=%d' % (len(touches) * 1000 // echecs if echecs else -1))
print('cout_par_item=%s' % ('+'.join('%s:%d' % kv for kv in sorted(par_item.items())) or '-'))
print('cout_par_jour=%s' % ('+'.join('%s:%d' % kv for kv in sorted(par_jour.items())) or '-'))
print('cout_par_source=%s' % ('+'.join('%s:%d' % kv for kv in sorted(par_source.items())) or '-'))
print('cout_liste=%s' % ('+'.join(sorted(touches)) or '-'))
# LE CHIFFRE QUE LE CONTRAT ANNONCE : « au moins 2 sur hud-eco-gauge les 21-22/09 ». On publie
# ce qu'on MESURE a cote, plutot que de le fabriquer.
recents = sum(v for k, v in par_jour.items() if k in ('2026-09-21', '2026-09-22'))
print('cout_21_22_septembre=%d' % recents)
PY
)
a(){ printf '%s\n' "$ARCH" | sed -n "s/^$1=//p" | tail -1; }
an(){ local v; v=$(a "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
age(){ local v; v=$(an "$1"); [ "$v" != -1 ] && [ "$v" -ge "$2" ] 2>/dev/null && echo 0 || echo 1; }
aeq(){ [ "$(an "$1")" = "$2" ] && echo 0 || echo 1; }
[ -n "$ARCH" ] || faute recensement-d-archive-muet

t_cout=0
# LE DENOMINATEUR D'ABORD : un plancher calibre sur une population vide est un faux vert.
t_cout=$((t_cout + $(age cout_journaux_lus 100)))
t_cout=$((t_cout + $(age cout_generic 50)))
t_cout=$((t_cout + $(age cout_echecs 20)))
# LE COUT, NON NUL, ET SUR PLUSIEURS ITEMS : un defaut qui n'aurait frappe qu'une fois ne
# justifierait pas qu'on touche au producteur de preuve.
t_cout=$((t_cout + $(age cout_verdicts 2)))
t_cout=$((t_cout + $(age cout_items 2)))
# CELUI QUI A PAYE, NOMME : au moins les deux essais de `hud-eco-gauge` que la consigne cite.
t_cout=$((t_cout + $(age cout_hud_eco_gauge 2)))
# ET LA PHRASE EPINGLEE EST ENCORE CELLE DU JUGE. Garde d'EGALITE : s'il reformule, cette porte
# rougit au lieu de compter zero sur un vocabulaire mort.
t_cout=$((t_cout + $(aeq cout_phrase_dans_le_juge 1)))

# ========================= 2. L'AVERTISSEMENT EXISTE, ET IL DIT QUOI FAIRE ===================
t_avert=0
# AUCUNE JAMBE MUETTE, sur les cinq items a critere device.
t_avert=$((t_avert + $(ge x86_unwarned_denominateur 5)))
t_avert=$((t_avert + $(eq banc_device_muets 0)))
# LE MOT DIT QUOI FAIRE : la course a refaire, en toutes lettres, avec son mode.
t_avert=$((t_avert + $(eq banc_device_sans_remede 0)))
# ET IL NOMME LE REFUS QUI VIENT, mot pour mot celui du juge.
t_avert=$((t_avert + $(eq banc_device_sans_constat 0)))
# LA CLE VOISINE PUBLIE LE CRITERE LU : « pas prevenu » et « critere illisible » ne se
# confondent pas.
t_avert=$((t_avert + $(eq banc_device_critere_non_publie 0)))
# LES ITEMS CHOISIS SONT BIEN CEUX QU'ON CROIT, releve par la source du juge.
t_avert=$((t_avert + $(eq banc_critere_inattendu 0)))

# ===================== 3. LE TERME, FABRIQUE DES DEUX COTES ==================================
t_terme=0
# AVEC LE CORRECTIF : aucune course x86 sur item device ne part sans son avertissement.
t_terme=$((t_terme + $(eq x86_unwarned_runs_after 0)))
# SANS LUI : TOUTES partent sans. Un instrument qui rendrait 0 aux deux bras ne mesurerait rien.
t_terme=$((t_terme + $(ge x86_unwarned_runs_before 5)))
t_terme=$((t_terme + $([ "$(n x86_unwarned_runs_before)" = "$(n x86_unwarned_before_denominateur)" ] \
                       && echo 0 || echo 1)))
# LE BRAS D'AVANT EST L'ABSENCE DE LA COUCHE, pas un drapeau a zero : la region y est VIDE.
t_terme=$((t_terme + $(eq bloc_avant_lignes 0)))
t_terme=$((t_terme + $(eq ancre_blob_porte_le_marqueur 0)))
# ET C'EST UN VRAI ETAT D'AVANT, pas un fichier tronque : le blob entier de `proof_run.sh`.
t_terme=$((t_terme + $(ge ancre_blob_octets 50000)))
t_terme=$((t_terme + $(ge bloc_apres_lignes 20)))

# ============================ 4. LE CONTROLE NEGATIF, LES DEUX COTES =========================
t_ctrl=0
# UN ITEM SANS `device=1` : la cle est publiee A ZERO, et PAS UN MOT au journal.
t_ctrl=$((t_ctrl + $(ge banc_nondevice_denominateur 5)))
t_ctrl=$((t_ctrl + $([ "$(n banc_nondevice_cle_a_zero)" = "$(n banc_nondevice_denominateur)" ] \
                     && echo 0 || echo 1)))
t_ctrl=$((t_ctrl + $(eq banc_nondevice_mots 0)))
# ET LE MEME ITEM A CRITERE device, LANCE EN MODE device : la course SERA jugee, donc rien.
t_ctrl=$((t_ctrl + $(ge banc_devicemode_denominateur 5)))
t_ctrl=$((t_ctrl + $([ "$(n banc_devicemode_cle_a_zero)" = "$(n banc_devicemode_denominateur)" ] \
                     && echo 0 || echo 1)))
t_ctrl=$((t_ctrl + $(eq banc_devicemode_mots 0)))

# =================== + LE SITE D'APPEL : DANS LA PRODUCTION, ET AVANT LA DEPENSE =============
t_site=0
t_site=$((t_site + $(eq site_occurrences_debut 1)))
t_site=$((t_site + $(eq site_occurrences_fin 1)))
t_site=$((t_site + $(eq site_publie_la_cle 1)))
# AVANT LE MOTEUR, AVANT L'HORODATAGE DE DEPART, AVANT L'ECRITURE DE LA PREUVE. Un mot pose
# apres le moteur previendrait apres la depense.
t_site=$((t_site + $(lt site_ligne_fin site_ligne_started)))
t_site=$((t_site + $(lt site_ligne_fin site_ligne_moteur)))
t_site=$((t_site + $(lt site_ligne_fin site_ligne_ecriture_preuve)))
# A LA PREMIERE LIGNE : aucune ligne de journal inconditionnelle ne le precede.
t_site=$((t_site + $(eq site_logs_inconditionnels_avant 0)))
# ET LE JUGE N'A PAS ETE ASSOUPLI : sa ligne de refus est intacte (hors perimetre, mesure).
t_site=$((t_site + $(eq juge_refuse_toujours 1)))
t_site=$((t_site + $(eq juge_porte_le_constat 1)))

# ======================================= COMBIEN DE TEMOINS ONT VRAIMENT ETE LUS ? ===========
# UNE SOMME A ZERO SUR DES TERMES AVEUGLES EST LE FAUX VERT LE PLUS CHER. La liste ci-dessous
# est le contrat de ce verdict : chaque cle qu'un terme interroge. Une cle absente compte deja
# pour un defaut (les comparateurs rendent 1 sur -1) ; ici on publie COMBIEN ont ete lues et on
# NOMME celles qui manquent. La recherche se fait par filtrage de motif, SANS TUBE : `grep -q`
# sous `pipefail` rend 141 sur un SIGPIPE et la condition devient fausse sur une population qui
# PORTE le motif.
TEMOINS="banc_ran bloc_apres_lignes bloc_avant_lignes ancre_blob_octets
ancre_blob_porte_le_marqueur x86_unwarned_denominateur x86_unwarned_runs_after
x86_unwarned_runs_before x86_unwarned_before_denominateur banc_device_muets
banc_device_sans_remede banc_device_sans_constat banc_device_critere_non_publie
banc_critere_inattendu banc_nondevice_denominateur banc_nondevice_cle_a_zero
banc_nondevice_mots banc_devicemode_denominateur banc_devicemode_cle_a_zero
banc_devicemode_mots site_occurrences_debut site_occurrences_fin site_publie_la_cle
site_ligne_fin site_ligne_started site_ligne_moteur site_ligne_ecriture_preuve
site_logs_inconditionnels_avant juge_refuse_toujours juge_porte_le_constat
cout_journaux_lus cout_generic cout_echecs cout_verdicts cout_items cout_hud_eco_gauge
cout_phrase_dans_le_juge cout_jours"
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

TOTAL=$((t_cout + t_avert + t_terme + t_ctrl + t_site + penalty))

# ======================================================================== CE QUI EST PUBLIE ==
pub x86_proof_unwarned "$TOTAL"
pub x86_warn_terms \
  "cout$t_cout+avert$t_avert+terme$t_terme+ctrl$t_ctrl+site$t_site+penalite$penalty${why:+:$why}"
pub x86_warn_census_ran "$([ "$(n banc_ran)" = 1 ] && echo 1 || echo 0)"
pub x86_warn_t_cout "$t_cout"
pub x86_warn_t_avert "$t_avert"
pub x86_warn_t_terme "$t_terme"
pub x86_warn_t_ctrl "$t_ctrl"
pub x86_warn_t_site "$t_site"
pub x86_warn_witness_penalty "$penalty"
pub x86_warn_terms_measured "$LUS"
pub x86_warn_terms_total "$NTEMOINS"
pub x86_warn_terms_missing "${MANQUANTS:--}"

# 1. LE COUT D'AVANT — la population, sa partition, la liste nommee.
for k in cout_phrase_dans_le_juge cout_journaux_lus cout_generic cout_echecs cout_verdicts \
         cout_items cout_jours cout_hud_eco_gauge cout_part_des_echecs_pour_mille \
         cout_par_item cout_par_jour cout_par_source cout_liste cout_21_22_septembre; do
  pub "x86_warn_$k" "$(a "$k")"
done
# LA POPULATION N'EST PAS VERSIONNEE : un autre arbre ne rendrait pas le meme compte, et le
# dire fait partie du chiffre.
pub x86_warn_cout_population_versionnee \
  "$(git -C "$ROOT" check-ignore -q .autoport/logs && echo 0 || echo 1)"

# 2/3/4. LES BRUTS DU BANC, sous un prefixe a eux : le moissonneur garde la DERNIERE valeur
# d'une cle, et un homonyme ecraserait un terme du verdict.
printf '%s\n' "$BN" | awk -F= '/^[a-z_][a-z0-9_]*=/ {k=$1; sub(/^[^=]*=/,"",$0);
   gsub(/[[:space:]]+/,"_",$0); if($0=="") $0="-"; printf "x86_warn_bn_%s=%s\n", k, $0}'

# LES OCTETS JUGES. Un chemin n'est pas une provenance.
for f in lib/proof_run.sh lib/x86_device_warning_selftest.sh lib/ablation_anchor.sh \
         lib/verdict_sources.sh validators/generic.sh \
         lib/census/harness-x86-proof-for-a-device-item-must-shout-at-launch.sh; do
  k="x86_warn_sha_$(printf '%s' "$f" | tr -c 'A-Za-z0-9_' '_')"
  pub "$k" "$(sha256sum "$AP/$f" 2>/dev/null | cut -c1-16)"
done
