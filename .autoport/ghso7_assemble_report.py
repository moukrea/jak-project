#!/usr/bin/env python3
"""Ajoute au report.txt les lignes de porte du cycle 7 tirees des trois jambes Redmi :
ablation (defaut brut), controle positif (inject=2), preuve (affine_arm=2). Le validateur ne
manque que la ligne HDROOTJUMP ; on ajoute aussi les HDSTRETCHCOUNT/HDMOVES/HDATTRIB des jambes 7."""
import re, glob, os
R = '.autoport/reports/Ghd-skin-origin-stretch'
rep = f'{R}/report.txt'
blocks = []
for tag, label in [('dev7-abl1', 'ABLATION affine_arm=1 (ancien correctif : colonne w forcee sans division)'),
                   ('dev7-abl0', 'ABLATION affine_arm=0 (defaut brut)'),
                   ('dev7-inj2', 'CONTROLE POSITIF inject=2 (pose de bind)'),
                   ('dev7-prf',  'PREUVE affine_arm=2 (>= 10 min)')]:
    f = f'{R}/device/{tag}-hdstretch.txt'
    if not os.path.exists(f):
        continue
    lines = open(f).read().split('\n')
    keep = [l for l in lines if l.startswith(('HDSTRETCHCOUNT', 'HDMOVES', 'HDROOTJUMP', 'HDATTRIB'))]
    blocks.append(f"\n;; ---- cycle 7 : {label} ({tag}) ----\n" + '\n'.join(keep))
if blocks:
    with open(rep, 'a') as fh:
        fh.write('\n\n================================================================================\n')
        fh.write('CYCLE 7 — PREUVE REDMI (source du w normalisee a la production ; symptomes racine+t-pose)\n')
        fh.write('================================================================================')
        fh.write('\n'.join(blocks))
        fh.write('\n')
    print(f"report.txt : {len(blocks)} bloc(s) cycle 7 ajoute(s)")
else:
    print("AUCUN resume cycle 7 trouve — jambes non executees")
