#!/usr/bin/env python3
"""Text-only pre-check of the Grecharged-hd-eye-scale report against the validator's own regexes.

The validator's numeric gate is a blunt scanner: it collects EVERY `\\bHD\\b ... max ... <number>`
and every `\\bstock\\b ... max ... <number>` in the whole file and demands max(HD) <= max(stock)*1.02.
Model names like `dax-hd-lod0` and even a raw `hd=0` field match `\\bHD\\b`, so a pasted log line can
silently poison it. This reproduces the check and prints exactly what it matched, so the report can
be written with eyes open instead of guessed at.
"""
import re
import sys

R = sys.argv[1] if len(sys.argv) > 1 else '.autoport/reports/Grecharged-hd-eye-scale/report.txt'
t = open(R, errors='ignore').read()
fails = []


def need(pat, msg, flags=re.I):
    if not re.search(pat, t, flags):
        fails.append(msg)


def forbid(pat, msg, flags=re.I):
    m = re.findall(pat, t, flags)
    if m:
        fails.append(f'{msg} -> {sorted(set(m))[:6]}')


need(r'RESULT:', 'no RESULT: line')
need(r'phase-NEW|Grecharged-hd-eye-scale', 'no phase-NEW marker')
need(r'(why|pourquoi|root.?cause|because).{0,120}(HD|bind|absolute|relatif|relative|base)',
     'no root cause for why it hits HD harder')
need(r'(effect|effet).{0,60}(kept|conserv|still|preserved|non nul|nonzero)',
     'must prove the effect is REDUCED, not removed')
need(r'(jak|keira|samos|variant|look).{0,80}(same channel|même canal|checked|verif)',
     'other HD characters not checked')
need(r'(gap|edge[- ]to[- ]edge|inter[- ]?eye|entre les deux yeux)[^\n]{0,60}[0-9]', 'EYE-GAP missing')
need(r'(quad|blerc|blend target|eye bone|scale)[^\n]{0,90}(ruled out|elimin|not the|excluded|is the)',
     'EYE-CHAN missing')
forbid(r'capture|screenshot|screencap|visual', 'BANNED word present')


def grab(tag):
    out = []
    for m in re.finditer(tag + r'[^\n]{0,140}?(?:max)[^0-9\n-]{0,12}(-?[0-9]+\.?[0-9]*)', t, re.I):
        line = t[:m.start()].count('\n') + 1
        out.append((float(m.group(1)), line, m.group(0)[:110].replace('\n', ' ')))
    return out


hd, stock = grab(r'\bHD\b'), grab(r'\bstock\b')
print(f'--- {len(hd)} HD matches ---')
for v, ln, s in sorted(hd, reverse=True)[:12]:
    print(f'  {v:>12}  L{ln}: {s}')
print(f'--- {len(stock)} stock matches ---')
for v, ln, s in sorted(stock, reverse=True)[:12]:
    print(f'  {v:>12}  L{ln}: {s}')
if not hd or not stock:
    fails.append('numeric gate: need at least one HD max and one stock max')
elif max(x[0] for x in hd) > max(x[0] for x in stock) * 1.02:
    fails.append(f'numeric gate: max(HD)={max(x[0] for x in hd)} > 1.02*max(stock)='
                 f'{max(x[0] for x in stock) * 1.02}')

print()
if fails:
    for f in fails:
        print('FAIL:', f)
    sys.exit(1)
print('[report-gate TEXT CHECKS PASS]')
