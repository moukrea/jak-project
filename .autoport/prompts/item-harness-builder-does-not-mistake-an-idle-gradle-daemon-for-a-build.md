> LIS D'ABORD `prompts/item-harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le constructeur d'APK ne prend plus un demon Gradle inactif pour un build en cours, et dit dans son journal pourquoi il ne construit pas

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
16/09 17:41 -> 17/09 00:40 : SEPT HEURES sans build ni ligne de journal alors que des commits livrables (herbe, harnais, ocean a 00:16) attendaient. Cause mesuree par le superviseur : auto_build_apk.sh:398-403 compte `java` dans `busy` ET `hard` ; un GradleDaemon INACTIF (lance par le gradle d'un proof_run appareil, vivant 3 h) fait donc `continue` sans `say`, et la patience de 20 min ne s'applique jamais puisque `hard` > 0. `./gradlew --stop` a 00:25 a libere 2 demons ; le proof_run suivant en […suite dans le contrat]

## Livrable
`builder_silent_skips` = 0, somme de termes publies SEPAREMENT.

1. LE COUT D'AVANT EST CHIFFRE : duree du plus long silence du journal du constructeur entre deux ticks alors qu'un commit livrable non bati existait (>= 7 h le 16/09), et nombre de ticks muets ; non nuls.

2. UN DEMON GRADLE INACTIF N'EST PAS UN BUILD : la garde distingue un `java` GradleDaemon sans travail (etat Idle de `gradle --status`, ou aucun enfant compilateur et CPU nulle sur 10 s) d'un gradle qui construit ; l'inactif ne […suite dans le contrat]

## Preuve exigee
`builder_silent_skips == 0` dans `reports/harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet : un build publie dans l'heure qui suit un commit livrable, meme quand des mesures appareil tournent..

## Hors perimetre
Ne touche pas au publieur ni a proof_run.sh ; ne tue aucun demon Gradle a la place de la garde. Tout ce qui n'est pas cet item.
