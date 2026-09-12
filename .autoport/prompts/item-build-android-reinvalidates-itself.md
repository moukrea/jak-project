# L'arbre arm64 livre porte le meme declencheur que le bureau vient de couper

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 12/09 (reports/build-tree-reinvalidates-itself/FINDINGS.txt). `build-android/build.ninja` et `build-android/CMakeCache.txt:645` portent EXACTEMENT le defaut que l'essai 4 vient de couper sur le bureau : `SDL_REVISION` derive d'un `git describe`, donc CHAQUE COMMIT invalide l'arbre et relance une reconstruction complete.
CE QUE CA COUTE ICI, ET C'EST PIRE QUE SUR LE BUREAU : l'arm64 est l'arbre qui produit l'APK LIVRE a l'owner. Le harnais commite plusieurs fois par heure — chaque item, chaque tri de signalement, chaque note de superviseur. Le constructeur repart donc de zero en permanence, et c'est lui qui tient le verrou de deploiement pendant ce temps : le meme verrou qui a bloque une preuve 6 h 38 le 12/09.
Le bureau vient de passer de 335 cibles a 0 et de 444 s a 1 s. L'ordre de grandeur attendu ici est le meme.

## Livrable
`build_android_reinval_defects` = 0, somme de termes publies SEPAREMENT.
1. Une construction arm64 sans edition de source recompile ZERO cible, y compris APRES un commit. Publier le compte de cibles sur trois invocations consecutives dont une suit un commit fabrique pour l'essai.
2. La constante posee ne fige AUCUN numero de version en dur : publier d'ou elle est derivee. Le bureau a laisse ce defaut derriere lui, ne pas le recopier.
3. La constante survit a une reconfiguration : publier le resultat d'un arbre reconfigure a neuf. Si elle ne vit que dans le cache, l'item le DIT et le corrige.
4. Le binaire livre est IDENTIQUE avant et apres : empreinte du `.so` arm64 publiee des deux cotes. Un gain de temps qui change le binaire n'est pas un gain.
5. Le gain est chiffre en secondes, mesure, pas estime.

## Preuve exigee
`build_android_reinval_defects == 0` dans `reports/build-android-reinvalidates-itself/proof.txt`.
Le proof se produit par `lib/proof_run.sh build-android-reinvalidates-itself x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible dans le jeu. Le gain se voit sur la duree de chaque livraison et sur le verrou de deploiement..

## Hors perimetre
Ne touche a aucun code du moteur. Ne change pas le build de bureau, il vient d'etre traite.
