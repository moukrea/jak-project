# Un `proof_run.sh <id> x86` lance pour un item dont le critere porte `device=1` le dit A LA PREMIERE LIGNE et l'inscrit dans proof.txt, au lieu de laisser le worker decouvrir au verdict que sa preuve ne sera jamais lue — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

22/09 : hud-eco-gauge a perdu DEUX essais d'affilee (15 et 16) sur le meme constat unique — « l'item exige l'appareil, la preuve est en source=x86 ». L'essai 16 mesurait pourtant hud_gauge_defects=0 : le chiffre n'a jamais ete lu. Le telephone (Redmi eae4df44) etait branche et joignable pendant les deux courses ; ce n'est donc pas une panne d'appareil mais un enchainement de worker : il calibre sur x86 (ce que le harnais lui recommande), puis rend la main sans refaire la course sur l'appareil. `lib/proof_run.sh:1713` ecrit `source=$MODE` sans jamais regarder si le critere de l'item exige l'appareil : rien, du lancement jusqu'au verdict, ne previent que cette course-la est perdue d'avance.

## Livrable — le contrat, en entier

`x86_proof_unwarned` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : nombre de verdicts archives (logs/*/validator-*.txt) dont le constat porte « exige l'appareil, la preuve est en source=x86 », par item et par date. Non nul (au moins 2 sur hud-eco-gauge les 21-22/09). Publier le compte et la liste.

2. L'AVERTISSEMENT EXISTE : pour un item dont le critere contient `device=1`, `lib/proof_run.sh <id> x86` ecrit, AVANT de lancer le moteur, une ligne visible dans son journal ET la cle `proof_will_not_be_judged=1` dans proof.txt. Le mot doit dire quoi faire : refaire la derniere course en `device`.

3. LE TERME MESURE : `x86_proof_unwarned` = nombre de courses x86 lancees sur un item a critere `device=1` qui n'ont PAS publie `proof_will_not_be_judged=1`. Le fabriquer : une course de controle sur un item a critere device sans le correctif rend 1, avec le correctif rend 0.

4. CONTROLE NEGATIF : une course x86 sur un item SANS `device=1` publie `proof_will_not_be_judged=0` et n'ecrit aucun avertissement. Publier les deux cotes.

## Hors perimetre

Ne change AUCUN critere de porte et n'assouplit rien : une preuve x86 sur un item a critere device reste refusee. Ne lance pas de course de lui-meme (c'est harness-judge-runs-the-proof-when-the-worker-left-none). Ne touche pas au choix d'appareil ni a pick_device.sh. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Rien a regarder dans le jeu : c'est du harnais. L'effet se lit au journal d'une course de calibration : le worker est prevenu tant qu'il lui reste du temps pour refaire la course sur le telephone.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

