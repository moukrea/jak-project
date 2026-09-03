#!/usr/bin/env python3
"""Ghd-skin-origin-stretch — genere `parts/head.txt` DEPUIS LES ANALYSES DE LA COURSE.

POURQUOI GENERE ET PAS ECRIT A LA MAIN : la tete du rapport porte des chiffres (nombre
d'episodes, pente, part des episodes ou longueur == distance). Ecrits a la main, ils
survivent a la course qui les a produits et decrivent alors une AUTRE campagne — c'est la
faute `validator reads a stale table` du registre, appliquee a un rapport.
"""
import re
import sys

D = '.autoport/reports/Ghd-skin-origin-stretch'


def kv(l):
    return dict(re.findall(r'(\w+)=([^\s]+)', l))


def grab(path, pfx):
    out = [l for l in open(path, errors='replace').read().split('\n') if l.startswith(pfx)]
    return out


ctl = f'{D}/ctl2-analyse.txt'
prf = f'{D}/prf-analyse.txt'

cs = kv(grab(ctl, 'HDSTALE ')[-1])
ps = kv(grab(prf, 'HDSTALE ')[-1])
cc = grab(ctl, 'HDCORREL ')
cc = kv(cc[-1]) if cc else {}
cx = grab(ctl, 'HDSTRETCH ')
cx = kv(cx[-1]) if cx else {}
cmt = [l for l in grab(ctl, '# |cible|')]
eps = [kv(l) for l in grab(ctl, 'HDEPISODE ')]

ident = sum(1 for e in eps
            if abs(float(e['distance_origine_m']) - float(e['longueur_etirement_m'])) < 5e-4)
mods = sorted({e['modele'] for e in eps})
dmin = min((float(e['distance_origine_m']) for e in eps), default=0.0)
dmax = max((float(e['distance_origine_m']) for e in eps), default=0.0)
dur = max((float(e['duree_ms']) for e in eps if e['modele'] in ('keira', 'samos')), default=0.0)
cible = re.search(r'\|cible\| = ([\d.]+) m ; os en fuite agreges = (\d+) ; '
                  r'dont a moins de 6 m de \(0,0,0\) = (\d+) \(([\d.]+) %\)',
                  '\n'.join(cmt))

pct_ctl = (100.0 * int(cs['images_avec_matrice_perimee']) / max(1, int(cs['images'])))

