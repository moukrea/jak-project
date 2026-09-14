#!/usr/bin/env bash
# census/harness-proof-run-device-deploys-or-refuses-first.sh — LE VERDICT DE L'ITEM.
#
# LANCE PAR `lib/proof_run.sh` (crochet generique `lib/census/<item-id>.sh`), apres la course.
# Il ne peut ecrire aucun champ de `proof.txt` : ni `sha`, ni `frames`, ni `crash`.
#
# CE QU'IL MESURE, DANS L'ORDRE DU LIVRABLE :
#   1. LE COUT D'AVANT, CHIFFRE — publie A PART, jamais dans la somme.
#   2. LA VERIFICATION PRECEDE LA MESURE  -> sb_t2_*
#   3. PLUS DE GARDE PRIVEE               -> sb_t3_*
#   4. LE TEMOIN A DEUX BRAS              -> sb_t4_*, et les verdicts cote a cote.
#
# CE QUE LE COUT D'AVANT EST, ET CE QU'IL N'EST PAS. Le livrable demandait « le compte de
# courses appareil ARCHIVEES dont `device_lib_md5 != local_lib_md5` ». Mesure : 258 paires lues
# sur le disque, ZERO ecart. Ce zero ne dit rien sur le defaut — `proof.txt` est ECRASE a chaque
# course, donc la preuve qui SURVIT est toujours celle de la course reussie, et la course perdue
# ne laisse aucun artefact. La population est vide PAR CONSTRUCTION. Le cout d'avant se compte
# ailleurs, et il se compte pour de vrai : 37 scripts prives de deploiement ecrits sous
# `reports/*/notes/` en 11 jours, dont 28 refont la MEME comparaison de md5 avec sept codes de
# sortie differents. Et le defaut lui-meme est FABRIQUE, pas suppose : le bras d'ABSENCE du banc
# fait ecrire au VRAI producteur une preuve mesuree sur un binaire qui n'est pas le sien.
#
# INCONNU = DEFAUT. Chaque temoin manquant, degenere ou muet AJOUTE au compte : une porte `== 0`
# sur un nettoyage est verte par INACTION si on ne le fait pas.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "sb_census_ran=0"; exit 1; }
AP="$ROOT/.autoport"
cd "$ROOT" || exit 1

RAW=$(bash "$AP/lib/stale_binary_selftest.sh" 2>/dev/null)
g(){ printf '%s\n' "$RAW" | sed -n "s/^$1=//p" | tail -1; }
# -1 = la cle manque. Jamais 0 : un zero passerait une porte `== 0`.
n(){ local v; v=$(g "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }
pub(){ printf '%s=%s\n' "$1" "${2:--}"; }

DEFAUTS=0
faute(){ DEFAUTS=$((DEFAUTS + $1)); }

# ================================================================ 0. LE BANC A-T-IL TOURNE ===
BANC=$(n selftest_ran); COURUS=$(n selftest_arms_courus); MONTES=$(n selftest_arms_montes)
pub sb_banc_ran "$BANC"
pub sb_banc_arms_montes "$MONTES"
pub sb_banc_arms_courus "$COURUS"
t_banc=0
[ "$BANC" = 1 ] || t_banc=$((t_banc + 1))
[ "$COURUS" = 4 ] || t_banc=$((t_banc + 1))
pub sb_banc_incomplet "$t_banc"; faute "$t_banc"

# ==================================================== LES QUATRE VERDICTS, COTE A COTE =======
# On publie ce que CHAQUE bras a fait, avant d'en juger un seul. Un verdict sans sa table est
# une affirmation ; avec elle, n'importe qui refait le raisonnement.
for a in egaux perime deploye vieux; do
  pub "sb_arm_${a}_rc"          "$(g "arm_${a}_rc")"
  pub "sb_arm_${a}_decision"    "$(g "arm_${a}_decision")"
  pub "sb_arm_${a}_raison"      "$(g "arm_${a}_raison")"
  pub "sb_arm_${a}_amorce"      "$(g "arm_${a}_started")"
  pub "sb_arm_${a}_installs"    "$(g "arm_${a}_installs")"
  pub "sb_arm_${a}_preuve"      "$(g "arm_${a}_proof")"
  pub "sb_arm_${a}_preuve_precedente" "$(g "arm_${a}_preuve_precedente")"
  pub "sb_arm_${a}_local_md5"   "$(g "arm_${a}_local_md5")"
  pub "sb_arm_${a}_dev_md5"     "$(g "arm_${a}_dev_md5_final")"
  pub "sb_arm_${a}_mesure_sur_perime" "$(g "arm_${a}_mesure_sur_perime")"
done

# ============================================ 2. LA VERIFICATION PRECEDE LA MESURE ===========
# LA GRANDEUR CENTRALE. Aucun des trois bras que la garde protege ne doit avoir MESURE sur un
# binaire qui n'est pas celui du build. Le bras `vieux` n'est pas compte ici : c'est le temoin
# d'AVANT, et il DOIT valoir 1 (terme 4).
t2_mes=0
for a in egaux perime deploye; do
  v=$(n "arm_${a}_mesure_sur_perime")
  case "$v" in 0) ;; *) t2_mes=$((t2_mes + 1)) ;; esac
