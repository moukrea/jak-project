# Un appel de fonction GOAL coute deux instructions, pas huit — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

16/09 ARBITRAGE OWNER : garder si gain potentiel, « mais faut que ca casse rien ». Etat : appels a 2 instructions livres (essai 6), 4980 images sur le Redmi sans crash, MAIS codegen_lot_defects=1 parce que le comparateur refset REFUSE le CGO modifie (provenance=data, maxdiff255 = sentinelle de refus, PAS un ecart RGB) et aucun gain de temps n'a jamais ete mesure. 3 essais, strategie : (1) diagnostiquer le contrat de comparaison : un CGO dont le CODE change est l'effet ATTENDU de cet item, la comparaison doit porter sur les pixels rendus contre la reference a2, pas sur l'empreinte des donnees ; ne pas recapturer la reference pour fabriquer le vert ; (2) publier le maxdiff RGB reel ; (3) mesurer goal_busy_ms avant/apres sur la meme scene, >=300 images par bras, publier codegen_gain_us. Sans gain mesure > 0 en 3 essais, archive.

Backend arm64 = traduction 1:1 du modele x86 (IGenARM64.cpp). Appel : ADD + 3 STP + BLR + 3 LDP (:1831-1882) pour sauver X3/X5/X10/X11/X12/X23 « saved » x86 mais caller-saved en AAPCS. Symbole : ADRP+ADD+LDR (IR.cpp:636-674, marqueur A5), s7/X14 inutilise. Acces memoire : ADD X16,Xaddr,X15 avant chaque load/store (:1198-1347), jamais [Xn,Xm]. Trampoline GOAL->C ~45 instr (kscheme.cpp jak1:856-982) avec check X30 toujours actif. pc-prof appele 20-30 fois par image vers un stub (gcommon.gc:29).

## Livrable — le contrat, en entier

Lot 1 : enrobage d'appel reduit aux saved vivants (ou sauvegarde en prologue callee), LDR [X14,#imm12] pour les symboles a moins de 16 Ko, forme [Xn,Xm] ou base pre-ajoutee pour les acces, pc-prof branche sur perf-instruments ou coupe sans recepteur. Le moteur publie codegen_lot_defects = (refset_replay_maxdiff != 0) + (boot non survecu 600 images) + (instructions par appel sur 5 fonctions marqueurs > cible). goalc rebati, GAME/ENGINE.CGO regeneres et verifies par grep -a, references refset recapturees une fois avec cause nommee.
N. GAIN MESURE : publier `codegen_gain_us` = goal_busy par image AVANT moins APRES sur l'appareil, meme scene, >= 300 images par bras ; un gain nul ou negatif est un defaut.

## Hors perimetre

Pas de changement de convention d'appel visible du C++ (asm_funcs_arm64.s, kscheme) dans ce lot. Ne touche a aucune feature validee.

## Ou l'owner regardera

rien a voir : identique au pixel ; goal_busy_ms baisse

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

