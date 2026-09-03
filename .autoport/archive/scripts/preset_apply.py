#!/usr/bin/env python3
"""preset_apply.py — POSE LE PRESET DU PERSONNAGE DANS LE FICHIER LIVRE, COMME UNE ENTREE.

Owner, 2026-08-22 : « tu pourrais faire en sorte que ce soit des boutons qu'on tourne justement,
regarde le preset de Maia, les memes proprietes des presets ont des valeurs differentes, on
pourrait donc imaginer que ces "knobs" influencent proprement le tout... C'est un peu le but d'un
preset. »

Sa premisse est verifiee : les deux presets de `SPEC-breast-softbody.md` (section 38, Keira et
Maia) partagent 71 cles et **51 portent des valeurs differentes**. Un document qui donne les MEMES
cles avec des valeurs DIFFERENTES pour deux personnages n'ecrit pas des observations : il ecrit des
ENTREES. Ce script les recopie donc, VERBATIM, dans `recharged_assets/physics_chains.txt` sous la
forme d'un enregistrement `pk <Cle> <valeur>` par cle et par chaine, que le moteur lit.

CE QUE CA CHANGE, ET C'EST LE POINT :
  * les valeurs de forme qui etaient ECRITES EN DUR dans le moteur sont desormais LUES. Une mesure
    qui republiait la constante qu'elle visait (13 entrees du registre) cesse d'etre tautologique
    PAR CONSTRUCTION, sans qu'on ait a le declarer ;
  * une cle que le moteur ne lit pas se compte comme `CANAL ABSENT` (compteur publie a l'execution
    par `pc-physics-chain-preset-absent`), c'est-a-dire un manque d'implementation NOMME — jamais
    une section « non tenue » comme si le solveur echouait ;
  * et ca donne le controle que ce dossier n'a jamais eu : poser le preset de MAIA sur la chaine de
    KEIRA doit produire un comportement MESURABLEMENT different, dans le sens que ses 51 ecarts
    prescrivent. Un moteur qui consomme vraiment le preset le montre ; un moteur qui fait semblant
    rend la meme chose.

PERIMETRE (DIRECTIVES 2026-08-22 23:00) : on ne livre PAS la physique de Maia et on ne touche pas a
son personnage. Ses chiffres servent de VECTEUR DE TEST sur la chaine de Keira, rien d'autre.
`--preset maia` ecrit donc vers `--out` (un fichier d'essai), jamais vers le livre par defaut.

Aucune valeur n'est retapee a la main : tout est LU dans SPEC-breast-softbody.md, avec le numero de
ligne d'origine, et le bloc pose porte ce numero. Une valeur retapee est une valeur qui derive.
"""
import argparse
import hashlib
import math
import os
import re
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = os.path.join(REPO, 'SPEC-breast-softbody.md')
CHAINS = os.path.join(REPO, 'recharged_assets', 'physics_chains.txt')

MARK_BEGIN = '# --- PRESET (SPEC-breast-softbody section 38) — pose par .autoport/preset_apply.py'
MARK_END = '# --- fin PRESET'

# Un tiret « – » (U+2013) separe les bornes d'une plage dans le document de l'owner ; un « - »
# ASCII apparait aussi. Les deux sont traites, et une plage devient DEUX cles `...Lo` / `...Hi`
# plutot qu'une moyenne : moyenner deux bornes fabrique un nombre que la spec n'ecrit nulle part.
NUM = r'[-+]?[0-9]*\.?[0-9]+'


def read_presets(path=SPEC):
    """Rend {nom_du_preset: {cle: (valeur_brute, ligne)}} pour les blocs de la section 38."""
    lines = open(path, encoding='utf-8').read().split('\n')
    out = {}
    i = 0
    while i < len(lines):
        m = re.match(r'^## 38\..*?—\s*(.+?)\s*$', lines[i])
        if not m:
            i += 1
            continue
        who = m.group(1).strip()
        j = i + 1
        while j < len(lines) and not lines[j].startswith('```'):
            j += 1
        j += 1
        keys = {}
        while j < len(lines) and not lines[j].startswith('```'):
            ln = lines[j]
            mm = re.match(r'^\s*([A-Za-z][A-Za-z0-9]*)\s*(?:=|≈|>=)\s*(.+?)\s*$', ln)
            if mm:
                keys[mm.group(1)] = (mm.group(2), j + 1)   # numero de ligne 1-based
            j += 1
        out[who] = keys
        i = j
    return out


