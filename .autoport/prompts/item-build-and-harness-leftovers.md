> LIS D'ABORD `prompts/item-build-and-harness-leftovers-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le reliquat du chantier de la construction : neuf petites choses, aucune urgente

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
NEUF SIGNALEMENTS DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt), reunis ici parce qu'aucun ne merite son propre chantier. CE CHANTIER N'OUVRE PAS DE SUCCESSEUR : ses propres signalements s'ajoutent a lui.
1. `gate_verdict.py:118` : `code_scope` tranche en premier et la prose n'est JAMAIS relue. Un champ qui CONTREDIT l'`out_of_scope` passe sans un mot. Publier le compte de contradictions.
2. `orchestrator.py:1682` : le message de refus dit encore « mets `no_code: true` », alors que le champ qui fait foi depuis le 12/09 est `code_scope`. Le message envoie au mauvais endroit.
3. `third-party/discord-rpc/src/CMakeLists.txt` : la cible `clangformat` n'a AUCUNE sortie, donc elle se rejoue a chaque construction.
4. `.gitignore:181` : le motif `build-*/` n'est pas ancre et avale tout dossier commencant par `build-` a n'importe quelle profondeur, y compris une capture d'essai. […suite dans le contrat]

## Livrable
`build_leftovers_defects` = 0, somme de DIX termes publies SEPAREMENT, un par point.
Pour chacun : le defaut est RETROUVE sur le commit d'avant par le meme detecteur, puis absent apres. Un point qui ne peut pas etre retrouve avant n'est pas corrige, il est declare NON REPRODUIT et son terme le dit.
Le point 10 est le seul qui peut se conclure par « cause non etablie » : publier alors ce qui a ete ecarte et ce qui reste possible, pas un silence.

## Preuve exigee
`build_leftovers_defects == 0` dans `reports/build-and-harness-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh build-and-harness-leftovers x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. Petit outillage et petites incoherences..

## Hors perimetre
Ne touche a aucun code du jeu. N'ouvre AUCUN item successeur : ses propres signalements s'ajoutent a celui-ci. Priorite 37 : tout le reste passe avant.