done
pub sb_t2_mesures_sur_perime "$t2_mes"; faute "$t2_mes"

# LE REFUS : son code, son moment, et ce qu'il n'a pas detruit.
t2_ref=0
[ "$(n arm_perime_rc)" = 6 ] || t2_ref=$((t2_ref + 1))
[ "$(g arm_perime_decision)" = refus ] || t2_ref=$((t2_ref + 1))
[ "$(n arm_perime_gate_rc)" = 6 ] || t2_ref=$((t2_ref + 1))
pub sb_t2_refus_manquant "$t2_ref"; faute "$t2_ref"

# « AVANT L'APPAREIL » SE MESURE SUR L'AMORCAGE, pas sur une intention : le faux appareil note
# le `am start`. Un refus qui tombe apres lui a deja paye le prix qu'on voulait eviter.
t2_tard=0
[ "$(n arm_perime_started)" = 0 ] || t2_tard=$((t2_tard + 1))
pub sb_t2_refus_apres_amorcage "$t2_tard"; faute "$t2_tard"

# LA PREUVE DE LA COURSE PRECEDENTE EST INTACTE. C'est la difference entre un refus et une
# destruction : un rc distinct qui efface quand meme la preuve d'hier ne vaut pas mieux.
t2_det=0
[ "$(g arm_perime_preuve_precedente)" = intacte ] || t2_det=$((t2_det + 1))
pub sb_t2_refus_a_detruit "$t2_det"; faute "$t2_det"

# LE DEPLOIEMENT : quand un APK du CONSTRUCTEUR porte le binaire local, on LIVRE au lieu de
# refuser — et la course mesure ensuite sur le bon binaire.
t2_dep=0
[ "$(g arm_deploye_decision)" = deploye ] || t2_dep=$((t2_dep + 1))
[ "$(n arm_deploye_installs)" -ge 1 ] 2>/dev/null || t2_dep=$((t2_dep + 1))
[ "$(n arm_deploye_proof)" = 1 ] || t2_dep=$((t2_dep + 1))
[ "$(g arm_deploye_dev_md5_final)" = "$(g arm_deploye_local_md5)" ] || t2_dep=$((t2_dep + 1))
pub sb_t2_deploiement_manquant "$t2_dep"; faute "$t2_dep"