def scalars(keys):
    """Cle -> (valeur numerique, ligne source, texte brut). Les plages donnent Lo et Hi."""
    out = {}
    for k, (raw, ln) in keys.items():
        txt = raw.replace('≈', '').strip()
        if txt.lower() in ('true', 'yes'):
            out[k] = (1.0, ln, raw)
            continue
        if txt.lower() in ('false', 'no'):
            out[k] = (0.0, ln, raw)
            continue
        rng = re.match(r'^(%s)\s*[–-]\s*(%s)\b' % (NUM, NUM), txt)
        if rng:
            out[k + 'Lo'] = (float(rng.group(1)), ln, raw)
            out[k + 'Hi'] = (float(rng.group(2)), ln, raw)
            continue
        one = re.match(r'^(%s)\b' % NUM, txt)
        if one:
            out[k] = (float(one.group(1)), ln, raw)
            continue
        # une valeur qu'on ne sait pas lire n'est PAS silencieusement omise : elle est signalee.
        out['#UNPARSED#' + k] = (None, ln, raw)
    return out


# Cles DERIVEES : elles ne sont pas ecrites dans le document, elles s'en DEDUISENT par une
# soustraction exacte. Elles existent parce que le moteur consomme la BANDE (genou -> plafond) et
# pas les deux bornes separement : sans elles il resterait un litteral en dur a cote d'un canal,
# c'est-a-dire un bouton a moitie branche, qui ment plus qu'un bouton absent. Le calcul est fait
# en DECIMAL exact (`Decimal`) pour que la valeur posee soit celle qu'un humain ecrirait — sinon
# 0.50 - 0.42 rend 0.080000005 en flottant et la valeur cesse d'etre identique au litteral
# qu'elle remplace, ce qui detruirait le controle de bit-identite.
DERIVED = {
    'DerivedApexSoftBand':          ('HardMaxApexDisplacement', '-', 'NormalMaxApexDisplacement'),
    'DerivedCOMSoftBand':           ('HardMaxCOMDisplacement', '-', 'NormalMaxCOMDisplacement'),
    'DerivedSupineProjectionYield': ('1', '-', 'SupineProjectionScale'),
}


def add_derived(out, raw):
    from decimal import Decimal
    def dec(name):
        if name == '1':
            return Decimal('1')
        txt = raw[name][0].replace('\u2248', '').strip()
        m = re.match(r'^(%s)' % NUM, txt)
        return Decimal(m.group(1))
    for k, (a, op, b) in DERIVED.items():
        if (a != '1' and a not in raw) or b not in raw:
            continue
        v = dec(a) - dec(b)
        ln = raw[b][1] if b in raw else 0
        out[k] = (float(v), ln, '%s %s %s' % (a, op, b))
    return out


def fmt(v):
    s = ('%.6f' % v).rstrip('0').rstrip('.')
    return s if s else '0'


