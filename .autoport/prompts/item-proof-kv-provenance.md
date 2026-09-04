# La preuve ne doit recopier que ce que le MOTEUR a dit

## Defaut cite
Aucun retour de l'owner : defaut trouve le 2026-09-03 par le superviseur en verifiant une vraie
preuve d'appareil. La preuve de `cutscene-npc-flicker` portait quatre lignes qui ne viennent pas
du jeu : `isNeedSkipTouch=true`, `coldStartMode=DEFINITELY_BACKGROUND`, `bgMode=BACKGROUND`,
`lastIncreasingIntervalStartIndex=0`. Ce sont des lignes du framework Android.

## Cause connue
`lib/proof_run.sh` capture `logcat` SANS filtre de processus (`logcat -v time`, tout l'appareil),
puis recopie dans `proof.txt` toute ligne de la forme `cle=valeur` seule sur sa ligne. N'importe
quel processus du telephone peut donc ecrire une ligne que la porte lira. C'est inoffensif
aujourd'hui, les cles de porte etant trop specifiques pour entrer en collision, mais la promesse
de tout le dispositif — « c'est le moteur qui emet, jamais le worker, jamais personne d'autre » —
n'est pas tenue tant que ce chemin existe.

## Livrable
`proof.txt` ne porte que des lignes produites par le processus du jeu. Deux voies possibles :
filtrer `logcat` sur le pid du jeu (`--pid`, connu seulement apres le lancement, donc capture en
deux temps pour ne pas perdre la fenetre de demarrage), ou faire porter aux lignes du moteur un
marqueur, comme la ligne `FEATURE` en porte deja un. La seconde demande une edition du moteur et
se prouve mieux ; choisis, et dis pourquoi dans le rapport.

Ne casse pas ce qui marche : les champs `frames=`, `crash=`, la ligne `FEATURE` et les cles de
porte existantes doivent continuer d'arriver, sur x86 comme sur appareil.

## Preuve exigee
`proof_foreign_kv_lines == 0` dans `reports/proof-kv-provenance/proof.txt` : le compte des lignes
`cle=valeur` retenues qui ne proviennent pas du processus du jeu. Le compteur doit etre emis par
le runner lui-meme, qui est le seul a savoir ce qu'il a ecarte.
Le proof se produit par `lib/proof_run.sh proof-kv-provenance device`.
Controle positif attendu : sur une course ou le framework Android bavarde, le compteur doit avoir
ete NON NUL avant le correctif — mesure-le avant, publie les deux chiffres.

## Hors perimetre
Ne touche pas au validateur generique : il lit deja les bonnes cles, le defaut est en amont.
Ne reecris pas la capture x86, qui lit la sortie directe du binaire et n'a pas ce probleme.
Aucune capture d'ecran ne vaut preuve.
