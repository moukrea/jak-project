#!/usr/bin/env python3
"""preset_channel_audit.py — QUEL CANAL PORTE CHAQUE CLE DU PRESET, ET LEQUEL N'EXISTE PAS.

DIRECTIVES 2026-08-22 23:00 : « chaque cle du preset devient un CANAL que le moteur LIT dans le
fichier livre [...] une cle sans canal se declare CANAL ABSENT — un manque d'implementation NOMME,
jamais une section "non tenue" comme si le solveur echouait. »

Ce script ne donne pas un avis, il VERIFIE, cle par cle :

  CANAL FICHIER      la cle est dans `kPhysPresetKeys` (kmachine.cpp) ET le fichier livre porte
                     `pk <Cle> <valeur>`. C'est un bouton : le tourner ne demande aucun build.
  CONSTANTE MOTEUR   aucun canal, mais une constante du moteur porte la valeur. Si cette constante
                     EGALE la valeur du preset, alors toute mesure de cette grandeur REPUBLIE sa
                     propre cible : elle est TAUTOLOGIQUE, et le script le dit mecaniquement en
                     comparant les deux nombres, pas de memoire.
  CANAL ABSENT       ni l'un ni l'autre. Manque d'implementation nomme.

Les deux premiers verdicts sont verifies par lecture des fichiers ; un desaccord fait sortir le
script en echec plutot que d'imprimer un tableau faux.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, '.autoport'))

import importlib.util
_spec = importlib.util.spec_from_file_location('pa', os.path.join(REPO, '.autoport', 'preset_apply.py'))
pa = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pa)

ENGINE = os.path.join(REPO, 'goal_src', 'jak1', 'pc', 'jak-hd-physics.gc')
ROOM = os.path.join(REPO, 'goal_src', 'jak1', 'pc', 'phys-room.gc')
KM = os.path.join(REPO, 'game', 'kernel', 'jak1', 'kmachine.cpp')
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')
GEN = os.path.join(REPO, '.autoport', 'physics_keira_gen2.py')

# Les sites CONSTANTE MOTEUR, cites nommement. `sym` = un `defconstant`, `lit` = un litteral a
# une ligne donnee. La valeur attendue est CALCULEE depuis le preset, jamais retapee : c'est ce
# qui rend le verdict TAUTOLOGIQUE demontrable au lieu d'affirme.
CONSTS = {
    'APCompliance':              ('sym', 'PHYS-MOB-AP',      lambda v: v),
    'LateralCompliance':         ('sym', 'PHYS-MOB-LAT',     lambda v: v),
    'TorsionalCompliance':       ('sym', 'PHYS-MOB-TOR',     lambda v: v),
    'AbsoluteStretchClamp':      ('sym', 'PHYS-DYN-MAX',     lambda v: v),
    'BreastBreastRestitution':   ('sym', 'PHYS-RST-BB',      lambda v: v),
    'BreastChestRestitution':    ('sym', 'PHYS-RST-CH',      lambda v: v),
    # `phys-vol-floor` : la MEME cle que le canal 0, gardee en dur sous sa forme complementaire
    # 1 - SupineProjectionScale. Tourner le bouton deplace le tenseur et PAS ce plancher.
    'SupineProjectionScale#2':   ('sym', 'PHYS-FLESH-YIELD', lambda v: round(1.0 - v, 6)),
    'NormalMaxApexDisplacement': ('lit', '(* 0.42 b0e)',     lambda v: v),
    'NormalMaxCOMDisplacement':  ('lit', '(* 0.35 b0e)',     lambda v: v),
}

# Canaux FICHIER indirects : la cle descend dans le fichier livre, mais sous un autre nom que
# `pk`, parce que le moteur la consomme sous une forme derivee. Chacun cite sa cle de chaine.
# Cles dont l'exigence porte sur l'ASSET (poids de peau, rig) et non sur le solveur : elles n'ont
# pas de canal de runtime et ne peuvent pas en avoir. Ce n'est pas un manque d'implementation.
ASSET = {
    'StrongRootFraction': ('barre de repesage : >= 30 % des sommets de la chaine doivent avoir le '
                           'nouvel os pour joint MAJORITAIRE (DIRECTIVES 2026-08-18 08:55). '
                           'Verifiee a la cuisson, pas a l\'execution.'),
    'RootAnchorLo': ('profil d\'ancrage de la 30, mesure sur le mesh livre', ),
    'RootAnchorHi': ('profil d\'ancrage de la 30, mesure sur le mesh livre', ),
    'RearIntermediateAnchorLo': ('profil d\'ancrage de la 30', ),
    'RearIntermediateAnchorHi': ('profil d\'ancrage de la 30', ),
    'MidVolumeAnchorLo': ('profil d\'ancrage de la 30', ),
    'MidVolumeAnchorHi': ('profil d\'ancrage de la 30', ),
    'DistalAnchorLo': ('profil d\'ancrage de la 30', ),
    'DistalAnchorHi': ('profil d\'ancrage de la 30', ),
    'RootDeformationExponentLo': ('gradient racine->apex de la 31, cuit dans les poids', ),
    'RootDeformationExponentHi': ('gradient racine->apex de la 31, cuit dans les poids', ),
}

# =================================================================================================
# CYCLE 114 — CET AUDIT CHERCHAIT LE SITE, IL DOIT CHERCHER LA VALEUR.
#
# CE QUI ETAIT FAUX ICI, ET C'EST LE MEME DEFAUT QU'AU CYCLE 111, UN CRAN PLUS BAS. Le dictionnaire
# `CONSTS` ci-dessus est une LISTE ECRITE A LA MAIN de sites, cherches par leur TEXTE EXACT
# (`'(* 0.42 b0e)'`). Le cycle 109b a converti ces textes-la et le compte est tombe a
# `CONSTANTE MOTEUR 0/90`. Mais une recherche indexee sur le SITE ne peut trouver que les sites
# qu'on lui a nommes : elle est aveugle a toute AUTRE copie de la meme valeur. Trois lui ont
# echappe, et la troisieme se denoncait elle-meme :
#
#   * `jak-hd-physics.gc` mur d'apex de la 22 DANS la boucle : `(* 0.42 b0f)` / `(* 0.08 b0f)` —
#     meme grandeur que `phys-cap-e22!`, qui lit deja les cles 16/17. UN BOUTON A MOITIE BRANCHE.
#   * les deux compteurs de la NOTE-91 : `(> ee 0.40)` / `(> cw 0.40)`, ou 0.40 est textuellement
#     « le plafond DUR de sa 22 » — c'est-a-dire la cle 20, deja cablee. Un SEUIL D'INSTRUMENT
#     fige est le meme defaut, du cote de la mesure.
#   * `phys-apex-scale` `(* 0.50 B0)` et le plafond de torsion `(* 0.50 b0f)` : la NOTE-160 ECRIT
#     « Sa borne est donc CELLE DE L'APEX [...] HardMaxApexDisplacement 0.50 B0 ». La note nommait
#     la cle ; le tableau publiait « CANAL ABSENT — aucun lecteur » pour cette meme cle.
#
# CE QUI REMPLACE LA LISTE : `sweep_hardcoded()` balaye TOUT le code du moteur ET de la salle, et
# rapporte CHAQUE litteral egal a une valeur du preset. La charge de la preuve est inversee — un
# site n'a plus besoin d'etre RETROUVE pour compter, il doit etre JUSTIFIE pour etre ignore. Toute
# coincidence est nommee ci-dessous avec sa raison ; tout hit non justifie sort en `NON TRIE` et
# fait echouer le script.
#
# LA CLE DE L'ALLOWLIST EST LE TEXTE DU CODE, JAMAIS UN NUMERO DE LIGNE : un numero derive au
# premier ajout et l'allowlist redeviendrait un tampon encreur.
# =================================================================================================

SWEEP_TRIVIAL = {0.0, 1.0, 2.0, 3.0, 4.0, 120.0}   # 0/1/2/3/4 et 120 Hz : partout, sans portee

# CONSTANTES CALEES SUR UNE CIBLE DU PRESET. Elles ne sont EGALES a aucune valeur du preset, donc
# aucun balayage par valeur ne peut les voir — mais elles sont reglees pour que la mesure tombe sur
# la cible, ce qui est la meme tautologie par un autre chemin (`never-fit-a-parameter-to-the-
# instrument`). Elles se publient nommement, avec l'arithmetique qui les trahit.
CALIBRATED = (
    ('PHYS-DYN-K', 'NormalDynamicStretch / NormalMaxCOMDisplacement = 0.15 / 0.35 = 0.428571 -> 0.43 : '
                   'le gain est regle pour que `sdy` (l etirement dynamique de la 22, :3722) vaille '
                   'exactement 0.15 quand l excursion radiale vaut exactement 0.35 B0. TAUTOLOGIE '
                   'CONDITIONNELLE : elle ne mord que si l excursion traine autour de 0.35 B0.'),
    ('PHYS-SEC-K', 'gain d excitation du mode secondaire (36). NOTE-169 : « cale sur sa bande ». Pas '
                   'une republication (un gain sur une vitesse n est pas une amplitude), mais la meme '
                   'faute de methode. A re-examiner si la 36 devait etre declaree tenue sur une amplitude.'),
)

SWEEP_COINCIDENCE = {
    # --- moteur : des MOITIES arithmetiques, pas des plafonds ------------------------------------
    '(h (* 0.5 a))': 'moitie arithmetique (demi-amplitude), aucune grandeur de preset',
    '(u (* 0.5 (* wh (sqrtf (fmax 0.0 (- 1.0 (* z z)))))))': 'moitie arithmetique de la pulsation amortie',
    '(omx (* 0.5 (- r21 r12)))': 'partie antisymetrique d une 3x3 : le 1/2 est la formule',
    '(omy (* 0.5 (- r02 r20)))': 'partie antisymetrique d une 3x3 : le 1/2 est la formule',
    '(omz (* 0.5 (- r10 r01)))': 'partie antisymetrique d une 3x3 : le 1/2 est la formule',
    '(kr (fmin 0.5 (/ bv (* pp ln))))': 'plafond de rapport sans dimension, sans equivalent au preset',
    # --- moteur : des SEUILS et des TOLERANCES ----------------------------------------------------
    '(defconstant PHYS-AUTH-TOL 0.05)': 'tolerance de detection de pose d auteur (unites moteur), pas une amplitude',
    '(defconstant PHYS-SIDE-COS 0.05)': 'seuil sur un COSINUS, sans dimension et sans cle correspondante',
    '(defconstant PHYS-COL-MARGIN 0.5)': 'marge de collision en UNITES MOTEUR, pas en B0',
    '(defconstant PHYS-DYN-TAU 0.30)': 'constante de TEMPS de la 38 (frames), homonyme numerique seulement',
    '(define *phys-med-inj* 0.5)': 'amplitude d INJECTION du controle positif medial, pas une grandeur livree',
    '(when (> pp 0.05)': 'seuil de POIDS de peau (un vertex compte si w>0.05)',
    '(when (> zl 0.05)': 'seuil de LONGUEUR, garde de division',
    '(when (< (fabs dphi) 0.5)': 'garde d angle (radians) sur la reconstruction de holonomie',
    '(when (> (-> *phys-rstp* scl w) 0.5)': 'test d un DRAPEAU stocke en flottant (0 ou 1)',
    '(if (or (< n 0.5) (< axis 0) (> axis 2))': 'test d un ENTIER stocke en flottant (n = 0 ?)',
    # --- moteur : deux constantes de SPEC, declarees et dont la morsure est COMPTEE ---------------
    '(defconstant PHYS-PRS-MAX 0.25)':
        'borne BASSE de la bande de la 12 (« gravity-side lateral flattening -15 a -25 % ») : c est '
        'un nombre de la SPEC, pas une cle du preset (aucun `pk` ne le porte), et sa morsure est '
        'publiee — `prsr` (non ecrete) est emis A COTE de `prsm` (ecrete) par PHYSSHAPE4, et '
        '`*phys-prsn*` compte les frames ou elle mord.',
    '(defconstant PHYS-SEC-K   0.05)':
        'GAIN d excitation du mode secondaire (36) : il multiplie une vitesse, il ne borne rien ; '
        'la cle homonyme `SecondaryJiggleAmplitudeHi` est une AMPLITUDE DE SORTIE. NON TRANCHE '
        'reste possible et NOTE-169 dit « cale sur sa bande » : a re-examiner si la 36 devait etre '
        'declaree tenue sur une amplitude — ce n est pas le cas aujourd hui.',
    # --- salle : enveloppes (1-cos)/2, normes au carre, drapeaux ---------------------------------
    '(w (* 0.5 (- 1.0 (cos (* 32768.0 u)))))': 'enveloppe (1-cos)/2 : le 1/2 est la formule',
    '(s  (* 0.5 (- 1.0 (cos (* 32768.0 tt)))))': 'enveloppe (1-cos)/2',
    '(s (* 0.5 (- 1.0 (cos (* 32768.0 u))))))': 'enveloppe (1-cos)/2',
    '(b (* 0.5 (+ 1.0 (cos (* 32768.0 u))))))': 'enveloppe (1+cos)/2',
    '(a (* PHYSROOM-TILTDEG 0.5 (+ 1.0 (cos (* 32768.0 u))))))': 'enveloppe (1+cos)/2 sur l inclinaison',
    '(let ((yp (* 0.5 (* v0 tp))))': 'cinematique : 1/2 v t',
    '(z1 (* 0.5 (* a1 (* t1 t1))))': 'cinematique : 1/2 a t^2',
    '(* 0.5 (* a1 (* t t)))': 'cinematique : 1/2 a t^2',
    '(gok (if (> (fabs gv) 0.5) 1 0))': 'test d un DRAPEAU stocke en flottant',
    '((and (> qn 0.5) (< qn 2.0))': 'test d un ENTIER stocke en flottant',
    '(set! (-> self root trans y) (+ (-> self home y) (* 0.4 amp (sin (* 2.0 ph))))))':
        'facteur de FORME du pilotage de la salle, aucune grandeur de preset',
    '(set! (-> self root trans z) (+ (-> self home z) (* 0.5 amp (cos ph))))))))':
        'facteur de FORME du pilotage de la salle',
    '(phys-osc-k2 0.65 0.5445367)':
        'AUTO-TEST des deux convertisseurs (PHYSOSCK2) : entrees fixes, sorties attendues ecrites '
        'avant la course. Ces nombres ne descendent dans aucun solveur.',
    '(phys-decay (* 2.0 (* 0.65 0.5445367)))': 'AUTO-TEST du convertisseur (PHYSOSCK2)',
    '(phys-osc-k2 0.35 0.2838553))': 'AUTO-TEST du convertisseur (PHYSOSCK2)',
}

# Les hits dont la forme se repete a l identique (meme texte, plusieurs lignes) : une seule entree
# d allowlist suffit, et c est voulu — le texte EST la justification.
SWEEP_REPEATED = (
    '(< (phys-stat slot chain 0) 0.5))',
    '(if (< (phys-stat slot chain 0) 0.5)',
    '(when (> (+ (* lx lx) (+ (* ly ly) (* lz lz))) 0.5)',
    '(when (> (+ (* ux ux) (+ (* uy uy) (* uz uz))) 0.5)',
    '(* 0.5 (- 1.0 (cos (* 32768.0 (/ (the float f) PHYSROOM-IMPFF))))))',
    '(* 0.5 (+ 1.0 (cos (* 32768.0 (/ (the float (- f PHYSROOM-AXW))',
    '(* 0.5 (- 1.0 (cos (* 32768.0 (/ (the float f) PHYSROOM-SGNIF)))))))',
    '(* 0.5 (+ 1.0 (cos (* 32768.0 (/ (the float (- f PHYSROOM-SGNM))',
    '(* 0.5 (* v0 (- t (* (/ tp 3.14159265) (sin (* 32768.0 (/ t tp))))))))',
    '(+ yp (- (* v0 tau) (* 0.5 (* PHYSROOM-REGG (* tau tau)))))))',
    '(let* ((yf (+ yp (- (* v0 tf) (* 0.5 (* PHYSROOM-REGG (* tf tf))))))',
    '(* 0.5 (* vl (- sg (* (/ tl 3.14159265) (sin (* 32768.0 (/ sg tl))))))))))))))',
    '(+ z1 (- (* v1 tau) (* 0.5 (* a2 (* tau tau)))))))))',
    '(* (-> self raz) (-> self raz)))) 0.5)',
    '(when (<= pp 0.05)',
)


def sweep_hardcoded(byval):
    """Chaque litteral du CODE egal a une valeur du preset, moteur ET salle.

    NATURE : une liste de sites, pas un jugement. REPERE : aucun, c est du texte source.
    LECTURE QUAND LE DEFAUT EST ABSENT : toute ligne rendue est soit dans l allowlist ci-dessus
    avec sa raison ecrite, soit imputee a une cle et publiee comme CONSTANTE MOTEUR / CANAL PARTIEL.
    """
    allow = dict(SWEEP_COINCIDENCE)
    for t in SWEEP_REPEATED:
        allow.setdefault(t, 'forme repetee, meme justification que son jumeau')
    hits, untriaged = {}, []
    for path, short in ((ENGINE, 'jak-hd-physics.gc'), (ROOM, 'phys-room.gc')):
        # LES DOCSTRINGS SONT DE LA PROSE, PAS DU CODE, et elles citent souvent la valeur voisine.
        # On suit la PARITE DES GUILLEMETS depuis le debut du fichier : une chaine GOAL peut courir
        # sur vingt lignes, et un `split(';;')` ne la voit pas. Quatre faux positifs du cycle 114
        # venaient exactement de la.
        instr = False
        for i, raw in enumerate(open(path, encoding='utf-8'), 1):
            line, code, j = raw, [], 0
            while j < len(line):
                c = line[j]
                if instr:
                    if c == '\\':
                        j += 2
                        continue
                    if c == '"':
                        instr = False
                elif c == '"':
                    instr = True
                elif c == ';' and j + 1 < len(line) and line[j + 1] == ';':
                    break
                else:
                    code.append(c)
                j += 1
            code = ''.join(code)
            if not code.strip():
                continue
            found = set()
            for m in re.finditer(r'(?<![\w.\-])(\d+\.\d+)', code):
                f = float(m.group(1))
                if f in SWEEP_TRIVIAL:
                    continue
                if f in byval:
                    found |= byval[f]
            if not found:
                continue
            txt = code.strip()
            if txt in allow:
                continue
            matched = [t for t in allow if t and t in txt]
            if matched:
                continue
            for k in found:
                hits.setdefault(k, []).append((short, i, txt[:110]))
            untriaged.append((short, i, txt[:110], sorted(found)))
    return hits, untriaged


# =================================================================================================
# CYCLE 111 — UN CANAL « INDIRECT » NE SE DECLARE PLUS, IL SE PROUVE PAR PERTURBATION.
#
# CE QUI ETAIT FAUX ICI, ET C'ETAIT UN FAUX VERT DANS LE SEUL INSTRUMENT QUI MESURE L'AVANCEMENT.
# Ce fichier portait un dictionnaire `INDIRECT` ECRIT A LA MAIN : trois cles y etaient declarees
# `CANAL FICHIER (indirect)` sur la foi d'une note (« stiffness / sqrt(mass) sur la ligne chain —
# f = 2.300 Hz mesure »), et le script les comptait comme des boutons branches. C'est exactement
# la regle 0 du contrat prise a l'envers : un commentaire tenait lieu de preuve.
#
# LA MESURE QUI L'A TRANCHE (cycle 111, aucune course, aucun build) : poser le preset de MAIA sur
# la chaine de KEIRA fait passer `pk GlobalFrequencyVertical` de 2.3 a 1.85 (-20 %),
# `pk GlobalDampingRatio` de 0.35 a 0.33 et `pk MassPerBreast` de 0.5 a 1.05 (x2.1) — et la ligne
# `chain chestL ... stiffness=2.7696 damping=0.1686 mass=1.45 ...` ressortait IDENTIQUE AU BIT.
# Les trois cles ne touchaient rien. Leurs valeurs livrees venaient d'une derivation HUMAINE faite
# le 2026-08-14 et figee dans `keira-owner-tuning.txt:1237-1241` ; `apply_owner_tuning.py` ne
# contient pas une seule occurrence de `pk`.
#
# CE QUI REMPLACE LA DECLARATION : `prove_indirect()` PERTURBE la cle (x1.5) et refait passer le
# producteur reel. Si l'artefact que le moteur lit ne bouge pas, la cle est `CANAL ABSENT`, quelle
# que soit la note qui l'accompagne. Une note ne peut plus accorder un canal.
# =================================================================================================

# Cles qui PRETENDENT un chemin indirect (elles n'entrent pas dans `kPhysPresetKeys`, mais un
# producteur pourrait ecrire une ligne que le moteur lit). Chacune est PROUVEE ou REFUTEE ci-dessous.
INDIRECT_CANDIDATES = {
    'GlobalFrequencyVertical': 'stiffness= sur la ligne `chain` (SPEC 24 : f = stiffness/sqrt(mass))',
    'GlobalDampingRatio':      'damping= sur la ligne `chain` (SPEC 25)',
}

# JAUGE — inerte PAR CONSTRUCTION, et ce n'est pas un manque d'implementation.
# DIRECTIVES 2026-08-19 20:25 : « le solveur ne lit la masse QUE dans w = 2*pi*stiffness/sqrt(mass)
# [...] Passer de 1,45 a la valeur nominale 0,50 kg de sa SPEC 5 ne ferait que reechelonner la
# raideur a frequence constante : ZERO effet observable. » Une jauge ne se compte donc JAMAIS comme
# un canal gagne — meme statut que `TENUE PAR CONSTRUCTION` au registre : declaree, jamais comptee
# comme une victoire. La compter en canal gonflerait le seul chiffre que l'owner lit.
JAUGE = {
    'MassPerBreast': ('mass= sur la ligne `chain` — JAUGE : le solveur ne lit la masse que dans '
                      'stiffness/sqrt(mass), sa valeur absolue est inerte (DIRECTIVES 2026-08-19 '
                      '20:25). Declaree, jamais comptee comme un canal.'),
}


def prove_indirect(key, mine, who):
    """PERTURBE `key` et regarde si l'artefact que le moteur lit bouge. Rend (prouve, detail).

    NATURE  : un booleen de causalite, obtenu en changeant l'entree et en comparant la sortie.
    HORS DEFAUT : une cle sans lecteur rend une sortie IDENTIQUE, donc `prouve = False`.
    LIGNE DE BASE : la sortie du meme producteur avec la valeur non perturbee.
    """
    lines = open(CHAINS, encoding='utf-8').read().split('\n')
    ref, _ = pa.derive_mechanics(lines, mine, who)
    if key not in mine:
        return False, 'cle absente du preset'
    v = mine[key]
    pert = dict(mine)
    pert[key] = (v[0] * 1.5,) + tuple(v[1:])
    got, _ = pa.derive_mechanics(lines, pert, who)
    chg = [(a, b) for a, b in zip(ref, got) if a != b]
    if not chg:
        return False, ('perturbee x1.5, AUCUNE ligne du fichier livre ne bouge — la note qui '
                       'annoncait un canal ne decrivait pas une lecture')
    ex = chg[0][1].split()[1] if len(chg[0][1].split()) > 1 else '?'
    return True, ('PROUVE PAR PERTURBATION : x1.5 sur la cle change %d ligne(s) `chain` (p.ex. %s)'
                  % (len(chg), ex))


def stamp():
    """L'EMPREINTE DES QUATRE FICHIERS DONT CE TABLEAU PARLE.

    Paye au cycle 114 : `preset-channels.md` publiait `CANAL FICHIER (indirect) 3/90` avec
    `GlobalDampingRatio` en indirect, alors que le script QUI L'ENGENDRE le refutait deja par
    perturbation et rendait 1/90. Le document avait ete copie a la main a un moment, puis le
    script avait avance sans lui. Un chemin n'est pas un horodatage : c'est l'empreinte qui dit
    de quel arbre ce tableau parle.
    """
    import hashlib
    out = []
    for f, n in ((ENGINE, 'jak-hd-physics.gc'), (ROOM, 'phys-room.gc'),
                 (KM, 'kmachine.cpp'), (CHAINS, 'physics_chains.txt')):
        out.append('%s %s' % (n, hashlib.md5(open(f, 'rb').read()).hexdigest()[:12]))
    return out


def main():
    P = pa.read_presets()
    names = list(P)
    keira = [k for k in names if k.lower().startswith('keira')][0]
    maia = [k for k in names if k.lower().startswith('maia')][0]
    SK, SM = pa.scalars(P[keira]), pa.scalars(P[maia])
    # `MINE` porte AUSSI les cles derivees : c'est ce que le producteur consomme reellement, donc
    # c'est sur lui que la perturbation doit porter, sinon on testerait une autre entree que la sienne.
    MINE = pa.add_derived(pa.scalars(P[keira]), P[keira])

    eng = open(ENGINE, encoding='utf-8').read()
    km = open(KM, encoding='utf-8').read()
    ch = open(CHAINS, encoding='utf-8').read()
    gen = open(GEN, encoding='utf-8').read()

    wired = re.findall(r'"([A-Za-z][A-Za-z0-9]*)",\s*//\s*\d', km)
    wired = set(wired)

    rows, errs = [], []
    n = {'CANAL FICHIER': 0, 'CANAL FICHIER (indirect)': 0, 'CONSTANTE MOTEUR': 0,
         'HORS RUNTIME (asset)': 0, 'JAUGE (inerte par construction)': 0, 'CANAL ABSENT': 0}
    tauto = 0

    for k in sorted(SK):
        kv, mv = SK[k][0], SM.get(k, (None,))[0]
        differe = (mv is not None and kv != mv)
        note = ''
        if k in wired:
            if not re.search(r'^pk %s\s' % re.escape(k), ch, re.M):
                errs.append('%s est CABLE mais absent du fichier livre' % k)
            st = 'CANAL FICHIER'
            note = 'lu par le moteur (kPhysPresetKeys), pose par preset_apply.py'
        elif k in INDIRECT_CANDIDATES:
            # LE CANAL SE PROUVE, IL NE SE DECLARE PAS. Voir prove_indirect() plus haut.
            ok, why = prove_indirect(k, MINE, keira)
            st = 'CANAL FICHIER (indirect)' if ok else 'CANAL ABSENT'
            note = '%s — %s' % (INDIRECT_CANDIDATES[k], why)
        elif k in JAUGE:
            st = 'JAUGE (inerte par construction)'
            note = JAUGE[k]
        elif k in ASSET:
            st = 'HORS RUNTIME (asset)'
            note = ASSET[k][0] if isinstance(ASSET[k], tuple) else ASSET[k]
        elif k in CONSTS or (k + '#2') in CONSTS:
            kk = k if k in CONSTS else k + '#2'
            kind, site, f = CONSTS[kk]
            want = f(kv)
            st = 'CONSTANTE MOTEUR'
            if kind == 'sym':
                m = re.search(r'\(defconstant\s+%s\s+([0-9.]+)\)' % re.escape(site), eng)
                if not m:
                    errs.append('%s: constante %s introuvable dans le moteur' % (k, site))
                    note = '%s INTROUVABLE' % site
                else:
                    got = float(m.group(1))
                    same = abs(got - want) < 1e-9
                    tauto += 1 if same else 0
                    note = '%s = %g (preset %g)%s' % (site, got, want,
                                                      ' — TAUTOLOGIQUE' if same else
                                                      ' — VALEUR DIVERGENTE')
            elif kind == 'lit':
                if site not in eng:
                    errs.append('%s: litteral %s introuvable' % (k, site))
                    note = '%s INTROUVABLE' % site
                else:
                    tauto += 1
                    note = 'litteral %s dans le moteur (preset %g) — TAUTOLOGIQUE' % (site, want)
            else:
                if site not in gen:
                    errs.append('%s: %s introuvable dans le generateur' % (k, site))
                    note = '%s INTROUVABLE dans le generateur' % site
                else:
                    tauto += 1
                    note = 'constante du GENERATEUR (%s) — TAUTOLOGIQUE' % site
        else:
            st = 'CANAL ABSENT'
            note = 'aucun lecteur'
        n[st] = n.get(st, 0) + 1
        rows.append([k, kv, mv, differe, st, note])

    # --- CYCLE 114 : LE BALAYAGE PAR VALEUR A LE DERNIER MOT ------------------------------------
    # Il vient APRES la boucle et il peut DEGRADER un statut, jamais l'ameliorer. Un `CANAL FICHIER`
    # dont une copie survit en dur devient `CANAL PARTIEL` : un bouton a moitie branche ment plus
    # qu'un bouton absent, parce qu'on le compte comme gagne.
    byval = {}
    for k in SK:
        v = SK[k][0]
        if v is None or v in SWEEP_TRIVIAL:
            continue
        byval.setdefault(v, set()).add(k)
    for k in MINE:                      # les cles DERIVEES portent aussi des valeurs a chercher
        v = MINE[k][0]
        if v is None or v in SWEEP_TRIVIAL:
            continue
        byval.setdefault(v, set()).add(k)
    hits, untriaged = sweep_hardcoded(byval)
    # UN `NON TRIE` FAIT ECHOUER LE SCRIPT, ET PAS SEULEMENT IMPRIMER UNE LIGNE. Sans ca, la
    # phrase « tout hit non justifie sort en NON TRIE et fait echouer le script » serait un
    # COMMENTAIRE, c'est-a-dire exactement ce que la regle 0 du contrat interdit de prendre pour
    # une preuve. Le rendre vrai coute deux lignes.
    for f, l, txt, ks in untriaged:
        errs.append('site NON TRIE : %s:%d  %s  [%s] — justifie-le dans SWEEP_COINCIDENCE '
                    'ou cable la cle' % (f, l, txt, ','.join(ks)))
    for r in rows:
        h = hits.get(r[0])
        if not h:
            continue
        where = ' ; '.join('%s:%d' % (f, l) for f, l, _ in h)
        if r[4] == 'CANAL FICHIER':
            r[4] = 'CANAL PARTIEL'
            r[5] = 'CABLE, MAIS une copie survit en dur : %s' % where
        elif r[4] == 'CANAL ABSENT':
            r[4] = 'CONSTANTE MOTEUR'
            r[5] = 'aucun canal, la valeur est ECRITE EN DUR : %s' % where
        else:
            r[5] += ' — copie en dur signalee : %s' % where
    n = {}
    for r in rows:
        n[r[4]] = n.get(r[4], 0) + 1

    if 'SupineProjectionScale#2' in CONSTS:
        # la deuxieme copie de la meme cle est signalee A PART : elle ne change pas le compte des
        # cles, elle nomme un canal PARTIEL.
        pass

    print('PROVENANCE — ce tableau decrit CES fichiers-la, et l\'empreinte le prouve :')
    for l in stamp():
        print('  %s' % l)
    print('Regenere par : python3 .autoport/preset_channel_audit.py > .../preset-channels.md')
    print()
    print('BALAYAGE PAR VALEUR (cycle 114) — moteur + salle, tout litteral egal a une valeur du')
    print('preset. Une coincidence doit etre JUSTIFIEE pour etre ignoree, elle n\'est plus ignoree')
    print('par oubli. Entrees d\'allowlist : %d. Sites non tries : %d.'
          % (len(SWEEP_COINCIDENCE) + len(SWEEP_REPEATED), len(untriaged)))
    for f, l, txt, ks in untriaged:
        print('  NON TRIE  %s:%d  %s   [%s]' % (f, l, txt, ','.join(ks)))
    print('  ANGLE MORT DECLARE : les valeurs %s sont FILTREES (elles sont partout et sans portee),'
          % ', '.join(('%g' % v) for v in sorted(SWEEP_TRIVIAL)))
    print('  donc une cle qui vaut 1, 2, 3, 4 ou 120 ne peut PAS etre trouvee par ce balayage. Les')
    print('  trois qui etaient dans ce cas (VerticalCompliance 1, MinimumSubstepsAt60FPS 2,')
    print('  HardImpactSubstepsHi 4) ont ete trouvees A LA LECTURE et cablees au cycle 114 ; les')
    print('  suivantes ne le seront pas par cet outil. Le balayage reduit l\'angle mort, il ne le')
    print('  supprime pas, et le dire ici vaut mieux que laisser croire a une preuve d\'exhaustivite.')
    print()
    print('CONSTANTES AJUSTEES SUR UN RAPPORT DE DEUX CLES — pas un litteral, donc invisibles au')
    print('balayage, et publiees ici pour qu\'elles ne disparaissent pas :')
    for sym, formula in CALIBRATED:
        m = re.search(r'\(defconstant\s+%s\s+([0-9.]+)\)' % re.escape(sym), eng)
        print('  %-14s = %-6s  %s' % (sym, m.group(1) if m else 'ABSENTE', formula))
    print()
    print('| cle | Keira | Maia | differe | etat du canal | site |')
    print('|---|---|---|---|---|---|')
    for k, kv, mv, d, st, note in rows:
        print('| `%s` | %s | %s | %s | **%s** | %s |'
              % (k, pa.fmt(kv), pa.fmt(mv) if mv is not None else '—',
                 'oui' if d else 'non', st, note))
    print()
    tot = len(rows)
    for st in ('CANAL FICHIER', 'CANAL FICHIER (indirect)', 'CONSTANTE MOTEUR',
               'HORS RUNTIME (asset)', 'JAUGE (inerte par construction)', 'CANAL ABSENT'):
        print('%-32s %3d / %d' % (st, n.get(st, 0), tot))
    print('%-26s %3d' % ('dont TAUTOLOGIQUES', tauto))
    diffs = [r for r in rows if r[3]]
    print('cles dont la valeur DIFFERE entre les deux presets : %d' % len(diffs))
    for st in ('CANAL FICHIER', 'CANAL FICHIER (indirect)', 'CONSTANTE MOTEUR',
               'HORS RUNTIME (asset)', 'JAUGE (inerte par construction)', 'CANAL ABSENT'):
        print('   dont %-30s %3d' % (st, sum(1 for r in diffs if r[4] == st)))
    # CANAL PARTIEL : la meme cle lue a un endroit et gardee en dur a un autre. Un bouton a demi
    # branche ment plus qu'un bouton absent, donc il se publie a part et nommement.
    kind, site, f = CONSTS['SupineProjectionScale#2']
    m = re.search(r'\(defconstant\s+%s\s+([0-9.]+)\)' % re.escape(site), eng)
    print()
    if m:
        print('CANAL PARTIEL — `SupineProjectionScale` est LU par le tenseur de deformation et')
        print('  reste ECRIT EN DUR dans `phys-vol-floor` sous sa forme complementaire :')
        print('  %s = %s, soit 1 - %s. Tourner le bouton deplace le tenseur et PAS ce plancher.'
              % (site, m.group(1), pa.fmt(SK['SupineProjectionScale'][0])))
    else:
        print('CANAL PARTIEL — RESOLU. `%s` n\'existe plus dans le moteur : `phys-vol-floor` recoit'
              % site)
        print('  `sc` et lit la cle DERIVEE `DerivedSupineProjectionYield` (= 1 - SupineProjection-')
        print('  Scale, calculee en decimal exact par preset_apply.py pour rester identique au')
        print('  litteral qu\'elle remplace). La seconde copie de la cle 0 est donc branchee elle')
        print('  aussi : le bouton n\'est plus a moitie connecte.')

    # Les cles DERIVEES : elles sont cablees mais n'appartiennent pas au document. Elles se
    # publient a part pour qu'on ne les confonde pas avec des lignes de la spec.
    der = [k for k in wired if k.startswith('Derived')]
    if der:
        print()
        print('CLES DERIVEES CABLEES (%d) — pas dans le document, deduites par soustraction EXACTE :'
              % len(der))
        for k in sorted(der):
            mm = re.search(r'^pk %s ([0-9.]+)' % re.escape(k), ch, re.M)
            print('  %-32s %s' % (k, mm.group(1) if mm else 'ABSENTE DU FICHIER'))
        print('  Elles existent parce que le moteur consomme la BANDE (genou -> plafond) et non les')
        print('  deux bornes separement : sans elles il resterait un litteral en dur a cote d\'un')
        print('  canal, c\'est-a-dire un bouton a moitie branche.')
    if errs:
        print()
        for e in errs:
            print('ERREUR DE VERIFICATION: %s' % e)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