# =================================================================================================
# CYCLE 111 — `pk GlobalFrequencyVertical` DEVIENT UN VRAI CANAL. IL N'EN ETAIT PAS UN.
#
# PREUVE PAR PERTURBATION, PAS PAR LECTURE DE CODE (regle 0 : un commentaire n'est pas une preuve).
# Avant ce bloc, en passant le preset de MAIA sur la chaine de KEIRA :
#     pk GlobalFrequencyVertical  2.3  -> 1.85   (-20 %)
#     pk GlobalDampingRatio       0.35 -> 0.33
#     pk MassPerBreast            0.5  -> 1.05   (x2.1)
#     ligne `chain chestL ... stiffness=2.7696 damping=0.1686 mass=1.45 ...`  ->  IDENTIQUE AU BIT
# Les trois cles les plus consequentes du preset ne touchaient RIEN. `.autoport/
# preset_channel_audit.py` les comptait pourtant `CANAL FICHIER (indirect)` sur la foi d'une note
# ecrite a la main — c'est-a-dire un faux vert dans le seul instrument qui mesure l'avancement.
#
# CE QU'ELLES ETAIENT REELLEMENT : une derivation HUMAINE, faite le 2026-08-14 et FIGEE dans
# `recharged_assets/keira-owner-tuning.txt:1237-1241`, qui ecrit le resultat (2.7696) et jamais
# l'operation. Tourner le bouton ne pouvait rien produire puisque personne ne le lisait :
# `apply_owner_tuning.py` ne contient pas une seule occurrence de `pk`.
#
# CE QUE CE BLOC FAIT : il refait CETTE derivation, a l'execution, depuis la cle du fichier livre.
#     SPEC 24  stiffness = GlobalFrequencyVertical * sqrt(mass)        (w = 2*pi*stiffness/sqrt(mass))
#     SPEC 32  chestR porte +5 % de raideur (haut de sa bande « stiffness +-3-5 % »)
#
# CONTROLE NEGATIF, ET IL EST EXACT : avec le preset de Keira la derivation rend 2.7696 et 2.9081,
# c'est-a-dire les deux nombres deja livres, AU BIT PRES. Cabler le canal est donc INERTE sur ce
# qu'on livre — la physique mesuree ne bouge pas d'un bit, et la course en cours reste valable.
# CONTROLE POSITIF : avec le preset de Maia elle rend 2.2277 (x0.8043), donc le bouton tourne.
#
# `damping=` EST DERIVE ICI DEPUIS LE CYCLE 115, ET LE CYCLE 111 AVAIT RAISON DE REFUSER — SUR CE
# QU'IL REFUSAIT. Il ecrivait : « changer 0.1753 en 0.1752 EN SILENCE serait modifier la physique au
# milieu d'un changement d'instrument ». Le mot qui porte est **en silence**. Le faire avec l'ecart
# PUBLIE, PREDIT D'AVANCE et MESURE n'est pas la meme chose, et le motif du 1e-4 est etabli par le
# cycle 111 lui-meme : le 2.3913 Hz employe a la main le 2026-08-14 n'est pas le 2.390443 Hz que
# rend la masse effectivement livree (1.4800). **0.1753 est un artefact d'arrondi de la derivation
# humaine ; 0.1752 est ce que la formule rend.** Ce n'est donc pas un ajustement, c'est la
# substitution d'un nombre fige par sa formule — et le sens de la substitution est le bon :
# `never-fit-a-parameter-to-the-instrument` interdit de tordre la FORMULE pour retomber sur le
# nombre, pas de garder la formule et de publier l'ecart.
#
# POURQUOI CE CANAL EST UNE CONDITION, PAS UN CONFORT. Le moteur consomme `damping=` comme un TAUX
# PAR PAS (`2*zeta*omega*dt`), pas comme un zeta. Le laisser gele pendant que la frequence tourne
# emmene zeta a l'OPPOSE de ce que le preset demande — le cycle 111 l'a MESURE : le vecteur Maia
# rendait zeta = 0.4351 la ou le preset de Maia ecrit 0.33 (+31.9 %, et Maia est censee etre un peu
# MOINS amortie que Keira, pas nettement plus). Le controle de niveau systeme que l'owner demande
# le 2026-08-22 a 23:00 aurait donc montre un personnage plus lent ET plus amorti : un faux
# resultat, dans le mauvais sens, sur la grandeur meme qu'il sert a prouver.
#
#   SPEC 25 / SPEC 28   damping = 2 * GlobalDampingRatio * 2*pi*f / 60,  f = stiffness / sqrt(mass)
#
# CONTROLE NEGATIF PARTIEL, ET IL EST EXACT SUR UNE CHAINE : chestL 0.1686 -> 0.1686, au bit.
# ECART, CHIFFRE D'AVANCE ET SUR UNE SEULE CHAINE : chestR 0.1753 -> 0.1752 (-0.057 %).
# Contrairement a `stiffness=`, la masse ne s'annule PAS ici : `f` est relue sur la ligne `chain`
# APRES que la premiere passe a reecrit `stiffness=`, donc le zeta obtenu est bien celui du preset.
# =================================================================================================

# SPEC 32 « Left/Right Independence [...] stiffness +-3-5 % ». Le +5 % (haut de bande) est un CHOIX
# de personnage, pas une cle du preset : il est donc nomme ici avec sa source, jamais devine.
# Derivation d'origine : recharged_assets/keira-owner-tuning.txt:1340-1365.
SPEC32_STIFFNESS_ASYM = {'chestL': 1.00, 'chestR': 1.05}


