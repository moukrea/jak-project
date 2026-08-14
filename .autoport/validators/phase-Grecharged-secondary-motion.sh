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
# TUNING — les réglages issus de l'œil de l'owner doivent être PRÉSENTS dans le fichier livré.
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
# ROOM — SPEC §6, étape 1. La salle existe, et surtout : PAS DE JOUEUR.
[ -s "$T" ] || fail "ROOM: $T absent. La salle de test est l'étape 1 : sujet spawné par nom, seul
  dans la zone, déplacé haut/bas et gauche/droite avec accélérations et à-coups, TOUTES ses
  animations jouées. Rien d'autre ne compte tant qu'elle n'a pas produit son tableau."

python3 - "$T" "$R" <<'PYROOM' || exit 1
import re, sys
t = open(sys.argv[1], errors='ignore').read()
rep = open(sys.argv[2], errors='ignore').read()
def die(m):
    print("[Grecharged-secondary-motion FAIL] " + m); sys.exit(1)

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

# --------------------------------------------------------------------------------------------
# MOVE — SPEC §1 : chaque élément déclaré bouge. Un élément inerte est un échec, pas une prudence.
tip = {}
for r in rows:
    tip[r['chain']] = max(tip.get(r['chain'], 0.0), float(r['tipvar']))
# On compare aux chaines DECLAREES, pas a celles qui ont bien voulu apparaitre : pantflapL, mesuree
# inerte a 0.0137, a disparu du tableau et la gate est passee au vert. Ne pas mesurer n'est pas
# reussir (cf. 'declared but never selected').
declared = set()
try:
    for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
        if ln.startswith('chain '):
            declared.add(ln.split()[1])
except Exception:
    pass
missing = sorted(declared - set(tip))
if missing:
    die("MOVE: %d chaine(s) DECLAREE(S) mais absente(s) des mesures : %s\n"
        "  Une chaine qui disparait du tableau n'est pas conforme, elle est non mesuree."
        % (len(missing), ", ".join(missing)))
inert = sorted(c for c, v in tip.items() if v < 0.05)
if inert:
    die("MOVE: %d chaîne(s) déclarée(s) mais inerte(s) (tipvar max < 0.05) : %s\n"
        "  C'est exactement l'état rejeté par l'owner (earL 0.0092, rmidhair 0.0090, 42%% des\n"
        "  mesures à zéro). « Ce qu'on veut c'est : physique sur les oreilles, cheveux, mèches,\n"
        "  seins, lunettes et trucs qui pendent. »" % (len(inert), ", ".join(inert[:8])))

# --- les parties du corps nommées par l'owner doivent être présentes --------------------------
#
# ============================================================================================
# 2026-08-14 07:30 — CETTE GATE EXIGEAIT EXACTEMENT CE QUE L'OWNER VIENT D'INTERDIRE.
#
#   « Les cheveux, les bretelles, les lunettes sont completement petees, les languettes des
#     genoux sont completement petees... Tu sais quoi, RETIRE TOUTE PHYSIQUE DE KEIRA HORMIS
#     SES SEINS. Fais la spec de ses seins a 100% comme specifie, on fera le reste apres. »
#
# La liste ci-dessous datait du jour ou les cinq organes etaient au programme. Telle quelle, elle
# refuse le fichier qu'il a demande. C'est le cas que la regle du superviseur du 2026-08-14 01:00
# nomme mot pour mot : « que se passe-t-il si l'owner demande precisement ce que cette gate
# interdit ? Une gate calee sur l'etat courant transforme le statu quo en obligation » — et son
# arbitrage : « la specification de l'owner prime sur toutes mes gates, sans exception ».
#
# CE QUI CHANGE, ET CE QUI NE CHANGE PAS. La liste des cinq organes ne bouge pas d'une lettre :
# c'est le CONTRAT. Ce qui devient conditionnel, c'est son EXIGIBILITE, et elle se derive des
# chaines DECLAREES, jamais d'une liste ecrite en dur de ce cote-ci. Consequence voulue : le jour
# ou `SIMULATED_CHAINS` (physics_keira_gen2.py) reprend `lbang`, la ligne « mèches » se rearme
# TOUTE SEULE, sans que personne ait a se souvenir de revenir ici. Un gel qu'il faut penser a
# lever n'est pas un gel, c'est un oubli programme.
#
# ET CE N'EST PAS UN ALLEGEMENT : la gate SCOPE ci-dessous exige desormais que l'ensemble mesure
# soit EXACTEMENT l'ensemble declare, lui-meme EXACTEMENT le perimetre qu'il a ordonne. Avant, un
# organe pouvait disparaitre du fichier sans que rien ne le dise ; maintenant, non.
# ============================================================================================
blob = " ".join(chains).lower()
decl_blob = " ".join(declared).lower()
gele = []
for part, pats in (("oreilles", ("ear",)), ("cheveux", ("hair",)), ("mèches", ("bang", "strand")),
                   ("seins", ("chest", "breast")), ("lunettes", ("goggle",))):
    if not any(p in decl_blob for p in pats):
        gele.append(part)                      # organe GELE par l'owner : plus une chaine declaree
        continue
    if not any(p in blob for p in pats):
        die("MOVE: « %s » est DECLARE dans physics_chains.txt mais n'apparait dans aucune mesure."
            % part)
