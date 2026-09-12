> LIS D'ABORD `prompts/item-harness-stale-proof-caught-before-the-run-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Une preuve perimee se voit AVANT la course, pas au validateur une heure plus tard

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
PITFALLS porte deja la garde `editing-a-shared-verdict-source-reddens-every-in-flight-proof`, mais elle vise le SUPERVISEUR. Le cout qui reste vient du WORKER : il edite sa propre source (moteur, ou son recensement `lib/census/<id>.sh`), NE RELANCE PAS la preuve, et ne l'apprend qu'au validateur — apres avoir depense l'essai entier. Mesure du 2026-09-12 : 12 essais refuses pour ce motif sur 5 items (android-text-overrides-dropped 4, lighting-hdr 3, menu-back-label 2, lighting-legacy-purge 2, mesh-browser-removal 1). L'essai 1 de menu-back-label a couru 43 minutes avant de mourir la-dessus. L'outil de detection EXISTE (`bash lib/verdict_sources.sh <id>`) : ce qui manque, c'est qu'il soit lu a […suite dans le contrat]

## Livrable
`stale_proof_late_catches` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE. Publier, depuis les journaux de validateur archives, le compte d'essais refuses pour « source editee APRES la preuve », par item. Non nul — c'est le denominateur de cet item, et un zero AVANT rendrait la suite vide.
2. LA PEREMPTION SE DETECTE AVANT DE DEPENSER LA COURSE. La comparaison des sources epinglees contre le disque se fait au demarrage de la preuve, pas au verdict. Publier le compte de fichiers compares — non nul — et le code de sortie pris, distinct de celui d'un echec de mesure.
3. LE TEMOIN NE PEUT PAS ETRE VIDE. Dans un bac a sable jetable, semer DEUX controles : un fichier volon […suite dans le contrat]

## Preuve exigee
`stale_proof_late_catches == 0` dans `reports/harness-stale-proof-caught-before-the-run/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-stale-proof-caught-before-the-run x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur la duree des essais perdus..

## Hors perimetre
Ne change AUCUNE regle de ce qui est epingle : la liste des sources de verdict reste celle d'aujourd'hui. On deplace le moment de la lecture, on n'assouplit pas le juge. Ne touche pas au verdict d'un item en vol. Tout ce qui n'est pas cet item.