# UNE GARDE QUI BLOQUE UNE COURSE SAINE N'EST PAS UNE GARDE. Le bras `egaux` doit MESURER, et
# la preuve doit porter le temoin que la verification a bien eu lieu AVANT.
t2_sain=0
[ "$(n arm_egaux_rc)" = 0 ] || t2_sain=$((t2_sain + 1))
[ "$(n arm_egaux_proof)" = 1 ] || t2_sain=$((t2_sain + 1))
[ "$(n arm_egaux_started)" = 1 ] || t2_sain=$((t2_sain + 1))
[ "$(n arm_egaux_checked)" = 1 ] || t2_sain=$((t2_sain + 1))
pub sb_t2_course_saine_bloquee "$t2_sain"; faute "$t2_sain"

# ================================================= 4. LE TEMOIN D'AVANT, FABRIQUE ============
# LE BRAS D'ABSENCE. La couche n'est pas dans ce `proof_run.sh` : le bloc en a ete RETIRE. Il
# doit donc mesurer 400 s sur le mauvais binaire, exactement comme le harnais le faisait hier.
# Une ablation qui ne retire AUCUNE ligne serait vide, et un zero s'y lirait « rien ne se perd »
# alors qu'il voudrait dire « personne n'a regarde ».
t4=0
[ "$(n arm_vieux_bloc_retire_lignes)" -ge 10 ] 2>/dev/null || t4=$((t4 + 1))
[ "$(n arm_vieux_mesure_sur_perime)" = 1 ] || t4=$((t4 + 1))
[ "$(n arm_vieux_started)" = 1 ] || t4=$((t4 + 1))
[ "$(g arm_vieux_decision)" = absent ] || t4=$((t4 + 1))
pub sb_t4_temoin_avant_absent "$t4"; faute "$t4"
pub sb_t4_ablation_lignes_retirees "$(g arm_vieux_bloc_retire_lignes)"

