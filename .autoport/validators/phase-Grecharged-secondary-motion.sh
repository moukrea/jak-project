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
  if [ "$_n" -gt 2500 ]; then
    fail "CLEAN: le moteur fait $_n lignes. L'ancien en faisait 6000 et c'est ce qui a tué le
  mouvement (clamps 9→84, détection d'anim 45→172, 42% des mesures à zéro). Si ce plafond gêne,
  c'est un signal, pas un obstacle à contourner."
  fi
fi

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
    if ln.startswith("+collider "):
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
blob = " ".join(chains).lower()
for part, pats in (("oreilles", ("ear",)), ("cheveux", ("hair",)), ("mèches", ("bang", "strand")),
                   ("seins", ("chest", "breast")), ("lunettes", ("goggle",))):
    if not any(p in blob for p in pats):
        die("MOVE: aucune chaîne pour « %s », que l'owner a nommée explicitement" % part)

# --------------------------------------------------------------------------------------------
# ROOT — SPEC §2 : « attention ça reste ancré à la racine ».
bad = sorted((r['chain'], float(r['rootdev'])) for r in rows if float(r['rootdev']) > 2.0)
if bad:
    die("ROOT: %d mesure(s) avec une racine qui dérive (rootdev > 2.0), p.ex. %s à %.3f.\n"
        "  « Les cheveux restent ancrés à la racine » — ancré ET mobile, les deux ensemble."
        % (len(bad), bad[0][0], bad[0][1]))

# --------------------------------------------------------------------------------------------
# COLLIDE — SPEC §3 : la liste exacte, chacune mesurée et à zéro, avec un contrôle qui a tiré.
pairs = (("cheveux/mèches vs crâne, visage, épaules, oreilles", r'hair|bang|strand'),
         ("lunettes vs corps et seins", r'goggle'),
         ("oreilles vs mèches", r'ear'))
for label, pat in pairs:
    rs = [r for r in rows if re.search(pat, r['chain'], re.I)]
    if not rs:
        die("COLLIDE: rien de mesuré pour « %s »" % label)
    worst = max(float(r['meshpen']) for r in rs)
    if worst > 0.0:
        die("COLLIDE: « %s » traverse encore, pénétration max %.3f.\n"
            "  « Collisions propres » — et une résolution pire que le clip est pire que rien."
            % (label, worst))

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
if int(an.group(1)) == 0 or int(an.group(2)) != int(an.group(1)):
    die("ANIM: %s chaînes pilotées par une animation, %s respectées. « Si un bone bouge sur une\n"
        "  intention d'animation, ça a la priorité sur la physique car voulu par l'animation\n"
        "  originale de Naughty Dog. »" % (an.group(1), an.group(2)))

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
