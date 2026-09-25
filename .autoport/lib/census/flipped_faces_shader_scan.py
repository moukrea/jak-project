#!/usr/bin/env python3
"""flipped_faces_shader_scan.py — retournements de NORMALE D'ASSET restant dans les shaders.

lighting-flipped-faces-everywhere (owner 25/09) : l'orientation des normales du decor se corrige
UNE FOIS dans l'asset recharge ; aucun shader ne doit plus retourner la normale STOCKEE d'un sommet
(ni decor, ni merc). Ce recensement lit le texte des shaders et compte ces retournements.

Ce qui COMPTE comme retournement : une negation unaire, un `faceforward`, `g_shade_flip`, ou un
choix par `gl_FrontFacing`, qui porte sur une normale DERIVEE de la normale stockee du sommet
(sources : v_normal, vtx_nrm*, rotated_nrm, normal_in, s.N, shadow_N, et toute variable affectee
depuis l'une d'elles).
Ce qui NE compte PAS : la normale GEOMETRIQUE d'ecran `cross(dFdx(p), dFdy(p))`, dont le signe
depend de l'ecran et pas de l'asset (elle n'a pas d'orientation d'asset a corriger), et le code
sous `#ifdef OG_FLIP_PROBE` (sonde, jamais compile dans le rendu livre).

Usage : flipped_faces_shader_scan.py <dossier-shaders | fichier...>
Sortie : `flip <fichier>:<ligne> <extrait>` par retournement, puis `flips=<n>` et `files=<n>`.
"""
import os
import re
import sys

SOURCES = re.compile(r'\b(v_normal|vtx_nrm\w*|rotated_nrm|normal_in|nrm_in|shadow_N)\b|\bs\.N\b')
DERIV = re.compile(r'\bcross\s*\(\s*dFdx\b')
ASSIGN = re.compile(r'^\s*(?:(?:const\s+)?(?:vec[234]|float)\s+)?([A-Za-z_][A-Za-z0-9_.]*)\s*=\s*(.+?);')


def strip(src):
    """Retire commentaires et blocs `#ifdef OG_FLIP_PROBE` (branche #else gardee), lignes gardees."""
    src = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), src, flags=re.S)
    src = re.sub(r'//[^\n]*', '', src)
    out, skip = [], 0
    for line in src.split('\n'):
        s = line.strip()
        if skip:
            if re.match(r'#\s*if', s):
                skip += 1
            elif re.match(r'#\s*endif', s):
                skip -= 1
            elif re.match(r'#\s*else', s) and skip == 1:
                skip = 0
            out.append('')
            continue
        if re.match(r'#\s*ifdef\s+OG_FLIP_PROBE\b', s) or re.match(r'#\s*if\s+defined\s*\(\s*OG_FLIP_PROBE\s*\)', s):
            skip = 1
            out.append('')
            continue
        out.append(line)
    return out


def scan(path):
    lines = strip(open(path, errors='replace').read())
    tainted = set()
    # deux passes : une variable peut etre teintee par une affectation posterieure (boucle, fonction)
    for _ in range(2):
        for line in lines:
            m = ASSIGN.match(line)
            if not m:
                continue
            var, rhs = m.group(1), m.group(2)
            if DERIV.search(rhs):
                continue
            names = set(re.findall(r'[A-Za-z_][A-Za-z0-9_.]*', rhs))
            if SOURCES.search(rhs) or (names & tainted):
                tainted.add(var)
    tainted |= {'s.N', 'shadow_N', 's.shadow_N'}
    tv = '|'.join(re.escape(t) for t in sorted(tainted, key=len, reverse=True))
    neg = re.compile(r'(^|[=(,?:+*/]|return)\s*-\s*(' + tv + r')\b') if tv else None
    hits = []
    for i, line in enumerate(lines, 1):
        if not line.strip():
            continue
        why = None
        if re.search(r'\bg_shade_flip\b', line):
            why = 'g_shade_flip'
        elif re.search(r'\bfaceforward\s*\(', line):
            why = 'faceforward'
        elif neg and neg.search(line):
            why = 'negation'
        elif tv and 'gl_FrontFacing' in line and re.search(r'\b(' + tv + r')\b', line):
            why = 'gl_FrontFacing'
        if why:
            hits.append((i, why, line.strip()[:90]))
    return hits


def main(argv):
    files = []
    for a in argv:
        if os.path.isdir(a):
            for root, _, names in os.walk(a):
                files += [os.path.join(root, n) for n in names
                          if n.endswith(('.frag', '.vert', '.glsl', '.geom', '.tesc', '.tese'))]
        else:
            files.append(a)
    total = 0
    for f in sorted(files):
        for i, why, txt in scan(f):
            print('flip %s:%d %s %s' % (f, i, why, txt))
            total += 1
    print('flips=%d' % total)
    print('files=%d' % len(files))


if __name__ == '__main__':
    main(sys.argv[1:])