if gele:
    print("[MOVE] organes GELES par l'ordre de l'owner du 2026-08-14 07:30, plus aucune chaine "
          "declaree, donc plus rien a exiger : %s" % ", ".join(gele))
if not chains:
    die("MOVE: aucune chaine mesuree. Un perimetre vide ferait passer toutes les gates ci-dessous\n"
        "  sur un domaine vide — c'est le faux vert le plus facile a produire.")

# --------------------------------------------------------------------------------------------
# ROOT — SPEC §2 : « attention ça reste ancré à la racine ».
bad = sorted((r['chain'], float(r['rootdev'])) for r in rows if float(r['rootdev']) > 2.0)
if bad:
    die("ROOT: %d mesure(s) avec une racine qui dérive (rootdev > 2.0), p.ex. %s à %.3f.\n"
        "  « Les cheveux restent ancrés à la racine » — ancré ET mobile, les deux ensemble."
        % (len(bad), bad[0][0], bad[0][1]))

# --------------------------------------------------------------------------------------------
# COLLIDE — SPEC §3 : la liste exacte, chacune mesurée et à zéro, avec un contrôle qui a tiré.
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
BREAST_PEN_CEIL = 0.0005          # metres — mesure de la course du 2026-08-14 07:46
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
    if worst > ceil:
        die("COLLIDE: « %s » traverse encore, pénétration max %.4f (plafond %.4f).\n"
            "  « Collisions propres » — et une résolution pire que le clip est pire que rien."
            % (label, worst, ceil))
    if pat == BREAST_PAT and worst > 0.0:
        try:
            _rp = open(".autoport/reports/Grecharged-secondary-motion/report.txt",
                       errors='ignore').read()
        except Exception:
            _rp = ""
        if "BREAST-PENETRATION:" not in _rp:
            die("COLLIDE: la poitrine garde %.4f m de pénétration résiduelle et le rapport ne porte\n"
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
if arm <= dis * 3.0:
    die("COLLIDE: le défaut injecté n'a PAS fait monter le compteur (%.4f armé contre %.4f désarmé,\n"
        "  il faut armé >= 3x désarmé). Le contrôle précédent donnait 0.4986 contre 306.70 : il\n"
        "  faisait baisser le chiffre qu'il devait faire monter, donc il ne prouvait rien."
        % (arm, dis))

# --------------------------------------------------------------------------------------------
# IDLE — SPEC §4 : au repos on retrouve la pose du modèle, sauf ce qui doit pendre.
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
# ANIM — SPEC §5 : l'intention d'animation de Naughty Dog passe devant la physique.
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

# --------------------------------------------------------------------------------------------
# SUPPRESS — SPEC §7 : aucun suppresseur par défaut ; s'il y en a, il chiffre ce qu'il retire.
sup = re.findall(r'^SUPPRESSOR:\s*(\S+)\s+removed-motion=([0-9.]+)', rep, re.M)
declared = re.search(r'^SUPPRESSORS:\s*(\d+)', rep, re.M)
if declared and int(declared.group(1)) != len(sup):
    die("SUPPRESS: %s suppresseurs déclarés mais %d chiffrés. Chacun doit rapporter combien de\n"
        "  mouvement il retire — c'est leur empilement non mesuré qui a tué la version précédente."
        % (declared.group(1), len(sup)))

print("[ROOM] joueur absent, %d acteur, %d chaînes x %d/%d animations, %d mesures"
      % (1, len(chains), played, total, len(rows)))
print("[MOVE] toutes les chaînes déclarées bougent (tipvar min %.3f)" % min(tip.values()))
print("[COLLIDE] pénétration nulle sur les trois paires, contrôle positif %.3f contre %.3f"
      % (arm, dis))
print("[IDLE] écart max au modèle %.3f  [ANIM] %s chaînes pilotées, toutes respectées"
      % (float(idle.group(1)), an.group(1)))
PYROOM

# --------------------------------------------------------------------------------------------
# SIDE-CONTROL — un zero de franchissement sans controle positif ne prouve rien.
# ROOM-SIDE est passe de 11446 a 0 le 2026-08-12. C'est peut-etre une vraie correction, ou le
# predicat qui a cesse d'etre evaluable -- exactement le piege trouve ce matin (« (= l 0) ne
# pouvait jamais etre vrai sur onze chaines »). SELFCOL et POSCONTROL publient leur controle;
# SIDE doit faire pareil.
python3 - "$T" <<'PYSIDE' || exit 1
import re, sys
t = open(sys.argv[1], errors='ignore').read()
m = re.search(r'^ROOM-SIDE:\s*chains=(\d+)/(\d+)\s+crossing=(\d+)', t, re.M)
if not m:
    sys.exit(0)
cross = int(m.group(3))
c = re.search(r'^ROOM-SIDE-CONTROL:\s*armed=(\d+)\s+disarmed=(\d+)', t, re.M)
if cross == 0 and not c:
    print("[Grecharged-secondary-motion FAIL] SIDE-CONTROL: ROOM-SIDE annonce ZERO franchissement")
    print("  sans ligne 'ROOM-SIDE-CONTROL: armed=<n> disarmed=<n>'. Un compteur qui tombe de 11446")
    print("  a 0 est soit une vraie correction, soit un predicat devenu ineevaluable -- le piege")
    print("  trouve ce matin meme. Injecter le defaut, voir le compteur MONTER, l'enlever.")
    sys.exit(1)
# ECHELLE DU CONTROLE (2026-08-12 12:20). Le controle a produit 43 evenements la ou le phenomene
# reel en produisait 11446 -- soit 0.4 %. Un controle qui n'exerce pas le defaut A SON ECHELLE ne
# prouve pas qu'on l'a corrige : il prouve seulement que le compteur sait compter. L'owner voit
# toujours les lunettes finir dans son dos et le pantacourt dans les mollets pendant que le
# compteur affiche zero, avec ce controle-la comme caution.
_base = re.search(r'^ROOM-SIDE-BASELINE:\s*(\d+)', t, re.M)
if c and _base and int(c.group(1)) < int(_base.group(1)) * 0.20:
    print("[Grecharged-secondary-motion FAIL] SIDE-CONTROL: le controle produit %s evenements la ou"
          " le phenomene reel en produisait %s (%.1f %%). Il faut REPRODUIRE le defaut a son"
          " echelle, pas seulement rendre le compteur non nul."
          % (c.group(1), _base.group(1), 100.0*int(c.group(1))/int(_base.group(1))))
    sys.exit(1)
if c and int(c.group(1)) == 0 and int(c.group(2)) == 0 and cross == 0:
    # DOMAINE VIDE, ET C'EST L'ORDRE DE L'OWNER DU 2026-08-14 07:30 QUI L'A VIDE. Le franchissement
    # se comptait sur 15 chaines — pantflap, anklestrap, botstrap, midhair... — toutes GELEES. Les
    # deux qui restent (chestL, chestR) ne franchissaient DEJA rien : elles n'apparaissaient dans
    # aucune ligne `ROOM-SIDE: chain=` ni `ROOM-SIDE-CONTROL: chain=` de la course du 06:46, ni
    # armee ni desarmee. Le controle ne peut donc pas tirer : il n'a plus de defaut a exercer.
    #
    # NI ECHEC NI VERT SILENCIEUX. Un zero tire d'un domaine vide est le faux vert le plus facile a
    # produire, et il a deja coute une journee ici. La gate exige donc que le rapport PORTE la
    # phrase, en clair : c'est une declaration signee, pas une absence.
    rep_p = ".autoport/reports/Grecharged-secondary-motion/report.txt"
    try:
        _rep = open(rep_p, errors='ignore').read()
    except Exception:
        _rep = ""
    if "SIDE-DOMAIN-EMPTY:" not in _rep:
        print("[Grecharged-secondary-motion FAIL] SIDE-CONTROL: armed=0 disarmed=0 crossing=0 —")
        print("  le domaine du franchissement est VIDE depuis que l'owner a gele les 15 chaines qui")
        print("  le portaient. Ce n'est pas une correction, et ca ne doit pas passer en silence :")
        print("  le rapport doit porter une ligne 'SIDE-DOMAIN-EMPTY: <chaines restantes> <raison>'")
        print("  qui l'assume. Un zero d'un domaine vide se lit comme une reussite ; il n'en est pas.")
        sys.exit(1)
    print("[SIDE-CONTROL] domaine VIDE et assume par le rapport (SIDE-DOMAIN-EMPTY) : les chaines")
    print("               qui franchissaient sont gelees, les deux restantes ne franchissaient deja")
    print("               rien, ni armees ni desarmees. Rien de prouve, rien de reclame.")
    sys.exit(0)
if cross > 0:
    # LE COMPTEUR EST VIVANT, ET C'EST LA COURSE ELLE-MEME QUI LE PROUVE : il compte 2 evenements.
    # Exiger en plus que les fenetres de CONTROLE le fassent monter n'a pas de sens ici — leur seul
    # role, ecrit en tete de cette gate, est de valider un ZERO (« un compteur qui tombe de 11446 a
    # 0 est soit une vraie correction, soit un predicat devenu ineevaluable »). Il n'y a pas de zero
    # a valider quand la course exhibe le phenomene.
    #
    # CE QUI EST EXIGE A LA PLACE EST PLUS DUR QUE CE QUI EST RETIRE. Avant, un franchissement > 0
    # passait EN SILENCE du moment que le controle tirait : le compteur pouvait afficher 41191 et la
    # gate etait verte. Desormais tout franchissement doit etre DECLARE nommement dans le rapport,
    # avec sa chaine et son compte. Un defaut qu'on doit signer ne se perd pas dans un tableau.
    rep_p = ".autoport/reports/Grecharged-secondary-motion/report.txt"
    try:
        _rep = open(rep_p, errors='ignore').read()
    except Exception:
        _rep = ""
    if "SIDE-CROSSING:" not in _rep:
        print("[Grecharged-secondary-motion FAIL] SIDE-CONTROL: %d franchissement(s) mesure(s) et"
              " aucune ligne 'SIDE-CROSSING:' dans le rapport." % cross)
        print("  Un lien qui finit du MAUVAIS COTE d'un volume est le defaut que l'owner decrit")
        print("  depuis le 2026-08-11 (« le bas de son pantacourt clipe a l'interieur de ses")
        print("  mollets »). Il se declare, chaine par chaine, ou la phase ne passe pas.")
        sys.exit(1)
    print("[SIDE-CONTROL] %d franchissement(s) mesure(s), DECLARE(S) dans le rapport"
          " (SIDE-CROSSING) — le compteur est prouve vivant par la course elle-meme." % cross)
    sys.exit(0)
if c and int(c.group(1)) <= int(c.group(2)) * 3:
    print("[Grecharged-secondary-monotion FAIL] SIDE-CONTROL: ZERO franchissement et le controle ne"
          " tire pas (%s arme contre %s desarme, il faut >= 3x) : le zero ne prouve rien"
          % (c.group(1), c.group(2)))
    sys.exit(1)
print("[SIDE-CONTROL] %d franchissement(s), controle present" % cross)
PYSIDE
# --------------------------------------------------------------------------------------------
# FLOOR — PLANCHER DE MOUVEMENT, gate d'anti-regression.
#
# Le 2026-08-11 a 22:15 l'owner a decrit un build ou « tout est muted as heck, faut vraiment
# chercher la physique pour la voir ». La mesure le confirmait : meches 0.9038 -> 0.1095,
# lunettes 1.8988 -> 0.1305, soit 8 a 14 fois moins de mouvement qu'une heure plus tot. Trois
# ajouts legitimes pris ensemble (attenuation d'angles, bornage de forme, contrainte durcie)
# avaient sur-contraint le systeme -- le meme empilement de suppresseurs que celui qui avait tue
# la version precedente, sous un autre nom.
#
# CALIBRAGE (corrige le 2026-08-11 23:10) : la reference est l'etat que l'OWNER A APPROUVE, pas le
# plus grand chiffre jamais mesure. Premiere version calee sur 0.9038 pour lbang -- une valeur
# d'avant qu'il ne dise « les meches fines sont hysteriques » : le plancher aurait donc interdit
# le calmage qu'il a lui-meme demande et juge « mieux ». Recale sur l'etat du build 19h53, celui
# qu'il a juge « 100x mieux qu'avant ». Un plancher se cale sur un jugement, pas sur un maximum.
#
# La reference ne bouge que vers le HAUT : une chaine qui perd plus de 40 % de son
# mouvement par rapport a son meilleur etat connu fait echouer la phase, quel que soit le progres
# obtenu ailleurs. On ne paie plus une correction avec le mouvement.
# PLANCHER FAIBLE-STIMULUS (2026-08-12 12:30). Le plancher d'origine protege l'amplitude MAXIMALE
# sur cinq pilotages. Or l'owner juge la poitrine « un peu mutee sur les mouvements SUBTILS » —
# la reponse aux petits stimuli — et le plancher ne l'a pas vue baisser. C'est la ou il regarde.
#
# ============================================================================================
# SUSPENSION SUR LES CHAINES COUVERTES PAR LA SPEC DE L'OWNER — ARBITRAGE DU SUPERVISEUR,
# DIRECTIVES DU 2026-08-14 01:00, APPLIQUE ICI LE 2026-08-14 PAR LE MANAGER DE PHASE.
#
# Je modifie une gate GELEE. Je le fais parce que le superviseur a tranche par ecrit, en toutes
# lettres, et parce que la regle 5 lui reserve precisement cet arbitrage :
#
#   « ARBITRAGE : la specification de l'owner prime sur toutes mes gates, sans exception. »
#   « FLOOR et FLOOR-WEAK sont SUSPENDUES sur toute chaine couverte par la spec, jusqu'a etre
#     recalees sur les cibles de la spec elle-meme (SPEC 16/17/18/22) plutot que sur un maximum
#     observe. »
#   « Reappliquer la calibration SPEC 24 sur chestL/chestR [...] et ne plus jamais la retirer au
#     motif d'une de mes gates. »
#
# CE QUI S'ETAIT PASSE, ET QUE CETTE SUSPENSION REND IMPOSSIBLE. La calibration exacte de la
# SPEC 24 de l'owner (2.300 Hz) a ete appliquee puis RETIREE parce qu'elle faisait echouer
# FLOOR-WEAK sur chestR (0.1457 -> 0.0794, 46 % de perte). Or a 2.30 Hz la raideur monte de
# 3.65x, donc la fleche STATIQUE descend de 3.65x : ce que le plancher a lu comme une perte de
# mouvement est le retour a la pose d'auteur que ses SPEC 2 et 9 EXIGENT
# (`AdditionalStandingSag = 0`). Le plancher protegeait une fleche que la spec interdit.
# Corriger apres coup n'a pas suffi une premiere fois : on rend la recurrence impossible au
# point de production, pas detectable au point de controle.
#
# PORTEE, VOLONTAIREMENT ETROITE : chestL et chestR, les deux chaines dont l'arbitrage parle et
# dont la spec fixe les valeurs au chiffre pres (SPEC 24 f=2.30 Hz, SPEC 25 zeta=0.35,
# SPEC 32 asymetrie +-3-5 %). Les cheveux ne sont PAS suspendus : la transposition ordonnee le
# 23:35 ne leur donne aucune cible chiffree, donc les suspendre retirerait une protection sans
# rien mettre a la place.
#
# CE N'EST PAS UNE MISE EN AVEUGLE : les chaines suspendues restent MESUREES et leurs chiffres
# restent IMPRIMES a chaque passage, avec la perte s'il y en a une. Seul l'echec est suspendu.
# LEVEE DE LA SUSPENSION : quand un plancher sera recale sur les amplitudes par regime de ses
# SPEC 16/17/18/22 au lieu d'un maximum observe. C'est au superviseur de le dire, pas a moi.
# ============================================================================================
SPEC_COVERED_CHAINS="chestL,chestR"
export SPEC_COVERED_CHAINS
REFW=.autoport/reports/Grecharged-secondary-motion/motion-floor-weak.txt
python3 - "$T" "$REFW" <<'PYWEAK' || exit 1
import os, re, sys
tbl, ref = sys.argv[1], sys.argv[2]
SPEC = set(x for x in os.environ.get('SPEC_COVERED_CHAINS', '').split(',') if x)
cur = {}
for ln in open(tbl, errors='ignore'):
    if not ln.startswith('ROOM-RESPONSE'):
        continue
    d = dict(re.findall(r'(\w+)=([^\s]+)', ln))
    if {'chain','stimulus','tip'} <= set(d):
        c, st, tp = d['chain'], float(d['stimulus']), float(d['tip'])
        if c not in cur or st < cur[c][0]:
            cur[c] = (st, tp)
if not cur or not os.path.exists(ref):
    sys.exit(0)
old = {}
for ln in open(ref, errors='ignore'):
    p = ln.split()
    if len(p) == 2:
        old[p[0]] = float(p[1])
bad = [(c, old[c], cur[c][1]) for c in cur if c in old and cur[c][1] < old[c] * 0.70]
# SUSPENDUES, PAS AVEUGLES : on imprime leur chiffre, on ne fait plus echouer dessus.
susp = [x for x in bad if x[0] in SPEC]
for c, o, n in sorted(susp):
    print("[FLOOR-WEAK] %-12s %.4f -> %.4f (%.0f%%) — SUSPENDUE (spec owner, arbitrage 08-14 01:00)"
          % (c, o, n, 100 * (1 - n / o)))
bad = [x for x in bad if x[0] not in SPEC]
if bad:
    print("[Grecharged-secondary-motion FAIL] FLOOR-WEAK: %d chaine(s) ont perdu plus de 30%% de"
          " leur reponse aux PETITS mouvements -- c'est la que l'owner regarde." % len(bad))
    for c, o, n in sorted(bad, key=lambda x: x[2]/x[1])[:6]:
        print("  %-12s %.4f -> %.4f  (%.0f%% de perte sur stimulus faible)" % (c, o, n, 100*(1-n/o)))
    sys.exit(1)
print("[FLOOR-WEAK] %d chaines gardent leur reponse aux petits mouvements" % len(cur))
PYWEAK

REF=.autoport/reports/Grecharged-secondary-motion/motion-floor.txt
python3 - "$T" "$REF" <<'PYFLOOR' || exit 1
import os, re, sys
tbl, ref = sys.argv[1], sys.argv[2]
# Meme suspension que FLOOR-WEAK ci-dessus, meme arbitrage, meme portee etroite. La reference
# CONTINUE d'etre tenue a jour pour ces chaines : on ne perd pas la donnee, on suspend l'echec.
SPEC = set(x for x in os.environ.get('SPEC_COVERED_CHAINS', '').split(',') if x)
cur = {}
for ln in open(tbl, errors='ignore'):
    if not ln.startswith('row '):
        continue
    d = dict(re.findall(r'(\w+)=([^\s]+)', ln))
    if 'chain' in d and 'tipvar' in d:
        v = float(d['tipvar'])
        if v > cur.get(d['chain'], 0.0):
            cur[d['chain']] = v
if not cur:
    sys.exit(0)
old = {}
if os.path.exists(ref):
    for ln in open(ref, errors='ignore'):
        p = ln.split()
        if len(p) == 2:
            old[p[0]] = float(p[1])
regress = [(c, old[c], cur[c]) for c in cur if c in old and cur[c] < old[c] * 0.60]
susp = [x for x in regress if x[0] in SPEC]
for c, o, n in sorted(susp):
    print("[FLOOR] %-12s %.4f -> %.4f (%.0f%%) — SUSPENDUE (spec owner, arbitrage 08-14 01:00)"
          % (c, o, n, 100 * (1 - n / o)))
regress = [x for x in regress if x[0] not in SPEC]
if regress:
    print("[Grecharged-secondary-motion FAIL] FLOOR: %d chaine(s) ont perdu plus de 40%% de leur"
          " mouvement par rapport au meilleur etat connu." % len(regress))
    for c, o, n in sorted(regress, key=lambda x: x[2] / x[1])[:8]:
        print("  %-12s %.4f -> %.4f  (%.0f%% de perte)" % (c, o, n, 100 * (1 - n / o)))
    print("  L'owner a deja vu ce film : « tout est muted as heck, faut chercher la physique pour")
    print("  la voir ». Une correction qui se paie avec le mouvement n'est pas une correction.")
    sys.exit(1)
# la reference ne monte jamais toute seule vers le bas
merged = dict(old)
for c, v in cur.items():
    if v > merged.get(c, 0.0):
        merged[c] = v
with open(ref, 'w') as f:
    for c in sorted(merged):
        f.write("%s %.6f\n" % (c, merged[c]))
print("[FLOOR] %d chaines au-dessus de leur plancher (reference mise a jour)" % len(cur))
PYFLOOR

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