# ================================================= 3. PLUS DE GARDE PRIVEE ===================
# Le detecteur tourne DEUX fois, sur le MEME code : sur l'arbre livre, et sur une copie jetable
# de la MEME population ou l'on a seme DEUX controles — une garde posterieure a la livraison (a
# compter) et une anterieure (a laisser). Sans le controle positif, « zero garde privee neuve »
# se lirait pareil qu'un detecteur aveugle.
GP=$(python3 - "$ROOT" <<'PY' 2>/dev/null
import os, re, shutil, subprocess, sys, tempfile
root = sys.argv[1]

# L'INSTANT DE LIVRAISON : le COMMIT qui AJOUTE la garde partagee — une empreinte de contenu,
# pas un chemin. A defaut de commit (pas encore versionnee), on le DIT et on retombe sur le
# mtime du fichier, jamais en silence.
det = '.autoport/lib/device_binary_gate.sh'
src, epoch, commit = 'commit', -1, '-'
r = subprocess.run(['git', '-C', root, 'log', '--diff-filter=A', '--format=%ct %H', '--', det],
                   capture_output=True, text=True)
lignes = [l for l in (r.stdout or '').splitlines() if l.strip()]
if lignes:
    champs = lignes[-1].split()
    epoch, commit = int(champs[0]), champs[1][:12]
else:
    src = 'mtime'
    p = os.path.join(root, det)
    if os.path.exists(p):
        epoch = int(os.path.getmtime(p))
print('sb_t3_livraison_source=%s' % src)
print('sb_t3_livraison_commit=%s' % commit)
print('sb_t3_livraison_epoch=%d' % epoch)

# CE QU'EST UNE GARDE PRIVEE : le GESTE, pas le nom. Un script pose sous `notes/` d'un item qui
# COMPARE deux empreintes de binaire. On ne cherche pas un libelle — chacune des 28 trouvees en
# porte un different — on cherche la comparaison.
NOM = re.compile(r'(deploy|push)', re.I)
CMP = re.compile(r'(md5sum|hashlib\.md5)')
ECART = re.compile(r'(!=|\bne\b|\bdiffer|"\$L" = "\$D"|==)')

def detecte(reports, epoch):
    """(population, gardes, apres_livraison, liste) — LE MEME code pour les deux appels."""
    pop = gardes = apres = 0
    liste = []
    for it in sorted(os.listdir(reports)) if os.path.isdir(reports) else []:
        notes = os.path.join(reports, it, 'notes')
        for dp, _dn, fn in os.walk(notes):
            for f in fn:
                if not f.endswith(('.sh', '.py')) or not NOM.search(f):
                    continue
                p = os.path.join(dp, f)
                pop += 1
                try:
                    t = open(p, encoding='utf-8', errors='replace').read()
                except OSError:
                    continue
                if not (CMP.search(t) and ECART.search(t)):
                    continue
                gardes += 1
                # LES DEUX COTES EN SECONDES ENTIERES, et l'EGALITE COMPTEE COMME APRES : le
                # sens de l'erreur est choisi CONTRE la porte. Une garde posee dans la seconde
                # de la livraison entre dans le compte, elle ne peut pas verdir par arrondi.
                if epoch >= 0 and int(os.path.getmtime(p)) >= epoch:
                    apres += 1
                    liste.append(os.path.relpath(p, reports))
    return pop, gardes, apres, liste

reports = os.path.join(root, '.autoport', 'reports')
pop, gardes, apres, liste = detecte(reports, epoch)
print('sb_t3_population=%d' % pop)
print('sb_t3_gardes_privees=%d' % gardes)
print('sb_t3_gardes_privees_apres=%d' % apres)
print('sb_t3_liste_apres=%s' % (','.join(liste) or '-'))

# ------------------------------------- LE CONTROLE POSITIF, SUR LA MEME POPULATION -----------
# On RECOPIE les gardes reelles (mtime preserve) dans un arbre jetable, puis on seme DEUX
# controles : un POSTERIEUR a la livraison, qui doit etre compte, et un ANTERIEUR, qui doit
# etre laisse. Un detecteur qui rend 0 sur les deux est aveugle ; un qui rend 2 ne date rien.
bac = tempfile.mkdtemp(prefix='gardes-ctrl-')
essai = 0
try:
    for it in sorted(os.listdir(reports)) if os.path.isdir(reports) else []:
        notes = os.path.join(reports, it, 'notes')
        for dp, _dn, fn in os.walk(notes):
            for f in fn:
                if f.endswith(('.sh', '.py')) and NOM.search(f):
                    # LE CHEMIN RELATIF EST CONSERVE. Une copie a plat ecrase les homonymes :
                    # `lighting-hdr` porte 22 `build-deploy.sh` dans 22 sous-dossiers, et la
                    # population de controle tombait de 37 a 13 sans que rien ne le dise.
                    rel = os.path.relpath(os.path.join(dp, f), reports)
                    cible = os.path.join(bac, rel)
                    os.makedirs(os.path.dirname(cible), exist_ok=True)
                    shutil.copy2(os.path.join(dp, f), cible)
    d = os.path.join(bac, 'zz-controle', 'notes')
    os.makedirs(d, exist_ok=True)
    corps = 'md5sum x\nif [ "$A" != "$B" ]; then exit 4; fi\n'
    ap_ = os.path.join(d, 'deploy-apres-livraison.sh')
    av_ = os.path.join(d, 'deploy-avant-livraison.sh')
    open(ap_, 'w', encoding='utf-8').write(corps)
    open(av_, 'w', encoding='utf-8').write(corps)
    os.utime(ap_, (epoch + 10, epoch + 10))
    os.utime(av_, (epoch - 100000, epoch - 100000))
    cpop, cgardes, capres, cliste = detecte(bac, epoch)
    print('sb_t3_ctrl_population=%d' % cpop)
    print('sb_t3_ctrl_gardes=%d' % cgardes)
    print('sb_t3_ctrl_apres=%d' % capres)
    print('sb_t3_ctrl_vu=%d' % (1 if any('deploy-apres-livraison' in x for x in cliste) else 0))
    print('sb_t3_ctrl_laisse=%d' % (0 if any('deploy-avant-livraison' in x for x in cliste) else 1))
    essai = 1
    print('sb_t3_ctrl_meme_population=%d' % (1 if cpop == pop + 2 else 0))
finally:
    shutil.rmtree(bac, ignore_errors=True)
print('sb_t3_ctrl_ran=%d' % essai)
PY
)
printf '%s\n' "$GP"
gp(){ printf '%s\n' "$GP" | sed -n "s/^$1=//p" | tail -1; }
gpn(){ local v; v=$(gp "$1"); case "$v" in ''|*[!0-9-]*) echo -1 ;; *) echo "$v" ;; esac; }

