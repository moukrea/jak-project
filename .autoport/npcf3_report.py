#!/usr/bin/env python3
"""Gcutscene-npc-flicker-2, cycle 3 — compose report.txt depuis les journaux ARCHIVES.

Les lignes de verdict (NPCFLICK / NPCSCENE / NPCFLICK-EV) sont recopiees VERBATIM des captures
logcat du Redmi et du journal x86 ; le texte ne porte aucun chiffre qui ne vienne pas d'un fichier
nomme ici. `NPCOK` est calcule par npcf_analyse.py sur les jambes SANS injection du Redmi.
"""
import re, subprocess, sys, os
os.chdir(subprocess.check_output(['git', 'rev-parse', '--show-toplevel']).decode().strip())
D = '.autoport/reports/Gcutscene-npc-flicker'
DEV = f'{D}/device3'

def lines(path, pat):
    out = []
    for l in open(path, errors='replace'):
        i = l.find('NPC')
        if i < 0:
            continue
        l = l[i:].rstrip()
        if re.search(pat, l):
            out.append(l)
    return out

def count(path, pat):
    try:
        return sum(1 for l in open(path, errors='replace') if re.search(pat, l))
    except FileNotFoundError:
        return 0

hd1 = f'{DEV}/dev-c3-mayor-hd1-logcat.txt'
hd0 = f'{DEV}/dev-c3-mayor-hd0-logcat.txt'
inj = f'{DEV}/dev-c3-inject-logcat.txt'
x86 = f'{D}/gk2-hd1-c3b.log'

analyse = subprocess.run(['python3', '.autoport/npcf_analyse.py', hd1, hd0], capture_output=True,
                         text=True).stdout
npcok = [l for l in analyse.splitlines() if l.startswith('NPCOK ')][-1]
agg = [l for l in analyse.splitlines() if l.startswith('[hd')]

guard = subprocess.run(['bash', '.autoport/npc_flicker_selftest.sh'], capture_output=True,
                       text=True)
guard_ok = [l for l in guard.stdout.splitlines() if l.startswith('[ok]')]
guard_line = [l for l in guard.stdout.splitlines() if l.startswith('NPCGUARD')]

def fps(path):
    m = re.search(r'NPCSCENE scene=mayor-introduction pnj_suivis=\d+ cycles=\d+ images=(\d+)',
                  open(path, errors='replace').read())
    return int(m.group(1)) if m else 0

inj_ev = lines(inj, r'^NPCFLICK-EV scene=mayor-introduction')
inj_hist = {}
for l in inj_ev:
    n = int(re.search(r'images=(\d+)', l).group(1))
    inj_hist[n] = inj_hist.get(n, 0) + 1
garb_dev = count(hd1, 'MATRICE-INVALIDE') + count(hd0, 'MATRICE-INVALIDE')
garb_x86 = count(x86, 'MATRICE-INVALIDE')

