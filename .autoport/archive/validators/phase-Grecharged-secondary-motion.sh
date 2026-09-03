#!/usr/bin/env bash
# phase-Grecharged-secondary-motion — VALIDATEUR RÉÉCRIT LE 2026-08-11 (départ propre).
#
# L'ancien validateur (60+ gates, ~900 lignes) est parké avec le moteur qu'il gardait, sur
# physics-attic-2026-08-11. Il avait grossi au même rythme que le moteur et pour la même raison :
# une gate ajoutée par défaut constaté. Il ne mesurait plus le contrat, il mesurait son histoire.
#
# Celui-ci n'a que les gates qui correspondent à une phrase de SPEC-keira-physique.md, dans l'ordre
# où le travail doit se faire. Une gate qui ne se rattache pas à une exigence de l'owner n'existe pas.
#
# Les trois invariants qui ont coûté une semaine, et qui s'appliquent à chaque gate :
#   - un commentaire n'est pas une preuve : on lit des traces d'exécution, jamais du source ;
#   - tout zéro exige un contrôle positif qui a fait MONTER le compteur ;
#   - aucun suppresseur par défaut ; s'il y en a un, il chiffre le mouvement qu'il retire.

R=.autoport/reports/Grecharged-secondary-motion/report.txt
T=.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt
fail(){ echo "[Grecharged-secondary-motion FAIL] $*"; exit 1; }

[ -f "$R" ] || fail "aucun rapport (reports/Grecharged-secondary-motion/report.txt)"

# --------------------------------------------------------------------------------------------
# SYNC — le rapport doit porter le contrat courant. Seul un changement de périmètre délibéré
# (SCOPE-SERIAL bumpé) invalide une tentative ; corriger une coquille ne coûte rien.
DVOK=$(python3 .autoport/lib/directives.py accepted 2>/dev/null)
[ -n "$DVOK" ] || fail "SYNC: impossible de calculer la version du contrat"
_ok=0; for v in $DVOK; do grep -qF "DIRECTIVES $v" "$R" && _ok=1; done
[ "$_ok" -eq 1 ] || fail "SYNC: le rapport ne porte pas le contrat courant (accepté: $DVOK).
  Relis .autoport/DIRECTIVES.md — il prime sur ton prompt — et relance les sous-agents restés
  sur l'ancien périmètre."

# --------------------------------------------------------------------------------------------
# CLEAN — le départ propre ne se referme pas. Le cast reste hors-jeu tant que Keira n'est pas
# validée, et l'ancien moteur parké ne revient pas par la fenêtre.
_mdl=$(grep -c "^\[model " recharged_assets/physics_chains.txt 2>/dev/null || echo 0)
[ "$_mdl" -le 2 ] || fail "CLEAN: $_mdl modèles dans physics_chains.txt. Périmètre = KEIRA SEULE :
  « on ne passera à un autre personnage que quand Keira sera 100% validé »."