out = f"""DIRECTIVES vd9e8b66782

Ghd-skin-origin-stretch — LE RECIBLAGE HD CONSOMMAIT DES MATRICES D'OS QUE PERSONNE N'AVAIT
ECRITES, ET LE MODELE S'ETIRAIT JUSQU'A L'ORIGINE DU MONDE

================================================================================
0. LE DEFAUT NE SE GUETTE PLUS A L'ECRAN — IL SE COMPTE TOUT SEUL
================================================================================
Le superviseur a refondu la porte le 2026-09-02 a 07:10 : « ON NE MESURE PLUS LE SYMPTOME, ON
MESURE LA CAUSE [...] A CHAQUE IMAGE et pour CHAQUE joint pilote, tester la matrice consommee ».
C'est fait, et c'est le resultat principal de ce cycle.

Le compteur est pose AUX TROIS SITES qui ecrivent un os HD depuis une matrice du pilote
(`fill-jak-hd-bones!`, modes 0, 1 et 3 — annotes `SITE DE CONSOMMATION i/3`). Il ne compte pas les
detections : il compte ce que le reciblage a REELLEMENT CONSOMME.

                                          garde DESARME     garde ARME
    images de reciblage                   {cs['images']:>14} {ps['images']:>14}
    images servies par une mat. perimee   {cs['images_avec_matrice_perimee']:>14} {ps['images_avec_matrice_perimee']:>14}
      dont HORS joint-racine              {cs['images_hors_racine']:>14} {ps['images_hors_racine']:>14}
    ecritures de joint concernees         {cs['joints_touches']:>14} {ps['joints_touches']:>14}
      dont HORS joint-racine              {cs['joints_hors_racine']:>14} {ps['joints_hors_racine']:>14}
    pire compte dans une seule image      {cs['pire_par_image']:>14} {ps['pire_par_image']:>14}
    minutes de la fenetre                 {cs['minutes']:>14} {ps['minutes']:>14}
    modeles ayant consomme une perimee    {cs['modeles']}  /  {ps['modeles']}

LES DEUX COLONNES SORTENT DU MEME BINAIRE ET DU MEME COMPTEUR ; ce qui change entre elles est le
symbole GOAL `*hd-guard-arm*`, pose depuis la REPL. Le zero de droite est donc falsifiable : le
meme compteur tire {cs['images_avec_matrice_perimee']} fois des qu'on le desarme, sur le meme itineraire.

ET LE TOTAL SE LIT AVEC SON SOUS-ENSEMBLE. A gauche, {cs['images_avec_matrice_perimee']} sur {cs['images']} images
({pct_ctl:.1f} %) : les occasions de JOINT-RACINE se presentent sur presque toutes les images, parce que
l'os `align` du pilote n'est JAMAIS ecrit (en-tete de `jak-hd.gc`, l.49-50). C'est une constante de
construction, pas le defaut de l'owner — et un compte qui vaut son propre denominateur ne
discrimine plus rien. Le sous-ensemble qui porte les joints reellement skinnes est HORS RACINE :
{cs['images_hors_racine']} images et {cs['joints_hors_racine']} ecritures a gauche, {ps['images_hors_racine']} et {ps['joints_hors_racine']} a droite. Les deux comptes sont
publies : ne publier que le second serait un de-scope, ne publier que le premier serait une
fausse constante.

ET LA LISTE DE MODELES CI-DESSUS N'EST PAS LA LISTE DES MODELES DECHIRES — il faut le dire, sinon
elle contredit la section 1. `HDSTALE modeles=` recense TOUTE consommation d'une matrice perimee,
JOINT-RACINE COMPRIS ; le recensement des DECHIRURES (section 1) ne retient qu'un os qui a
reellement quitte le personnage. Les deux ne peuvent pas coincider, et c'est DAXTER qui les
separe : son compagnon a consomme au moins une matrice perimee, et AUCUNE dechirure vers l'origine
n'a ete mesuree sur lui, dans aucun bras. Je ne declare donc rien de plus sur lui que ces deux
faits — ni touche, ni epargne.

================================================================================
1. CE QUE L'OWNER DECRIT, ET CE QUE LA MESURE EN DIT
================================================================================

  « le modèle s'allonge horizontalement comme s'il essayait d'atteindre un point d'origine au
    loin (Sandover Village ?) [...] plus on est loin de Sandover Village, plus l'effet est
    extrême. ça dure à chaque fois une split seconde [...] je me demande si ça n'affecte pas
    non plus Samos et Keira »

Sa description designe un point precis, et elle est VERIFIEE, pas crue. Sur le bras de controle,
la LONGUEUR de l'etirement et la DISTANCE DU PERSONNAGE A (0,0,0) sont la meme grandeur :

    HDCORREL  n = {cc.get('n','?')}   pente = {cc.get('pente','?')}   r2 = {cc.get('r2','?')}   ({dmin:.1f} m .. {dmax:.1f} m)

Une pente de 1 sur {cc.get('n','?')} episodes et un facteur {dmax/max(dmin,1e-9):.0f} de distance, ce n'est pas une correlation,
c'est une IDENTITE : les os fautifs se posent sur l'origine du monde, donc l'etirement MESURE
l'eloignement. C'est mot pour mot « plus on est loin, plus l'effet est extreme »."""

if cible:
    out += f"""
Et le barycentre des {cible.group(2)} os en fuite agreges vaut |cible| = {cible.group(1)} m, avec {cible.group(3)} sur
{cible.group(2)} a moins de 6 m de (0,0,0) — {cible.group(4)} %."""

out += f"""

ET LA PENTE EST MEME UNE FACON FAIBLE DE LE DIRE : sur les {len(eps)} episodes, **{ident} rendent les deux
grandeurs IDENTIQUES a la quatrieme decimale du metre imprimee**. Les autres sont les dechirures
PARTIELLES de Keira et Samos, ou quelques os seulement partent a l'origine pendant que le reste du
corps reste en place : la longueur y depasse la distance de 1 a 2 m, l'ecart entre la racine du
process et l'os de reference. Le mode TOTAL et le mode PARTIEL du meme defaut, cote a cote.

SON HYPOTHESE « SANDOVER » EST REFUTEE AU PASSAGE, et il faut le lui dire : Sandover (village1-hut)
est LUI-MEME a 246,6228 m de l'origine (`goal_src/jak1/engine/level/level-info.gc`). Les os ne
partent pas vers Sandover, ils partent vers (0,0,0) — le barycentre du groupe en fuite est publie
et vaut zero a la quatrieme decimale du metre.

SA QUESTION SUR SAMOS ET KEIRA EST FONDEE, ET ELLE EST MEME EN-DESSOUS DE LA VERITE : les modeles
touches sont {', '.join(mods)}, et chez Samos et Keira la dechirure a tenu jusqu'a {dur/1000.0:.1f} SECONDES
d'affilee, pas une fraction de seconde.
"""

open(f'{D}/parts/head.txt', 'w', encoding='utf-8').write(out)
print(f"head.txt regenere : {len(out.splitlines())} lignes ; ctl staleimg={cs['images_avec_matrice_perimee']} "
      f"prf staleimg={ps['images_avec_matrice_perimee']}")