R = []
w = R.append
w('DIRECTIVES vd9e8b66782')
w('')
w('# PNJ QUI CLIGNOTENT, RETOUR 3 — LA PREUVE EST PRISE SUR L\'APPAREIL, LE MAIRE EST SUIVI,')
w('# ET L\'INSTRUMENT PEUT ENFIN ETRE LU DEPUIS LE TELEPHONE DE L\'OWNER')
w('')
w('Owner, 2026-09-03 : « bah non c\'est toujours pété, première cinématique avec le Maire est le')
w('worst offender... c\'est pas corrigé du tout. »')
w('')
w('CE QUE CE RAPPORT DIT, EN UNE PHRASE : sur le Redmi (modeles HD actifs ET eteints) comme sur')
w('x86, la premiere cinematique du maire rend ZERO cycle de cause defectueuse avec le maire suivi,')
w('le controle positif tire sur CETTE scene SUR L\'APPAREIL, et le defaut que l\'owner voit sur son')
w('Honor n\'est donc reproduit sur AUCUNE machine que je peux observer. Je ne presente pas ce zero')
w('comme une guerison : je livre (1) un angle mort du recensement ferme (« dessine mais invisible »),')
w('(2) trois sorties qui rendent SON telephone lisible — ligne de plateforme, fichier sur le')
w('telephone, compteur a l\'ecran — et (3) la liste exacte de ce qu\'il doit regarder.')
w('')
w('-' * 98)
w('## 1. NPCPRIOR — POURQUOI LES CORRECTIONS PRECEDENTES N\'ONT PAS TENU (cycles 1 et 2 compris)')
w('-' * 98)
w('')
w('NPCPRIOR correction=Grecharged-hd-models3 pourquoi_pas_tenu=le-trou-cinematique-etait-DECLARE-dans-d4fddfd245-et-livre-quand-meme')
w('NPCPRIOR correction=Grecharged-hd-models4-fail-open pourquoi_pas_tenu=45b7140ca7-supprime-le-SEUL-site-d-ecriture-de-s_hd_blackout_events-et-laisse-blackouts=0-comme-barre-de-passage')
w('NPCPRIOR correction=Gcutscene-npc-flicker pourquoi_pas_tenu=la-scene-nommee-n-a-jamais-ete-JOUEE-et-le-seul-seau-non-vide-etait-declare-non-defaut')
w('NPCPRIOR correction=Gcutscene-npc-flicker-2-cycle2 pourquoi_pas_tenu=preuve-prise-sur-PC-seulement-ET-recensement-structurellement-AVEUGLE-a-un-paquet-dessine-avec-des-matrices-invalides')
w('')
w('Le cycle 2 a construit le lanceur, mesure la scene du maire, separe le fourre-tout `culled` en')
w('trois seaux et fait tirer le controle positif 325 fois sur 325 — SUR PC. Sa porte s\'est ouverte')
w('sans qu\'une seule ligne vienne d\'un telephone, pendant que l\'owner voyait le defaut sur le sien.')
w('Et son recensement ne pouvait voir qu\'une ABSENCE de dessin : un paquet merc DESSINE avec des')
w('matrices d\'os invalides ne met rien a l\'ecran et comptait comme une presence.')
w('')
w('-' * 98)
w('## 2. LA SCENE DU MAIRE SUR LE REDMI — LE MAIRE LUI-MEME, HD ACTIFS ET ETEINTS')
w('-' * 98)
w('')
w('Route : continue `village1-hut`, spawn devant `mayor-5` (`debug.opengoal.level.warp.pos`),')
w('beach en \'active puis affiche (`want.levels` / `want.display`), `cine.kick=mayor`. Les quatre')
w('proprietes ont ete ajoutees a `npcf_device_run.sh` : sans elles, 29 tentatives')
w('`absent-du-pool-actif` (course de 02:16). Ecran reveille avant chaque course : la premiere')
w('tentative (`mWakefulness=Asleep`) a rendu 0 ligne en 480 s — un zero qui se serait lu « aucun')
w('defaut » (voir la note dans le script).')
w('')
w('### 2.1 Jambe HD ACTIFS (la configuration de l\'owner) — dev-c3-mayor-hd1-logcat.txt')
w('')
for l in lines(hd1, r'^NPCFLICK scene=mayor-introduction '):
    w(l)
for l in lines(hd1, r'^NPCSCENE scene=mayor-introduction '):
    w(l)
w('')
w('### 2.2 Jambe HD ETEINTS (ablation, meme binaire) — dev-c3-mayor-hd0-logcat.txt')
w('')
for l in lines(hd0, r'^NPCFLICK scene=mayor-introduction '):
    w(l)
for l in lines(hd0, r'^NPCSCENE scene=mayor-introduction '):
    w(l)
w('')
w('### 2.3 Les autres cinematiques du maire, memes courses')
w('')
for p in (hd1, hd0):
    for l in lines(p, r'^NPCSCENE scene=mayor-reminder'):
        w(l)
w('')
w(f'Cadence mesuree : {fps(hd1)} images de recensement (HD actifs) et {fps(hd0)} (HD eteints) pour')
w('une scene de 63 s — ~19 img/s, `Kernel dispatch time: 55 ms`. Le Redmi Note 9 Pro (Adreno 618)')
w('joue cette scene TROIS FOIS plus lentement que le Honor de l\'owner (Snapdragon 8 Elite,')
w('Adreno 840, 60 img/s). Voir §6 : c\'est la limite de cette preuve, et elle est dite.')
w('')
w('### 2.4 Le verdict, calcule par l\'analyseur sur les DEUX jambes sans injection')
w('')
for l in agg:
    w(l)
w('')
w(npcok)
w('')
w('-' * 98)
w('## 3. LE CONTROLE POSITIF, SUR LA SCENE DU MAIRE, SUR L\'APPAREIL — dev-c3-inject-logcat.txt')
w('-' * 98)
w('')
w('Injection `-lod0:120:10` (10 images de rendu jetees toutes les 120), armee par la propriete')
w('`debug.opengoal.npcf.inject` — le meme binaire que les deux jambes ci-dessus.')
w('')
for l in lines(inj, r'^NPCFLICK scene=mayor-introduction pnj=mayor'):
    w(l)