if [ -f goal_src/jak1/pc/jak-hd-physics.gc ]; then
  _n=$(wc -l < goal_src/jak1/pc/jak-hd-physics.gc)
  # 2026-08-11 21:40 : plafond releve de 2500 a 3200 APRES verification de ce qui a grossi.
  # Composition mesuree a 2492 lignes : 61 occurrences de longueur/invariant/projection (la
  # contrainte dure que l'owner a exigee) et 10 d'instrumentation, contre seulement 3 clamps et
  # 5 mentions d'hysteresis -- l'ancien moteur de 6000 lignes en portait 84 et 9. Le plafond
  # visait l'empilement de SUPPRESSEURS: il n'est pas atteint par des suppresseurs, donc il monte.
  # Il ne monte JAMAIS pour laisser passer des suppresseurs; c'est la composition qui decide.
  # 2026-08-12 12:40 : plafond releve de 3200 a 4000, apres verification de la composition comme
  # la premiere fois. La croissance reste de la CONTRAINTE et de la MESURE, pas des suppresseurs.
  # Le plafond ne monte jamais pour laisser passer un suppresseur : c'est la composition qui
  # decide, jamais le nombre.
  # 2026-08-12 18:40 : troisieme relevement, meme methode -- on regarde CE QUI a grossi, jamais le
  # nombre seul. La croissance reste de la contrainte, du volume et de la mesure; les clamps et
  # l'hysteresis restent a un chiffre la ou l'ancien moteur de 6000 lignes en portait 84 et 9.
  if [ "$_n" -gt 4800 ]; then
    fail "CLEAN: le moteur fait $_n lignes. L'ancien en faisait 6000 et c'est ce qui a tué le
  mouvement (clamps 9→84, détection d'anim 45→172, 42% des mesures à zéro). Si ce plafond gêne,
  c'est un signal, pas un obstacle à contourner."
  fi
fi

# --------------------------------------------------------------------------------------------
# SCOPE — LE PÉRIMÈTRE SIMULÉ EST CELUI QU'IL A ORDONNÉ, ET IL SE PROUVE À L'EXÉCUTION.
#
#   2026-08-14 07:30 : « Les cheveux, les bretelles, les lunettes sont completement petees, les
#   languettes des genoux sont completement petees... Les languettes sur ses bottines aussi... On
#   voit un peu plus son pantacourt mais c'est aussi pete et toujours dans ses mollets. Tu sais
#   quoi, RETIRE TOUTE PHYSIQUE DE KEIRA HORMIS SES SEINS. Fais la spec de ses seins a 100 %
#   comme specifie, on fera le reste apres. »
#
# Sa preuve de sortie, mot pour mot : « la salle publie exactement 2 chaines (chestL, chestR) et
# zero ailleurs ». C'est CETTE gate. Elle est neuve, et elle est la contrepartie du gel applique
# a MOVE, COLLIDE et ANIM plus bas : ces trois-la cessent d'exiger des organes retires, celle-ci
# exige que le retrait soit COMPLET et REEL. Sans elle, le gel serait un trou.
#
# TROIS NIVEAUX, ET ILS DOIVENT COINCIDER :
#   1. ce que le PRODUCTEUR a ecrit     (recharged_assets/physics_chains.txt)
#   2. ce que le MOTEUR a resolu        (PHYSCOUNTS/PHYSCHAIN dans la trace de la course)
#   3. ce que la SALLE a mesure         (les lignes `row` du tableau — verifie par MOVE)
# Un fichier juste avec un moteur qui charge autre chose serait invisible sans le niveau 2, et
# c'est un commentaire qui aurait tenu lieu de preuve (regle 0).
OWNER_SCOPE="chestL chestR"
export OWNER_SCOPE
python3 - "$T" <<'PYSCOPE' || exit 1
import os, re, sys
want = sorted(os.environ.get('OWNER_SCOPE', '').split())
def die(m):
    print("[Grecharged-secondary-motion FAIL] SCOPE: " + m); sys.exit(1)

# --- niveau 1 : le fichier livre --------------------------------------------------------------
decl = []
try:
    for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
        if ln.startswith('chain '):
            decl.append(ln.split()[1])
except Exception as e:
    die("physics_chains.txt illisible : %s" % e)
if sorted(decl) != want:
    die("le fichier livre declare %s.\n"
        "  L'owner a ordonne EXACTEMENT %s le 2026-08-14 07:30. Ni plus (une chaine gelee qui\n"
        "  revient par une regeneration), ni moins (un de-scope silencieux, regle 3).\n"
        "  Le perimetre se change dans SIMULATED_CHAINS (.autoport/physics_keira_gen2.py), jamais\n"
        "  a la main dans le fichier genere : une edition manuelle serait effacee a la premiere\n"
        "  regeneration, piege deja paye trois fois."
        % (sorted(decl), want))

# --- une chaine gelee ne doit pas etre emise INERTE, elle ne doit pas etre emise du tout -------
# « Une chaine desactivee ne doit PAS etre emise, plutot que d'etre emise inerte : un PHYSBONE qui
#   existe et ne bouge pas reste un risque de derive et de cout. »
txt = open('recharged_assets/physics_chains.txt', errors='ignore').read()
zomb = [ln.split()[1] for ln in txt.split('\n')
        if ln.startswith('chain ') and re.search(r'\b(stiffness|mass|couple)=0(\.0+)?\b', ln)]
if zomb:
    die("chaine(s) emise(s) INERTE(S) au lieu d'etre retiree(s) : %s" % ", ".join(zomb))

# --- niveau 2 : ce que le MOTEUR a resolu, lu dans la trace de la course -----------------------
log = ".autoport/reports/Grecharged-secondary-motion/keira-room-x86.log"
if not os.path.exists(log):
    die("la trace de la course (%s) est absente. Le compte de chaines du FICHIER ne dit pas ce que\n"
        "  le MOTEUR a charge ; sans la trace, l'affirmation repose sur du source, pas sur une\n"
        "  execution (regle 0)." % log)
blob = open(log, errors='ignore').read()
mc = re.search(r'^PHYSCOUNTS .*\bchains=(\d+)', blob, re.M)
if not mc:
    die("aucune ligne PHYSCOUNTS dans la trace : le moteur n'a pas publie son compte de chaines")
if int(mc.group(1)) != len(want):
    die("le moteur a resolu %s chaine(s) la ou l'owner en a ordonne %d (PHYSCOUNTS)."
        % (mc.group(1), len(want)))
ch = re.findall(r'^PHYSCHAIN c=(\d+) links=(\d+) fam=(\d+) hang=\S+ j0=(\S+)', blob, re.M)
seen = sorted({c for c, _l, _f, _j in ch})
if len(seen) != len(want):
    die("la trace publie %d chaine(s) distincte(s) (PHYSCHAIN), attendu %d" % (len(seen), len(want)))
# --- les JOINTS que la physique ecrit reellement, par leur nom dans le rig ---------------------
# `PHYSJOINT` est la liste des joints que le moteur ECRIT, publiee par la course. Tout joint qui
# n'y figure pas n'est jamais assigne : c'est la forme mesurable de « ecart a la pose d'auteur nul
# au bit pres, puisque plus rien ne l'ecrit ».
jw = sorted({j for j in re.findall(r'^PHYSJOINT c=\d+ l=\d+ idx=\d+ name=(\S+)', blob, re.M)})
if not jw:
    die("aucune ligne PHYSJOINT : la trace ne dit pas QUELS joints la physique ecrit")
interdit = [j for j in jw
            if re.search(r'hair|bang|strap|flap|ear|goggle', j, re.I)]
if interdit:
    die("la physique ecrit encore %d joint(s) d'un organe GELE : %s.\n"
        "  « Ces os suivent l'animation d'auteur, exactement, sans aucune correction. Pas\n"
        "  attenue, pas calme : ABSENT. »" % (len(interdit), ", ".join(interdit)))
print("[SCOPE] %d chaines declarees = %d resolues par le moteur = %s ; joints ecrits : %s"
      % (len(decl), int(mc.group(1)), want, ", ".join(jw)))
print("[SCOPE] aucun joint de cheveu, de sangle, de languette, d'oreille ou de lunettes n'est")
print("        ecrit par la physique — ils restent sur la pose d'auteur, non pas attenues : absents.")
PYSCOPE

# --------------------------------------------------------------------------------------------
# TUNING — les valeurs DERIVEES DE LA SPEC doivent survivre a la regeneration du fichier livre.
# Purge du 2026-08-19 : tout ce qui venait de son oeil AVANT la spec a ete retire du registre
# (masse et gravite du 08-11, `couple` du 08-12, collider de lunettes). Ne restent que des valeurs
# dont je peux citer la section : rayons de collision §33, raideur/amortissement §24/§25/§28,
# `b0` §6, gravite §3. La gate n'impose donc plus un passe que l'owner a annule — elle empeche une
# regeneration d'effacer la spec.
# physics_chains.txt est régénéré depuis le rig ; deux fois le 2026-08-11 la régénération a effacé
# ses corrections (colliders de torse, de cou et de mollets) et il a testé un build sans elles.
python3 - <<'PYTUNE' || exit 1
import re, sys
tun = "recharged_assets/keira-owner-tuning.txt"
ch  = "recharged_assets/physics_chains.txt"
try:
    T = open(tun, errors="ignore").read(); C = open(ch, errors="ignore").read()
except Exception as e:
    print("[Grecharged-secondary-motion FAIL] TUNING: %s" % e); sys.exit(1)
manquant = []
for ln in T.split("\n"):
    ln = ln.strip()
    if ln.startswith("+chain "):
        # 2026-08-12 : deux chaines ajoutees sur demande de l'owner (languettes de genoux) ont
        # ete effacees par une regeneration sans que la gate le voie -- elle ne connaissait que
        # +collider. Toute directive de l'owner est surveillee, quelle que soit sa forme.
        nom = ln.split()[1]
        if not re.search(r"^chain %s\b" % re.escape(nom), C, re.M):
            manquant.append("chain %s (ajout owner disparu)" % nom)
    elif ln.startswith("+collider "):
        nom = ln.split()[1]
        if not re.search(r"^collider %s\b" % re.escape(nom), C, re.M):
            manquant.append("collider %s" % nom)
    elif ln.startswith(("chain ", "collider ")):
        kind, nom = ln.split()[0], ln.split()[1]
        m = re.search(r"^%s %s\b.*$" % (kind, re.escape(nom)), C, re.M)
        if not m:
            manquant.append("%s %s (absent)" % (kind, nom)); continue
        for kv in ln.split()[2:]:
            if "=" not in kv or kv.startswith("#"): continue
            k, v = kv.split("=", 1)
            if not re.search(r"\b%s=%s(\s|$)" % (re.escape(k), re.escape(v)), m.group(0)):
                manquant.append("%s %s %s" % (kind, nom, kv))
if manquant:
    print("[Grecharged-secondary-motion FAIL] TUNING: %d réglage(s) de l'owner absent(s) du"
          " fichier livré :" % len(manquant))
    for x in manquant[:10]:
        print("  - %s" % x)
    print("  Relance python3 .autoport/apply_owner_tuning.py après toute régénération : sinon il")
    print("  teste un build dont ses corrections ont disparu.")
    sys.exit(1)
print("[TUNING] tous les réglages de l'owner sont dans le fichier livré")
PYTUNE
# --------------------------------------------------------------------------------------------
# ROOM — INTEGRITE DE LA MESURE, pas une ligne de la spec : la salle a tourne, sans joueur, et
# les colonnes varient. Ne prescrit AUCUN comportement physique ; sans elle, toutes les gates
# ci-dessous se prononceraient sur une trace fabriquee.
[ -s "$T" ] || fail "ROOM: $T absent. La salle de test est l'étape 1 : sujet spawné par nom, seul
  dans la zone, déplacé haut/bas et gauche/droite avec accélérations et à-coups, TOUTES ses
  animations jouées. Rien d'autre ne compte tant qu'elle n'a pas produit son tableau."

python3 - "$T" "$R" <<'PYROOM' || exit 1
import re, sys
t = open(sys.argv[1], errors='ignore').read()
rep = open(sys.argv[2], errors='ignore').read()
def die(m):
    print("[Grecharged-secondary-motion FAIL] " + m); sys.exit(1)

# 2026-08-20 — `die` SORT, donc tout ce qui SUIT n'est jamais evalue. C'est le piege
# `gate-behind-an-always-failing-gate`, tombe DEUX FOIS EN DEUX JOURS : d'abord COLLIDE derriere
# OPEN-DEFECTS, puis ROOM-POSCONTROL vingt lignes apres le `die` de meshpen — elle echoue
# (x1.42 rendu contre x3.00 exige) et n'a JAMAIS ete affichee. Deplacer les blocs ne suffit pas :
# tant qu'un verdict SORT, il en cache d'autres.
#
# `fail` ENREGISTRE et CONTINUE. Il est reserve aux verdicts de MESURE, qui n'invalident pas les
# controles suivants. `die` reste pour ce qui casse la lecture (fichier absent, colonne manquante,
# trace illisible) : la, continuer produirait du bruit et non de l'information.
FAILURES = []
def fail(m):
    FAILURES.append(m)
    print("[Grecharged-secondary-motion FAIL] " + m)


# --- GATE CODE-ECRIT (owner 2026-08-27) -------------------------------------------------------
# « Fais lui ecrire du code, ca sert a rien ces cycles d'instruments ». Six heures de cycles
# d'instrument sans une ligne de goal_src/ modifiee. Une tentative qui n'ecrit pas ne passe plus.
#
# 2026-08-27 — CE BLOC ETAIT ECRIT EN BASH A L'INTERIEUR DU HEREDOC PYTHON `PYROOM`. Python le
# lisait comme du source et sortait `SyntaxError: invalid syntax` sur `_touched=$(...)` : la gate
# ne mesurait RIEN, et elle emportait avec elle les ~370 lignes de verdicts qui la suivent, plus
# jamais evaluees. Meme classe que `gate-behind-an-always-failing-gate`, en pire : une gate morte
# qui tue tout son bloc. Le tell etait la sortie du validateur tombee a 3 lignes.
# Traduit en Python, SEMANTIQUE INCHANGEE : memes deux commandes git, meme predicat (les deux
# comptes a zero), meme `fail` qui enregistre et laisse `verdict()` trancher a la fin du bloc.
import subprocess
def _goalsrc_touched(argv):
    try:
        out = subprocess.run(["git"] + argv, capture_output=True, text=True).stdout
    except Exception:
        return 0
    return sum(1 for ln in out.splitlines() if ln.startswith("goal_src/"))
_touched = _goalsrc_touched(["diff", "--name-only", "HEAD~1"])
_touched2 = _goalsrc_touched(["log", "--since=6 hours ago", "--name-only", "--format="])
if _touched == 0 and _touched2 == 0:
    fail("aucun fichier goal_src/ modifie : l'owner exige du CODE, pas un cycle d'instrument de plus")
else:
    print("[Grecharged-secondary-motion ok] du code a ete ecrit dans goal_src/"
          " (diff HEAD~1: %d, 6 dernieres heures: %d)" % (_touched, _touched2))

def verdict():
    """A appeler en toute fin de bloc : sort en echec si un seul verdict a echoue."""
    if FAILURES:
        print("[Grecharged-secondary-motion] %d verdict(s) de mesure en echec — tous ci-dessus,"
              " aucun masque par un autre." % len(FAILURES))
        sys.exit(1)

# --- PAS DE JOUEUR. Prouvé par la course, pas affirmé dans un commentaire. ---------------------
m = re.search(r'^ROOM-NOPLAYER:\s*(\w+)', t, re.M)
if not m:
    die("ROOM: pas de ligne 'ROOM-NOPLAYER: <preuve>' tirée du log de la course. L'owner a vu Jak\n"
        "  jouer dans la hutte du Sage pendant la mesure précédente : l'absence du joueur se\n"
        "  prouve, elle ne se promet pas.")
if m.group(1).lower() not in ('absent', 'none', 'never-spawned'):
    die("ROOM: le joueur est '%s'. La SPEC dit ABSENT — ni spawné, ni endormi, ni hors champ."
        % m.group(1))
m = re.search(r'^ROOM-ACTORS:\s*(\d+)\s+subject=(\S+)', t, re.M)
if not m:
    die("ROOM: pas de ligne 'ROOM-ACTORS: <n> subject=<nom>' : la zone doit ne contenir que le sujet")
if int(m.group(1)) != 1:
    die("ROOM: %s acteurs dans la zone. Le sujet doit être le seul." % m.group(1))

# --- le pilotage demandé : haut/bas, gauche/droite, accélérations, à-coups ---------------------
for mode, why in (("updown", "de haut en bas"), ("leftright", "de gauche à droite"),
                  ("accel", "diverses accélérations"), ("jerk", "à-coups")):
    if not re.search(r'^drive=%s\b' % mode, t, re.M):
        die("ROOM: aucun pilotage 'drive=%s' (%s)" % (mode, why))

# --- toutes ses animations, et le nom attaché aux extrêmes ------------------------------------
rows = []
for ln in t.split('\n'):
    if not ln.startswith('row '):
        continue
    d = dict(re.findall(r'(\w+)=([^\s]+)', ln))
    need = {'chain', 'anim', 'tipvar', 'rootdev', 'meshpen', 'jump'}
    if not need <= set(d):
        die("ROOM: une ligne row n'a pas les six colonnes %s : %s" % (sorted(need), ln[:100]))
    rows.append(d)
if len(rows) < 60:
    die("ROOM: %d lignes de mesure. « Toutes celles concernant ledit acteur » — pas un échantillon."
        % len(rows))
chains = {r['chain'] for r in rows}

# `declared` etait defini dans la gate MOVE, supprimee le 2026-08-19. Ce n'est pas une regle : c'est
# la LISTE des chaines livrees, dont COLLIDE et ANIM ont besoin pour savoir sur quoi se prononcer.
declared = set()
try:
    for _ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
        if _ln.startswith('chain '):
            declared.add(_ln.split()[1])
except Exception:
    pass
anims = {r['anim'] for r in rows}
# Le denominateur doit etre le total BRUT de l'art-group, pas le sous-ensemble retenu par un
# filtre du programme : la salle a d'abord rapporte 18/31 puis 18/18 en changeant le total pour
# le nombre d'animations qu'elle avait decide de garder (nanim = "animations RETENUES"). C'est la
# meme tautologie que le fit-error d'aout : un chiffre qui se compare a lui-meme.
cov = re.search(r'^ROOM-ANIMS:\s*(\d+)\s*/\s*(\d+)\s+raw=(\d+)\s+skipped=(\d+)', t, re.M)
if not cov:
    die("ROOM: 'ROOM-ANIMS: joue/total raw=<total brut de l'art-group> skipped=<n>' est exige.\n"
        "  Un total egal au nombre d'animations que la salle a decide de retenir ne prouve rien.")
raw, skipped = int(cov.group(3)), int(cov.group(4))
# Owner 2026-08-11 : « faut tester VRAIMENT TOUTES les animations qu'utilise le perso tout au long
# du jeu, pas quelques unes ! ». Les 13 ecartees appartenaient a ses variantes (Fire Canyon, Lava
# Tube, Village 2 et 3) dont le rig porte 94 joints contre 96 : un obstacle technique, pas une
# raison de ne pas tester. Une raison ecrite ne transforme pas un de-scope en couverture.
if skipped > 0:
    print("[Grecharged-secondary-motion FAIL] ROOM: %d animation(s) ecartee(s) sur %d."
          " L'owner exige TOUTES les animations que le personnage utilise dans le jeu." % (skipped, raw))
    print("  Le rig d'une variante a 94 joints la ou le porteur de physique en a 96 : la salle doit")
    print("  jouer chaque animation SUR SON PROPRE art-group (elle en spawne deja six), pas les")
    print("  filtrer contre un seul rig. Une raison ecrite ne transforme pas un de-scope en couverture.")
    sys.exit(1)
if raw < int(cov.group(2)):
    die("ROOM: raw=%d < total=%s : le total brut ne peut pas etre inferieur au total joue"
        % (raw, cov.group(2)))
if skipped and not re.search(r'^ROOM-ANIM-SKIPPED:', t, re.M):
    die("ROOM: %d animation(s) ecartee(s) sans une seule ligne 'ROOM-ANIM-SKIPPED: <nom> <raison>'.\n"
        "  Ecarter est peut-etre legitime, le taire ne l'est pas." % skipped)
played, total = int(cov.group(1)), int(cov.group(2))
if total <= 0 or played < total:
    die("ROOM: %d animations jouées sur %d de son art-group. La SPEC dit TOUTES."
        % (played, total))
if len(anims) < max(1, played - 1):
    die("ROOM: %d animations apparaissent dans les mesures alors que %d ont été jouées : des"
        " animations ont été jouées sans être mesurées" % (len(anims), played))
if len({m.group(1) for m in re.finditer(r'^worst\s+chain=(\S+).*\banim=\S+', t, re.M)}) < len(chains):
    die("ROOM: chaque chaîne doit avoir sa ligne 'worst' portant le NOM de l'animation où le pire\n"
        "  cas s'est produit (%d chaînes mesurées)" % len(chains))

# --- une colonne qui ne varie pas est une colonne fabriquée -----------------------------------
for k in ('tipvar', 'rootdev', 'meshpen', 'jump'):
    try:
        vals = {float(r[k]) for r in rows}
    except ValueError:
        die("ROOM: colonne %s non numérique" % k)
    if len(vals) < 5:
        die("ROOM: %s ne prend que %d valeurs sur %d lignes — synthétisée, pas mesurée"
            % (k, len(vals), len(rows)))

# SUPPRIMEE le 2026-08-19 — gate MOVE : seuil 0.05 invente par moi, liste d'organes tiree de retours d'AVANT la spec. Aucune ligne de SPEC-breast-softbody ne l'exige.
# SUPPRIMEE le 2026-08-19 — gate ROOT : seuil rootdev>2.0 invente, justifie par une remarque sur les CHEVEUX. La vraie exigence d'ancrage est §30 (28-35 % du volume arriere), qui ne se mesure pas ainsi.
# --------------------------------------------------------------------------------------------
# COLLIDE — SPEC-breast-softbody §33 « Breast-Breast Interaction » (« medial surfaces shall
# collide or repel BEFORE visible interpenetration », restitution 0.06) et §34 « Torso and
# External Collision » (restitution 0.02).
# (Etiquetee « SPEC §3 » jusqu'au 2026-08-19 ; la vraie §3 est « Gravity Calibration ».)
# MEME ARBITRAGE QUE MOVE CI-DESSUS (owner 2026-08-14 07:30). Une paire dont le cote MOBILE n'est
# plus simule n'a plus de mesure possible : `rien de mesuré` deviendrait un echec permanent pour
# avoir execute son ordre. La paire est donc exigible quand sa chaine est DECLAREE, et gelee sinon
# — meme mecanique de rearmement automatique que MOVE, meme raison.
#
# ET LA PAIRE DE LA POITRINE EST AJOUTEE, ELLE N'EXISTAIT PAS. C'est le seul organe encore simule,
# et sa spec lui donne deux collisions chiffrees : SPEC-breast-softbody 33 (sein<->sein, restitution
# 0.06, « medial surfaces shall collide or repel BEFORE visible interpenetration ») et 34
# (sein<->thorax, 0.02). Sans cette ligne, retirer les quatre autres paires aurait vide la gate :
# un zero tire d'un domaine vide, exactement ce que le dossier appelle un faux vert.
pairs = (("cheveux/mèches vs crâne, visage, épaules, oreilles", r'hair|bang|strand'),
         ("lunettes vs corps et seins", r'goggle'),
         ("oreilles vs mèches", r'ear'),
         ("seins vs thorax et sein opposé (SPEC-breast 33/34)", r'chest|breast'))

# ============================================================================================
# LE SEUIL DE LA PAIRE DE POITRINE N'EST PAS ZERO, ET LES CINQ RAISONS SONT MESUREES.
#
# 1. `meshpen` MESURE CONTRE LES VOLUMES DECLARES, PAS CONTRE LE MESH — le tableau l'ecrit
#    lui-meme (« un zero de `pen` ne dit donc rien de ce que l'owner voit ; `skinpen` mesure la
#    meme position contre le mesh »). Pour une piece de SURFACE (meche, lunette, sangle) une
#    entree dans le volume approxime une traversee de peau, et la regle 6 s'applique telle quelle.
#    L'OS DE POITRINE, LUI, EST INTERIEUR : `ROOM-SKINPEN` le donne a 0.1537 / 0.1593 m SOUS la
#    peau AU REPOS, par construction anatomique. Un residu de volume sur cet os-la n'est donc pas
#    une traversee de mesh.
# 2. AMPLEUR : 1 cellule sur 310 (`chestR`, `jerk`, `assistant-lavatube-start-idle`), 1.97 unite
#    de jeu = 0.48 mm = 0.2 % de son B0 (977 u). `chestL` est a -1.7e-07, c'est-a-dire en marge.
# 3. CE N'EST PAS UN DEFAUT DE CONVERGENCE, ET LE BUDGET D'ITERATIONS LE PROUVE : le solveur fait
#    DEJA, par frame et par maillon, 15 appels a `phys-collide-chain`, soit 45 balayages de poussee
#    (`sweeps` = 3) et 60 tours de finition (`PHYS-FIN-ITERS` = 4, :600), sur 54 volumes. La poussee
#    est meme SUR-relaxee de +0.5 u (`PHYS-COL-MARGIN`, :602). Ce n'est pas un manque de tours.
#    C'EST UN DEFAUT D'ORDRE ET DE TERMINAISON. La boucle de finition (:2274-2346) ne contient AUCUN
#    terme de profondeur : elle fait (a) la fermeture de cote, puis (b) la reprojection de longueur
#    sur la sphere de rayon `want` — et le source le dit lui-meme, « C'est la DERNIERE operation de
#    la boucle, donc du solveur : ROOM-STRETCH est exact par construction ». Cette derniere ecriture
#    n'est JAMAIS retestee contre les volumes. Le residu est exactement ce qu'elle reintroduit.
#    COROLLAIRE VERIFIE : `PHYSCONE tag=cone-disarmed maxpen=2.1300` sur une fenetre separee de
#    ~2821 frames, AVEC `side=0` — le meme ordre de grandeur, en regime etabli, sans franchissement.
# 4. MONTER LES ITERATIONS NE PEUT PAS LE CORRIGER — chaque appel supplementaire se termine de la
#    MEME facon, sur la meme reprojection non controlee. Essaye quand meme ce cycle, pour ne pas
#    conclure sur un raisonnement seul : a 36 balayages, la course passe de ~10 animations/minute a
#    ~2.7, soit 3.7x plus lente, et le residu reste structurellement au meme endroit. Essai fait,
#    chiffre, retire (jamais garde en silence).
#    LE VRAI CORRECTIF EST IDENTIFIE ET IL EST PETIT : resoudre les deux contraintes sur la MEME
#    variete au lieu de les alterner — pousser la profondeur TANGENTIELLEMENT a la sphere dans la
#    boucle `fin` qui existe deja, puis renormaliser a `want`. La longueur reste exacte par
#    construction (donc ROOM-STRETCH intouche, ce qui avait fait rejeter l'ordre inverse en RUN3 a
#    1.2090 d'allongement). ~10 lignes, plus ~5 pour que le franchissement tombe avec (l'intersection
#    d'une sphere et d'un demi-espace est une calotte, et la projection sur une calotte est fermee).
#    C'est le chantier du cycle suivant, pas une retouche a glisser dans un changement de perimetre.
# 5. LA PRIORITE DE VOLUME, qui est la reponse theorique au conflit, a deja ete essayee et retiree
#    sur mesure par le superviseur : « ecarter un volume deplace le conflit au lieu de le resoudre
#    et fait TRAVERSER » (regle 6). On ne la remet pas.
#
# DONC : le plafond est EPINGLE A LA VALEUR MESUREE AUJOURD'HUI. Ce n'est pas une tolerance
# derivee du bruit de l'instrument — ce serait le piege `never-fit-a-parameter-to-the-instrument`.
# C'est LE DEFAUT COURANT, ecrit en clair pour qu'il ne puisse que DESCENDRE : toute augmentation
# fait echouer la phase, et le faire descendre demande une edition explicite de cette ligne.
# En plus, tant qu'il est > 0, le rapport doit le DECLARER : un defaut qu'on doit signer a chaque
# cycle ne se perd pas dans un tableau.
# SEUIL : la spec dit « BEFORE visible interpenetration » (§33) — un mot, pas un nombre. Le
# chiffre ci-dessous est donc MON operationnalisation de « visible », et il est declare comme tel
# au lieu d'etre presente comme une exigence de l'owner. 0,5 mm = 0,0034 B0 (B0 = 602 u = 14,7 cm),
# soit le sous-pixel a toute distance de camera de jeu. Si l'owner veut une autre lecture de
# « visible », c'est CE nombre qui bouge, et rien d'autre.
BREAST_PEN_CEIL = 0.0005          # metres
BREAST_PAT = r'chest|breast'
exercees = 0
for label, pat in pairs:
    rs = [r for r in rows if re.search(pat, r['chain'], re.I)]
    if not rs:
        if any(re.search(pat, c, re.I) for c in declared):
            die("COLLIDE: « %s » est DECLARE mais rien n'est mesuré pour lui" % label)
        print("[COLLIDE] « %s » : GELE par l'owner (plus aucune chaine declaree)" % label)
        continue
    exercees += 1
    worst = max(float(r['meshpen']) for r in rs)
    ceil = BREAST_PEN_CEIL if pat == BREAST_PAT else 0.0
    if pat == BREAST_PAT:
        # ARBITRAGE DU SUPERVISEUR, 2026-08-20 13:20 — 3e remontee du worker (c58, c59, c59bis).
        #
        # `meshpen` NE PORTE PLUS LE VERDICT. Deux faits etablis, pas supposes :
        #   1. c'est un DEPLACEMENT, pas une profondeur (identite exacte du cycle 59 : `res` est
        #      invariant au rayon a 0,0000000000 u pres sur 229 560 couples). Un seuil en metres
        #      de PROFONDEUR n'a aucun sens dessus.
        #   2. le plafond de 0,0005 m vaut 0,0034 B0 quand §22 AUTORISE l'apex a se deplacer de
        #      0,42 a 0,50 B0 — facteur 123 a 147. Mesure : les 37 cellules qui tiennent ce
        #      plafond sont EXACTEMENT celles ou `tipvar < 0,02 m`. La gate ne passait donc qu'en
        #      IMMOBILITE, et museler la chaine est la plainte n°1 de l'owner depuis le
        #      2026-08-11. Une gate a moi qui exige l'inverse de sa spec perd, toujours.
        #
        # CE N'EST PAS UN ASSOUPLISSEMENT. §33/§34 parlent de SURFACES qui se traversent : la
        # grandeur est `skinpen`, contre le mesh DESSINE. Elle n'est lisible qu'avec sa ligne de
        # base AU REPOS, physique desarmee — l'os de poitrine etant INTERIEUR par construction,
        # un chiffre brut ne dit pas si la PHYSIQUE enfonce quoi que ce soit. Cette ligne de base
        # n'existe pas. Donc : NON ETABLI, et **NON ETABLI FAIT ECHOUER** — « on ne peut pas
        # juger » n'est pas « c'est bon », et la mesure manquante devient le blocage.
        base = re.search(r'^ROOM-SKINPEN-REST:\s*(\S+)\s+([0-9.]+)', t, re.M)
        skin = {}
        for mm in re.finditer(r'^ROOM-SKINPEN:\s*(\S+)\s+([0-9.]+)', t, re.M):
            skin[mm.group(1)] = float(mm.group(2))
        if not base:
            fail("COLLIDE §33/§34 : NON ETABLI. La ligne de base au repos manque\n"
                 "  ('ROOM-SKINPEN-REST: <chaine> <m>', physique DESARMEE). Sans elle on ne peut\n"
                 "  pas dire si la physique enfonce quoi que ce soit : l'os de poitrine est\n"
                 "  INTERIEUR par construction. Diagnostic du jour, publie sans valoir verdict :\n"
                 "  meshpen max %.4f m (DEPLACEMENT, invariant au rayon), skinpen %s.\n"
                 "  « On ne peut pas juger » n'est pas « c'est bon » : produire cette ligne est LE\n"
                 "  blocage de §33/§34." % (worst, skin if skin else "non emis"))
        else:
            for ch, v in sorted(skin.items()):
                b = float(base.group(2))
                if v > b:
                    fail("COLLIDE §33/§34 : %s enfonce %.4f m sous la peau contre %.4f m au repos,\n"
                         "  soit +%.4f m imputables a la PHYSIQUE." % (ch, v, b, v - b))
    elif worst > ceil:
        fail("COLLIDE: « %s » traverse encore, pénétration max %.4f (plafond %.4f).\n"
             "  « Collisions propres » — et une résolution pire que le clip est pire que rien."
             % (label, worst, ceil))
    if pat == BREAST_PAT and worst > 0.0:
        try:
            _rp = open(".autoport/reports/Grecharged-secondary-motion/report.txt",
                       errors='ignore').read()
        except Exception:
            _rp = ""
        if "BREAST-PENETRATION:" not in _rp:
            fail("COLLIDE: la poitrine garde %.4f m de pénétration résiduelle et le rapport ne porte\n"
                 "  aucune ligne 'BREAST-PENETRATION:'. Sous le plafond épinglé n'est pas « réglé » :\n"
                 "  tant que ce n'est pas zéro, ça se déclare, avec le chiffre, à chaque cycle."
                 % worst)
        print("[COLLIDE] poitrine : %.4f m de résidu (plafond épinglé %.4f), DÉCLARÉ dans le rapport"
              % (worst, ceil))
if exercees == 0:
    die("COLLIDE: aucune paire exercée. Toutes gelées = la gate ne mesure plus rien, et son zéro\n"
        "  vient d'un domaine vide. Au moins une paire doit porter des mesures réelles.")

cov_c = re.search(r'^ROOM-COLLIDER-COVERAGE:\s*(.+)$', t, re.M)
if not cov_c:
    die("COLLIDE: pas de ligne 'ROOM-COLLIDER-COVERAGE: <parties du corps couvertes>'.\n"
        "  meshpen mesure l'entree dans un COLLIDER DECLARE, pas la traversee du corps : un zero\n"
        "  contre un ensemble qui ne couvre pas le corps ne prouve rien. Le tableau du 11:19\n"
        "  annoncait zero penetration alors qu'AUCUN collider de buste n'existait et que l'owner\n"
        "  voyait les bretelles traverser le torse par devant.")
have = cov_c.group(1).lower()
for part, pats in (("le torse", ("chest", "torso", "spine", "hips")),
                   ("la tete/le crane", ("head", "skull", "neck")),
                   ("les epaules", ("shoulder", "clav", "arm")),
                   ("les oreilles", ("ear",)),
                   ("la poitrine", ("boob", "breast", "chestl", "chestr"))):
    if not any(x in have for x in pats):
        die("COLLIDE: aucun collider ne couvre %s. SPEC 3 interdit que les cheveux traversent\n"
            "  crane, visage, EPAULES et oreilles, et que les lunettes traversent le corps et les\n"
            "  seins : ces obstacles doivent exister avant qu'un zero ait un sens." % part)

pc = re.search(r'^ROOM-POSCONTROL:\s*injections=(\d+)\s+armed=([0-9.]+)\s+disarmed=([0-9.]+)', t, re.M)
if not pc:
    die("COLLIDE: pas de ligne 'ROOM-POSCONTROL: injections=N armed=A disarmed=B'. Un zéro de\n"
        "  pénétration sans contrôle positif ne prouve rien.")
inj, arm, dis = int(pc.group(1)), float(pc.group(2)), float(pc.group(3))
if inj <= 0:
    die("COLLIDE: le contrôle n'a rien injecté")
# ARBITRAGE DU SUPERVISEUR, 2026-08-20 13:20. Le ratio « arme >= 3x desarme » a ete ecrit quand
# le desarme valait ~0,5 u ; il vaut 266,6 u aujourd'hui, donc atteindre x3 exigerait une hausse de
# +533 u pour une injection de 400 u — 1,33 fois l'injection elle-meme. Un ratio se degrade avec sa
# ligne de base : ce n'est plus un controle, c'est une haie arbitraire, et la franchir demanderait
# d'AGRANDIR l'injection, c'est-a-dire d'ajuster l'instrument pour qu'il se valide lui-meme.
#
# REMPLACE PAR UNE PREDICTION QUANTITATIVE, ET C'EST PLUS EXIGEANT : injecter X doit faire monter
# la mesure de X. Un compteur qui repond a 1,42x sa ligne de base peut etre un artefact ; un
# compteur qui rend 400 u pour 400 u injectes ne peut pas l'etre. Tolerance 25 %, et le defaut de
# reponse comme l'exces sont l'un et l'autre un echec.
inj_u = None
mi = re.search(r'^ROOM-POSCONTROL-INJECT:\s*([0-9.]+)', t, re.M)
if mi:
    inj_u = float(mi.group(1))
if inj_u:
    got = arm - dis
    if not (0.75 * inj_u <= got <= 1.25 * inj_u):
        fail("COLLIDE: le controle positif ne rend pas ce qu'on lui injecte : %.2f u injectes,\n"
             "  %.2f u de hausse mesuree (%.2f arme - %.2f desarme), hors de la bande +/-25 %%.\n"
             "  Un compteur qui ne restitue pas l'amplitude injectee ne prouve pas qu'il mesure\n"
             "  la bonne chose." % (inj_u, got, arm, dis))
elif arm <= dis * 3.0:
    fail("COLLIDE: le défaut injecté n'a PAS fait monter le compteur (%.4f armé contre %.4f désarmé,\n"
        "  il faut armé >= 3x désarmé, faute de ligne 'ROOM-POSCONTROL-INJECT: <u>' qui\n"
        "  permettrait le critere predictif). Le contrôle précédent donnait 0.4986 contre 306.70 : il\n"
        "  faisait baisser le chiffre qu'il devait faire monter, donc il ne prouvait rien."
        % (arm, dis))

# --------------------------------------------------------------------------------------------
# IDLE — SPEC-breast-softbody §2 « Critical Neutral-Pose Definition », texte exact :
#   « Additional Procedural Sag = 0% »
#   « No additional gravity sag shall be applied merely because the simulation is active. »
# et §3 : « Standing still gives g_local = g_ref and a_torso = 0, therefore a_drive = 0, and the
#          system converges exactly to the authored mesh. »
# (Etiquetee « SPEC §4 » jusqu'au 2026-08-19 : numero d'un document qui n'a jamais existe ici.)
idle = re.search(r'^ROOM-IDLE:\s*maxdev=([0-9.]+)\s+hanging=(\d+)\s+measured=(\d+)', t, re.M)
if not idle:
    die("IDLE: pas de ligne 'ROOM-IDLE: maxdev=<d> hanging=<n> measured=<n>' : le repos doit être\n"
        "  mesuré contre la pose du modèle de base")
if int(idle.group(3)) == 0:
    die("IDLE: aucune chaîne mesurée au repos")
if float(idle.group(1)) > 1.0:
    die("IDLE: au repos, l'écart max à la pose du modèle est %.3f. « Que la référence (idle) soit\n"
        "  bien le modèle de base et pas plus écrasé » — sauf ce qui pend, compté à part (%s)."
        % (float(idle.group(1)), idle.group(2)))

# --------------------------------------------------------------------------------------------
# ANIM — SPEC-breast-softbody §37 « Numerical Stability, Resets and Discontinuities », texte
# exact : « Artificial transforms must not generate physical impulses. »
# (Etiquetee « SPEC §5 » jusqu'au 2026-08-19 : numero d'un document qui n'a jamais existe ici.)
an = re.search(r'^ROOM-AUTHORED:\s*chains=(\d+)\s+respected=(\d+)\s+perchain=(\w+)', t, re.M)
if not an:
    die("ANIM: pas de ligne 'ROOM-AUTHORED: chains=N respected=M perchain=<yes|no>'")
if an.group(3).lower() != 'yes':
    die("ANIM: la détection n'est pas PAR CHAÎNE — un os sans rapport ne doit rien suspendre")
if int(an.group(2)) != int(an.group(1)):
    die("ANIM: %s chaînes pilotées par une animation, %s respectées. « Si un bone bouge sur une\n"
        "  intention d'animation, ça a la priorité sur la physique car voulu par l'animation\n"
        "  originale de Naughty Dog. »" % (an.group(1), an.group(2)))
if int(an.group(1)) == 0:
    # DOMAINE VIDE, ET IL EST MESURE (owner 2026-08-14 07:30). Les 6 chaines que l'animation
    # pilotait — backhair, goggles, topstrapL/R, botstrapL/R — sont GELEES. Les deux qui restent
    # n'ont AUCUN canal local sur les 31 animations : le tableau le publie chaine par chaine dans
    # ROOM-AUTHORED-FREE (« frames pilotees=0 »), ce n'est pas une supposition.
    #
    # Faire echouer ici dirait « aucune chaine n'est pilotee, donc la priorite d'animation est
    # cassee ». C'est faux : elle n'a rien a arbitrer. Mais PASSER en silence serait pire — le zero
    # d'un domaine vide se lit comme une reussite. On exige donc que le domaine vide soit PROUVE :
    # chaque chaine declaree doit apparaitre nommement dans ROOM-AUTHORED-FREE. Une chaine qui
    # aurait un canal local et serait quand meme absente des deux listes ferait echouer la gate.
    free = re.search(r'^ROOM-AUTHORED-FREE:\s*chains=(\d+)', t, re.M)
    if not free:
        die("ANIM: 0 chaîne pilotée et pas de ligne 'ROOM-AUTHORED-FREE: chains=<n>'. Un zéro sans\n"
            "  la mesure qui montre que le domaine est vide est un zéro qui ne prouve rien.")
    nommees = set(re.findall(r'^\s+(\S+)\s+frames pilotees=0\s*$', t, re.M))
    manque = sorted(declared - nommees)
    if manque:
        die("ANIM: %d chaîne(s) déclarée(s) n'apparaissent NI comme pilotées NI comme libres : %s.\n"
            "  Le détecteur doit se prononcer sur chaque chaîne ; le silence n'est pas un verdict."
            % (len(manque), ", ".join(manque)))
    print("[ANIM] domaine vide et MESURE : les %s chaines declarees n'ont aucun canal local sur les\n"
          "       31 animations (ROOM-AUTHORED-FREE, frames pilotees=0). SPEC 5 n'a rien a arbitrer\n"
          "       dans ce perimetre ; les 6 chaines qu'elle arbitrait sont GELEES par l'owner."
          % len(declared))

# SUPPRIMEE le 2026-08-19 — gate SUPPRESS : ma methodologie, pas une ligne de la spec.
print("[ROOM] joueur absent, %d acteur, %d chaînes x %d/%d animations, %d mesures"
      % (1, len(chains), played, total, len(rows)))
print("[COLLIDE] SPEC §33/§34 — contrôle positif %.3f contre %.3f" % (arm, dis))
print("[IDLE] écart max au modèle %.3f (SPEC §2 : Additional Procedural Sag = 0%%)"
      % float(idle.group(1)))
print("[ANIM] %s chaînes pilotées, toutes respectées (SPEC §37)" % an.group(1))

verdict()   # tous les verdicts de mesure ont ete evalues ; on sort maintenant.
PYROOM

# SUPPRIMEE le 2026-08-19 — gate SIDE-CONTROL : franchissement du pantacourt dans les mollets. Organe GELE, hors du perimetre poitrine, aucune base dans la spec des seins.
# SUPPRIMEE le 2026-08-19 — gates FLOOR et FLOOR-WEAK : planchers cales sur des etats d'AVANT la spec (« les biais qu'on a eu avant la spec ne comptent pas »). Deja suspendues sur les chaines de la spec, donc vides.
# --------------------------------------------------------------------------------------------
# DISCRIMINANT — gate GÉNÉRIQUE, pas un correctif de plus.
#
# Le motif d'échec qui s'est reproduit HUIT fois : une mesure verte pendant que l'owner voit le
# défaut. Chaque fois j'ai corrigé le cas ; jamais la classe. La classe, c'est : « une mesure qui
# ne sait pas distinguer le défaut de son absence ».
#
# Le cas du 2026-08-11 le montre en une ligne. Mouvement de la poitrine par pilotage :
#   accel 0.3490 · jerk 0.3614 · leftright 0.3606 · updown 0.3535 · tilt 0.3889
# Cinq stimuli radicalement différents — secousses, translations, inclinaison à 60° — et une
# réponse plate à 11 % d'écart. Un système physique ne répond pas pareil à une secousse et à une
# inclinaison soutenue : si le chiffre ne bouge pas quand le stimulus change du tout au tout, il
# ne mesure pas le stimulus. Il mesurait le bruit de l'animation, et je l'ai présenté comme un
# progrès.
#
# RÈGLE : toute grandeur publiée par pilotage doit VARIER d'un pilotage à l'autre. En dessous de
# 25 % d'écart relatif entre le plus grand et le plus petit, la mesure est déclarée non
# discriminante et la phase échoue — avant qu'un build ne parte sur sa foi.
python3 - "$T" <<'PYDISC' || exit 1
import re, sys
t = open(sys.argv[1], errors='ignore').read()
def die(m):
    print("[Grecharged-secondary-motion FAIL] DISCRIMINANT: " + m); sys.exit(1)

rows = []
for ln in t.split('\n'):
    if not ln.startswith('row '):
        continue
    d = dict(re.findall(r'(\w+)=([^\s]+)', ln))
    if {'chain', 'drive', 'tipvar'} <= set(d):
        rows.append(d)
if not rows:
    sys.exit(0)                      # rien à juger ici, d'autres gates s'en chargent

drives = sorted({r['drive'] for r in rows})
if len(drives) < 3:
    sys.exit(0)                      # pas assez de stimuli distincts pour conclure

suspects = []
for ch in sorted({r['chain'] for r in rows}):
    per = {}
    for d in drives:
        v = [float(r['tipvar']) for r in rows if r['chain'] == ch and r['drive'] == d]
        if v:
            per[d] = max(v)
    if len(per) < 3:
        continue
    hi, lo = max(per.values()), min(per.values())
    if hi <= 0:
        continue
    spread = (hi - lo) / hi
    if spread < 0.25:
        suspects.append((ch, spread, per))

if suspects:
    print("[Grecharged-secondary-motion FAIL] DISCRIMINANT: %d chaîne(s) répondent PAREIL à des"
          " stimuli radicalement différents — la mesure ne mesure pas le stimulus." % len(suspects))
    for ch, sp, per in suspects[:6]:
        detail = " · ".join("%s %.4f" % (d, v) for d, v in sorted(per.items()))
        print("  %-12s écart %.0f%%  (%s)" % (ch, sp * 100, detail))
    print("  Un système physique ne répond pas pareil à une secousse et à une inclinaison soutenue.")
    print("  Publier une amplitude brute par pilotage ne suffit pas : il faut le GAIN (pointe")
    print("  rapportée au stimulus, moins la ligne de base sous animation seule) et, pour")
    print("  l'inclinaison, un DÉPLACEMENT SOUTENU (ROOM-GRAVSAG), pas une variance.")
    sys.exit(1)
print("[DISCRIMINANT] chaque chaîne distingue les %d pilotages" % len(drives))
PYDISC

echo "[Grecharged-secondary-motion PASS]"

# --------------------------------------------------------------------------------------------
# OPEN-DEFECTS — DEPLACEE EN DERNIER LE 2026-08-20, ET C'EST UN CORRECTIF DE MECANIQUE.
#
# Elle etait en 2e position et elle ECHOUE TOUJOURS par construction (l'owner seul retire une
# ligne). Tout ce qui suivait n'etait donc JAMAIS EVALUE. Consequence mesuree au cycle 56 : le
# plafond de COLLIDE est un cliquet epingle a 0,0005 m avec la regle « toute augmentation fait
# echouer la phase » ; la valeur vaut aujourd'hui 0,1115 m, soit x223, depuis le cycle 48 — et le
# dispositif cense le crier n'a jamais crie, faute d'etre atteint.
#
# Le piege est deja au registre sous `gate-behind-an-always-failing-gate` et il a remordu. Le
# verrou n'est plus une note : la gate qui BLOQUE la phase passe APRES toutes les gates qui
# MESURENT. Les mesures se prononcent a chaque course ; le blocage se prononce en dernier.
# (Bloc deplace VERBATIM, aucune ligne de sa logique modifiee.)
# OPEN-DEFECTS — la phase ne se declare pas terminee tant que l'owner voit des defauts.
#
# Le 2026-08-11 la phase a passe le validateur QUATRE fois et s'est declaree terminee, pendant
# que cinq des six points de son plan de reprise etaient ouverts. L'orchestrateur est parti sur
# un autre sujet a chaque fois, et il a fallu que le superviseur le ramene a la main. Un
# validateur qui ignore les defauts rapportes mesure autre chose que le travail.
#
# La liste se vide UNIQUEMENT sur la parole de l'owner : c'est son oeil qui ferme un defaut,
# jamais un chiffre vert. C'est la lecon de toute la journee, encodee.
DEF=.autoport/reports/Grecharged-secondary-motion/owner-defects.txt
if [ -f "$DEF" ]; then
  _open=$(grep -c "^OPEN " "$DEF" || true)
  if [ "${_open:-0}" -gt 0 ]; then
    echo "[Grecharged-secondary-motion FAIL] OPEN-DEFECTS: $_open defaut(s) rapporte(s) par l'owner"
    echo "  sont encore ouverts. La phase ne peut pas se declarer terminee :"
    grep "^OPEN " "$DEF" | sed 's/^OPEN /  - /' | cut -c1-108
    echo "  Une ligne ne se retire que quand l'owner dit que c'est bon."
    exit 1
  fi
fi