t3=$(gpn sb_t3_gardes_privees_apres)
case "$t3" in ''|-*) t3=1 ;; esac
faute "$t3"

# LE DETECTEUR EST-IL SEULEMENT CAPABLE DE VOIR UNE GARDE NEUVE ?
t3c=0
[ "$(gpn sb_t3_ctrl_ran)" = 1 ] || t3c=$((t3c + 1))
[ "$(gpn sb_t3_ctrl_apres)" = 1 ] || t3c=$((t3c + 1))
[ "$(gpn sb_t3_ctrl_vu)" = 1 ] || t3c=$((t3c + 1))
[ "$(gpn sb_t3_ctrl_laisse)" = 1 ] || t3c=$((t3c + 1))
[ "$(gpn sb_t3_ctrl_meme_population)" = 1 ] || t3c=$((t3c + 1))
pub sb_t3_detecteur_aveugle "$t3c"; faute "$t3c"

# ================================================= 1. LE COUT D'AVANT, CHIFFRE, A PART =======
# Il ne rentre PAS dans la somme : c'est ce que le defaut COUTAIT, pas ce qu'il coute encore.
pub sb_avant_gardes_privees_scripts "$(g avant_gardes_privees_scripts)"
pub sb_avant_gardes_privees_md5 "$(g avant_gardes_privees_md5)"
pub sb_avant_codes_de_sortie_distincts "$(g avant_gardes_privees_codes_distincts)"
# LE RECENSEMENT DE DISQUE ET SON DENOMINATEUR. Zero ecart sur 258 paires : c'est une propriete
# du PRODUCTEUR (proof.txt est ecrase a chaque course), pas une absence de defaut. Publie tel
# quel, avec la raison, pour que personne ne le relise comme une porte verte.
pub sb_avant_disque_paires "$(g disque_paires_lues)"
pub sb_avant_disque_ecarts "$(g disque_ecarts)"
pub sb_avant_disque_vide_par_construction 1
# LE DEFAUT, FABRIQUE ET MESURE : le bras d'ABSENCE a fait ecrire au VRAI producteur une preuve
# mesuree sur un binaire qui n'etait pas le sien. C'est le « non nul » que le disque ne donne pas.
pub sb_avant_fabrique_mesures_perimees "$(g arm_vieux_mesure_sur_perime)"

# ================================================= LE DENOMINATEUR DE LA GARDE ===============
# Sur combien de courses la garde a-t-elle decide, et quoi ? Le registre est append-only et il
# est ecrit a CHAQUE passage, refus compris : un registre qu'on n'ecrit que dans le cas heureux
# ne peut pas servir de denominateur. Sur une preuve x86 il est vide, et on le dit.
REG="$AP/logs/device-binary-gate.tsv"
if [ -s "$REG" ]; then
  pub sb_registre_courses "$(grep -c . "$REG")"
  pub sb_registre_refus "$(awk -F'\t' '$4=="refus"' "$REG" | grep -c . || echo 0)"
else
  pub sb_registre_courses 0
  pub sb_registre_refus 0
fi
pub sb_courses_verifiees_avant_mesure \
    "$(printf '%s\n' "$RAW" | grep -cE '^arm_(egaux|perime|deploye)_decision=(identique|deploye|refus)$')"

# ===================================================================== LA SOMME ==============
pub stale_binary_runs "$DEFAUTS"
pub sb_census_ran 1