def derive_mechanics(lines, mine, who):
    """Reecrit `stiffness=` de chaque ligne `chain` depuis `GlobalFrequencyVertical` du preset.

    NATURE  : une raideur en unites moteur, telle que f = stiffness/sqrt(mass) [Hz] (SPEC 24).
    REPERE  : sans objet — grandeur scalaire d'un ressort, pas une direction.
    HORS DEFAUT : avec le preset de Keira, la valeur ecrite est celle deja livree, au bit pres.

    Rend (lines, journal) ou `journal` liste (chaine, avant, apres, change) pour publication.
    """
    fv = mine.get('GlobalFrequencyVertical', (None,))[0]
    journal = []
    if fv is None:
        return lines, journal

    # PREMIERE PASSE — LA RAIDEUR DE REFERENCE, SUR LA CHAINE QUE SPEC 32 NE TOUCHE PAS.
    # Erreur commise puis corrigee au cycle 111, et le controle negatif l'a attrapee AVANT
    # qu'elle atteigne le fichier livre : recalculer chestR avec SA PROPRE masse (1.4800) rend
    # 2.9380 au lieu des 2.9081 livres. Sa derivation d'origine ne fait pas ca — elle prend la
    # raideur de chestL et lui applique +5 % (keira-owner-tuning.txt:1340-1365, « chestL n'est PAS
    # touchee : elle porte exactement le nominal de sa spec ; l'asymetrie est portee d'un seul
    # cote »). La masse de chestR porte SON propre ecart de SPEC 32 (+2.03 %) et n'entre donc pas
    # une seconde fois dans la raideur, sinon l'ecart serait compte deux fois.
    base = None
    for ln in lines:
        if not ln.startswith('chain '):
            continue
        name = ln.split()[1]
        if SPEC32_STIFFNESS_ASYM.get(name, 1.00) != 1.00:
            continue
        mm = re.search(r'\bmass=(%s)\b' % NUM, ln)
        if mm:
            base = round(fv * (float(mm.group(1)) ** 0.5), 4)
            break
    if base is None:
        return lines, journal

    # SECONDE PASSE — chaque chaine porte la reference fois son facteur de SPEC 32.
    out = []
    for ln in lines:
        if not ln.startswith('chain '):
            out.append(ln)
            continue
        name = ln.split()[1]
        ms = re.search(r'\bstiffness=(%s)\b' % NUM, ln)
        if not ms:
            out.append(ln)
            continue
        asym = SPEC32_STIFFNESS_ASYM.get(name, 1.00)
        val = base if asym == 1.00 else round(base * asym, 4)
        avant = ms.group(1)
        apres = '%.4f' % val
        journal.append(('stiffness', name, avant, apres, avant != apres))
        out.append(ln[:ms.start(1)] + apres + ln[ms.end(1):])

    # TROISIEME PASSE — `damping=` DEPUIS `GlobalDampingRatio`. Elle vient APRES la seconde et lit
    # la raideur QU'ELLE VIENT D'ECRIRE : le taux depend de la frequence, donc le derive dans
    # l'autre ordre rendrait le zeta de l'ANCIENNE frequence. Motif complet en tete de fichier.
    zeta = mine.get('GlobalDampingRatio', (None,))[0]
    if zeta is None:
        return out, journal
    out2 = []
    for ln in out:
        if not ln.startswith('chain '):
            out2.append(ln)
            continue
        name = ln.split()[1]
        md = re.search(r'\bdamping=(%s)\b' % NUM, ln)
        mst = re.search(r'\bstiffness=(%s)\b' % NUM, ln)
        mms = re.search(r'\bmass=(%s)\b' % NUM, ln)
        if not (md and mst and mms) or float(mms.group(1)) <= 0.0:
            out2.append(ln)
            continue
        f = float(mst.group(1)) / (float(mms.group(1)) ** 0.5)
        avant = md.group(1)
        apres = '%.4f' % round(2.0 * zeta * 2.0 * math.pi * f / 60.0, 4)
        journal.append(('damping', name, avant, apres, avant != apres))
        out2.append(ln[:md.start(1)] + apres + ln[md.end(1):])
    return out2, journal



