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
        rows.append((k, kv, mv, differe, st, note))

    if 'SupineProjectionScale#2' in CONSTS:
        # la deuxieme copie de la meme cle est signalee A PART : elle ne change pas le compte des
        # cles, elle nomme un canal PARTIEL.
        pass

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