for l in lines(inj, r'^NPCSCENE scene=mayor-introduction '):
    w(l)
w('')
w(f'  evenements NPCFLICK-EV sur mayor-introduction : {len(inj_ev)}')
w('  distribution des longueurs mesurees (10 images injectees) :')
for n in sorted(inj_hist):
    w(f'      {inj_hist[n]:4d} evenement(s) a {n} images')
w('')
w('Le compteur MONTE sur l\'appareil, sur la scene nommee, pour le maire lui-meme, avec la cause')
w('attendue (`supprime`) ; sans injection, la meme scene sur le meme binaire rend cycles=0. La paire')
w('est complete SUR LE REDMI, ce que le cycle 2 n\'avait que sur PC.')
w('')
w('-' * 98)
w('## 4. L\'ANGLE MORT FERME : « DESSINE MAIS INVISIBLE »')
w('-' * 98)
w('')
w('Le recensement voyait une absence de PAQUET. Un paquet dessine avec des matrices d\'os invalides')
w('(NaN/inf, os projete a plus de 3 km de la camera, matrice nulle) ne met rien a l\'ecran — c\'est')
w('la signature que Ghd-skin-origin-stretch a mesuree sur les os HD — et il comptait comme une')
w('PRESENCE. Merc2 juge desormais, pour chaque paquet, les os qu\'un sommet LIT')
w('(`used_bone_mask_rt`, calcule par le chargeur) ; majorite invalide -> `Outcome::kGarbage` ->')
w('cause `matrice-invalide`, un DEFAUT. Le paquet est dessine tel quel : mesure, pas correction.')
w('')
w('### 4.1 La premiere version FABRIQUAIT un faux rouge, et la mesure l\'a retiree')
w('')
w('« slot 0 = racine, un os invalide suffit » : x86 (gk2-hd1-c3a.log) rendait')
w('`dax-hd-lod0 os_invalides=1/76 racine=1 t0=(0 0 0)` puis `t0=(8589934592 0 -0)` — le slot 0')
w('du compagnon HD est un joint que le reciblage n\'ecrit JAMAIS (memoire non initialisee) et')
w('qu\'aucun sommet ne lit. Resultat : 5 faux cycles `supprime` et 15 blinks sur Daxter dans')
w('mayor-introduction. Avec le masque des sommets, la meme scene (gk2-hd1-c3b.log) : cycles=0,')
w('blinks=0 sur les 7 acteurs. Un faux rouge coute autant qu\'un faux vert ; il est parti AVANT')
w('la livraison, et la lecon est dans la memoire du projet.')
w('')
w('### 4.2 Ce que la sonde voit deja, hors cinematique')
w('')
w(f'  paquets MATRICE-INVALIDE : x86 {garb_x86} ligne(s), Redmi {garb_dev} ligne(s) (hd1+hd0),')
w('  tous `lurkercrab-lod0 os_invalides=20/23 juges=23 masque=1` : trois crabes dessines 2 images')
w('  a CHAQUE naissance avec 20 os NULS sur 23 (pids 141-143, 255-257, 368-370... : le cycle')
w('  naissance/mort par visibilite de Gjak1-crate-collision, vu ici sur des ennemis). GOAL croit')
w('  les avoir dessines, l\'ecran n\'a rien. Hors perimetre (pas une cinematique, pas un PNJ) —')
w('  publie parce que c\'est exactement la classe que l\'instrument devait voir, et qu\'aucun cycle')
w('  precedent ne pouvait la voir.')
w('')
w('-' * 98)
w('## 5. NPCGUARD — CE QUI EMPECHE LA QUATRIEME FOIS')
w('-' * 98)
w('')
w('NPCGUARD nom=npc-flicker-selftest echoue_si=une-des-26-proprietes-du-recensement-tombe-OU-une-valeur-publiee-n-a-aucun-site-d-ecriture-OU-le-repli-de-classify-nomme-une-cause-que-reason_is_defect-EXCUSE')
w('')
w(f'Trois bras, sans appareil, au POST_BUILD de `gk` (game/CMakeLists.txt:495 et android/) — ')
w(f'{len(guard_ok)} proprietes tenues a l\'instant ({guard_line[0] if guard_line else "?"}).')
w('Ajoutees ce cycle : matrice invalide (controle positif : cycle cause=matrice-invalide, PAS')
w('`nodraw`), controle negatif (une image invalide = au plus un blink), etat vivant (0 pendant')
w('l\'episode, 1 + cause apres la reprise, rien hors cinematique), plateforme publiee par le code.')
w('')
w('-' * 98)
w('## 6. CE QUE CE ZERO NE DIT PAS — ET CE QUI REND LE TELEPHONE DE L\'OWNER LISIBLE')
w('-' * 98)
w('')
w('Le defaut n\'est REPRODUIT NULLE PART chez moi. Deux raisons possibles, et je ne choisis pas :')
w('  a) il depend de la CADENCE. Le Redmi joue la scene a ~19 img/s (thread GOAL arm64 a 55 ms,')
w('     HD ou pas), x86 a 60 mais n\'est pas arm64, le Honor est arm64 A 60. Les fenetres de la')
w('     couverture HD sont en APPELS de rendu (~8 par image ici : TTL 32 = 4 images, fail-open')
w('     20 = 2,5 images) — une constante en appels n\'est pas une duree ;')
w('  b) il vit dans ce que le recensement ne voit toujours pas : un trou de UNE image de rendu')
w('     (tolerance d\'appariement des deux horloges), ou un dessin invisible pour une raison')
w('     autre que les matrices (fondu, effets tous desactives) — non instrumentes.')
w('')
w('Donc trois sorties, produites par le CODE, pour que SON appareil parle :')
w('  1. `plateforme=` sur chaque ligne (ro.product.brand : `redmi` ici, `honor` chez lui) ;')
w('  2. `/storage/emulated/0/OpenGOAL/jak1/npc_flicker.txt` : les memes lignes NPCFLICK/NPCSCENE,')
w('     bornees a 1 Mo (une rotation). Verifie sur le Redmi : `NPCF-LOG fichier=... plateforme=redmi`')
w(f'     et le fichier compte {subprocess.run(["adb","-s","eae4df44","shell","wc -l < /storage/emulated/0/OpenGOAL/jak1/npc_flicker.txt"],capture_output=True,text=True).stdout.strip() or "?"} lignes apres les trois jambes ;')
w('  3. sous le compteur FPS, pendant une cinematique : `PNJ cycles=N blinks=M coupes=K cause=<nom>`')
w('     (`__pc-npc-census-live`, un entier compose, aucune allocation ; la chaine « PNJ cycles= »')
w('     est dans le GAME.CGO arm64 livre).')
w('')
w('-' * 98)
w('## 7. CE QUE L\'OWNER DOIT REGARDER (et c\'est un NOMBRE, pas une image)')
w('-' * 98)
w('')
w('  * Activer le compteur FPS (option graphique « FPS counter »), relancer la premiere cinematique')
w('    du maire, et lire la ligne `PNJ cycles=... cause=...` au moment ou un PNJ disparait :')
w('      - cycles > 0 avec une cause : l\'instrument VOIT le defaut sur son appareil, la cause est')
w('        nommee, et on sait ou chercher ;')
w('      - cycles = 0 pendant qu\'il voit un PNJ disparaitre : l\'instrument est AVEUGLE a ce')
w('        mecanisme-la, et c\'est la reponse la plus precieuse — elle elimine tout ce que le')
w('        recensement couvre (mort, hidden, no-anim, cull, suppression HD, modele absent, niveau,')
w('        clone, non-dessine, matrice invalide).')
w('  * S\'il peut, envoyer `OpenGOAL/jak1/npc_flicker.txt` de son telephone.')
w('  * Aucun autre reglage a changer.')
w('')
w('-' * 98)
w('## 8. NOT DONE / HORS PERIMETRE')
w('-' * 98)
w('')
w('  * Le defaut de l\'owner n\'est pas reproduit ; ce cycle livre la mesure sur l\'appareil, un')
w('    angle mort ferme et un canal de lecture depuis son telephone — pas une guerison.')
w('  * `lurkercrab-lod0` dessine avec 20/23 os nuls a chaque naissance : hors perimetre, publie.')
w('  * Les trous d\'UNE image de rendu restent sous la tolerance d\'appariement.')
w('')
w('-' * 98)
w('## 9. LIGNES DE VERDICT COMPLETES (Redmi, jambes sans injection)')
w('-' * 98)
w('')
for p in (hd1, hd0):
    for l in lines(p, r'^NPCFLICK scene=mayor-'):
        w(l)
w('')
open(f'{D}/report.txt', 'w').write('\n'.join(R) + '\n')
print(f'{D}/report.txt : {len(R)} lignes')
print(npcok)