def strip_block(text):
    out, skip = [], False
    for ln in text.split('\n'):
        if ln.startswith(MARK_BEGIN):
            skip = True
            continue
        if skip and ln.startswith(MARK_END):
            skip = False
            continue
        if skip or ln.startswith('pk '):
            continue
        out.append(ln)
    return '\n'.join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--preset', default='keira',
                    help='keira (livre) ou maia (VECTEUR DE TEST, jamais livre)')
    ap.add_argument('--chains', default=CHAINS, help='fichier de chaines a lire')
    ap.add_argument('--out', default=None, help='ou ecrire (defaut: --chains)')
    ap.add_argument('--audit', action='store_true', help="n'ecrit rien, publie l'inventaire")
    args = ap.parse_args()

    presets = read_presets()
    names = {k.split()[0].lower(): k for k in presets}
    if args.preset.lower() not in names:
        print('preset inconnu: %s (connus: %s)' % (args.preset, ', '.join(sorted(names))))
        return 2
    who = names[args.preset.lower()]
    other = [k for k in presets if k != who]

    S = {k: scalars(v) for k, v in presets.items()}
    mine = add_derived(S[who], presets[who])
    bad = sorted(k[len('#UNPARSED#'):] for k in mine if k.startswith('#UNPARSED#'))

    if args.audit or args.preset.lower() != 'keira':
        a, b = S[who], S[other[0]] if other else {}
        common = sorted(set(a) & set(b))
        diff = [k for k in common if a[k][0] != b[k][0]]
        print('[preset] %s: %d cles lues, %d communes avec %s, %d valeurs DIFFERENTES'
              % (who, len(a), len(common), other[0] if other else '(rien)', len(diff)))
        if bad:
            print('[preset] %d cle(s) non numeriques, NON posees: %s' % (len(bad), ', '.join(bad)))
        if args.audit:
            for k in sorted(common):
                mark = 'DIFFERENT' if a[k][0] != b[k][0] else 'identique'
                print('  %-30s %-12s %-12s %s' % (k, fmt(a[k][0]) if a[k][0] is not None else '?',
                                                  fmt(b[k][0]) if b[k][0] is not None else '?', mark))
            return 0

    src = args.chains
    dst = args.out or args.chains
    text = open(src, encoding='utf-8').read()
    if dst == src:
        # La sauvegarde va dans un repertoire de travail, JAMAIS a cote du fichier livre : tout
        # ce qui traine dans recharged_assets/ part dans le pack que l'owner telecharge.
        bak = os.path.join(REPO, '.autoport', 'backups')
        os.makedirs(bak, exist_ok=True)
        shutil.copyfile(src, os.path.join(bak, 'physics_chains.prepreset.txt'))

    text = strip_block(text)
    posed = [(k, v[0], v[1]) for k, v in sorted(mine.items())
             if not k.startswith('#UNPARSED#')]

    out, n_chain = [], 0
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        out.append(lines[i])
        if lines[i].startswith('chain '):
            name = lines[i].split()[1]
            # les `j` de la chaine restent colles a leur `chain`
            while i + 1 < len(lines) and lines[i + 1].startswith('j '):
                i += 1
                out.append(lines[i])
            out.append('%s pour %s.' % (MARK_BEGIN, name))
            out.append('#     source: SPEC-breast-softbody.md « %s », une ligne par cle, valeur et'
                       % who)
            out.append('#     numero de ligne recopies TELS QUELS. Une cle sans lecteur dans le')
            out.append('#     moteur se compte CANAL ABSENT (pc-physics-chain-preset-absent), pas')
            out.append('#     une section non tenue.')
            for k, v, ln in posed:
                out.append('pk %s %s   # SPEC-breast-softbody.md:%d' % (k, fmt(v), ln))
            out.append(MARK_END)
            n_chain += 1
        i += 1
    # LE CANAL MECANIQUE, DERIVE DE LA CLE ET PAS RECOPIE D'UN FICHIER FIGE (cf. derive_mechanics).
    out, mech = derive_mechanics(out, mine, who)
    text = '\n'.join(out)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(text)
    dg = hashlib.sha256(text.encode()).hexdigest()[:16]
    print('[preset] %s: %d cles posees sur %d chaine(s) -> %s (%d octets, sha %s)'
          % (who, len(posed), n_chain, dst, len(text), dg))
    # Publie TOUJOURS, y compris quand rien ne bouge : c'est le controle de bit-identite, et un
    # controle qui ne s'imprime que lorsqu'il echoue n'est pas un controle.
    for what, name, avant, apres, chg in mech:
        print('[preset] %-7s canal %-8s %-9s %s -> %s   %s'
              % ('SPEC24' if what == 'stiffness' else 'SPEC25', name, what, avant, apres,
                 'CHANGE (le bouton tourne)' if chg else 'identique au bit (controle negatif)'))
    if bad:
        print('[preset] %d cle(s) non numeriques, NON posees: %s' % (len(bad), ', '.join(bad)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
