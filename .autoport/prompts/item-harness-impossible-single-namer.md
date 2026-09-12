> LIS D'ABORD `prompts/item-harness-impossible-single-namer-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un seul endroit nomme les fichiers d'etat, et l'impossibilite se lit partout ou elle existe

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
QUATRE SIGNALEMENTS DU 12/09 (reports/harness-impossible-state-hygiene/FINDINGS.txt). Le chantier precedent a donne au LECTEUR un nommeur unique. L'ECRIVAIN ne s'en sert pas encore.
1. `lib/proof_impossible.sh:44` fabrique toujours son nom tout seul (`"$D/proof$SUF-impossible.txt"`) au lieu de le deriver de `lib/impossible.py`. C'est EXACTEMENT la divergence qui rendait l'attente du bras d'ablation illisible, deplacee d'un cran en amont. Deux endroits qui fabriquent un nom finissent toujours par en fabriquer deux differents.
2. `validators/generic.sh:22` ecrit encore « proof.txt absent ou vide » en PREMIER sur sa sortie standard. L'orchestrateur reecrit desormais l'en-tete du JOURNAL, mais q […suite dans le contrat]

## Livrable
`single_namer_defects` = 0, somme de termes publies SEPAREMENT.
1. L'ECRIVAIN et le LECTEUR derivent leur nom du MEME endroit. Publier, par bras, le nom produit par l'ecrivain et celui attendu par le lecteur : l'egalite est le verdict, sur les deux bras, ablation comprise. Un seul bras teste ne prouve rien — c'est le bras d'ablation qui etait aveugle.
2. La sortie du validateur ne commence plus par un diagnostic que la porte va contredire. Publier le compte de sorties ou les deux se contredisaient, mesure sur un etat SEME.
3. Le journal des purges a UN seul ecrivain et une borne. Publier sa taille et le nombre d'ecrivains observes.
4. Un etat debout sur un item hors file apparait quand meme […suite dans le contrat]

## Preuve exigee
`single_namer_defects == 0` dans `reports/harness-impossible-single-namer/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-impossible-single-namer x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la coherence des noms de fichiers d'etat du harnais..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change ni la detection de l'impossibilite ni les motifs de purge. Priorite 30 volontaire : la refonte de l'eclairage passe AVANT ce chantier.
