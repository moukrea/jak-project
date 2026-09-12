# Un seul endroit nomme les fichiers d'etat, et l'impossibilite se lit partout ou elle existe — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

QUATRE SIGNALEMENTS DU 12/09 (reports/harness-impossible-state-hygiene/FINDINGS.txt). Le chantier precedent a donne au LECTEUR un nommeur unique. L'ECRIVAIN ne s'en sert pas encore.
1. `lib/proof_impossible.sh:44` fabrique toujours son nom tout seul (`"$D/proof$SUF-impossible.txt"`) au lieu de le deriver de `lib/impossible.py`. C'est EXACTEMENT la divergence qui rendait l'attente du bras d'ablation illisible, deplacee d'un cran en amont. Deux endroits qui fabriquent un nom finissent toujours par en fabriquer deux differents.
2. `validators/generic.sh:22` ecrit encore « proof.txt absent ou vide » en PREMIER sur sa sortie standard. L'orchestrateur reecrit desormais l'en-tete du JOURNAL, mais qui lit la sortie du validateur lui-meme lit toujours le mauvais diagnostic.
3. `logs/impossible-purges.log` est en ajout seul, sans rotation ni borne, avec DEUX ecrivains — l'orchestrateur au changement d'item, `proof_run.sh` au debut de course. Il grandit pour toujours, et deux ecrivains sur un fichier est la faute qui a deja coute une nuit ici.
4. `lib/backlog.py:394` ne lit les etats impossibles que des items ACTIONABLE : un etat debout sur un item `validated` ou hors file n'apparait JAMAIS dans le texte de l'owner, meme si le fichier existe. La purge le couvre en partie, pas entierement.

## Livrable — le contrat, en entier

`single_namer_defects` = 0, somme de termes publies SEPAREMENT.
1. L'ECRIVAIN et le LECTEUR derivent leur nom du MEME endroit. Publier, par bras, le nom produit par l'ecrivain et celui attendu par le lecteur : l'egalite est le verdict, sur les deux bras, ablation comprise. Un seul bras teste ne prouve rien — c'est le bras d'ablation qui etait aveugle.
2. La sortie du validateur ne commence plus par un diagnostic que la porte va contredire. Publier le compte de sorties ou les deux se contredisaient, mesure sur un etat SEME.
3. Le journal des purges a UN seul ecrivain et une borne. Publier sa taille et le nombre d'ecrivains observes.
4. Un etat debout sur un item hors file apparait quand meme dans le texte rendu. Preuve a deux bras : un etat SEME sur un item `validated` doit figurer dans le bras d'APRES et manquer dans celui d'AVANT. C'est le texte RENDU qui est juge.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change ni la detection de l'impossibilite ni les motifs de purge. Priorite 30 volontaire : la refonte de l'eclairage passe AVANT ce chantier.

## Ou l'owner regardera

Invisible. C'est la coherence des noms de fichiers d'etat du harnais.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

