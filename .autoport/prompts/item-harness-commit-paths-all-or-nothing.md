> LIS D'ABORD `prompts/item-harness-commit-paths-all-or-nothing-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un chemin qui refuse de s'indexer ne fait plus perdre le commit de tout un essai

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 12/09 (reports/gl-uniforms-dead-seven/FINDINGS.txt), verifie sur l'arbre. `orchestrator.py:854 git_commit_paths` fait UN SEUL `git add` pour tous les chemins sales. Le 12/09 a 02:26, a la fermeture de `lighting-legacy-purge`, un chemin a fait sortir git en fatal — « game/graphics/opengl_renderer/loader/PbrTestPattern.cpp ne correspond a aucun fichier » — et AUCUN des 64 fichiers n'a ete commite.
CE QUE CA A COUTE, MESURE. L'arbre porte depuis 357 insertions et 6390 suppressions que decrit aucun commit. Le constructeur bati depuis l'ARBRE : l'APK publie a 03:05 sur le commit cbc8e8598b porte donc du code d'un AUTRE item, bloque, dont l'essai avait ete tue. Pire, la mesure de `g […suite dans le contrat]

## Livrable
`commit_paths_defects` = 0, somme de termes publies SEPAREMENT.
1. Un chemin qui refuse de s'indexer n'emporte plus les autres : l'indexation se fait chemin par chemin, ou le lot est retente sans le chemin fautif. Publier le compte de chemins indexes et le compte de chemins refuses, separement — jamais un seul booleen.
2. Un refus est DIT dans le journal avec le chemin et la raison rendue par git, et l'essai ne se ferme pas en silence sur un commit vide. Publier le compte de commits vides evites.
3. Preuve a deux bras sur un depot jetable : un lot contenant un chemin impossible, juge par le code d'AVANT (zero fichier commite) et par celui d'APRES (tous les autres commites). Le chemin impossi […suite dans le contrat]

## Preuve exigee
`commit_paths_defects == 0` dans `reports/harness-commit-paths-all-or-nothing/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-commit-paths-all-or-nothing x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est la facon dont le harnais enregistre le travail d'un essai..

## Hors perimetre
Ne touche a aucun code du jeu. Ne commite et ne restaure rien de l'arbre courant.
