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


def fmt(v):
    s = ('%.6f' % v).rstrip('0').rstrip('.')
    return s if s else '0'


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
    mine = S[who]
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
    text = '\n'.join(out)
    with open(dst, 'w', encoding='utf-8') as f:
        f.write(text)
    dg = hashlib.sha256(text.encode()).hexdigest()[:16]
    print('[preset] %s: %d cles posees sur %d chaine(s) -> %s (%d octets, sha %s)'
          % (who, len(posed), n_chain, dst, len(text), dg))
    if bad:
        print('[preset] %d cle(s) non numeriques, NON posees: %s' % (len(bad), ', '.join(bad)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
