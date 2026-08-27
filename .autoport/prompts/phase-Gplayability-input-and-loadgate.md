# JOUABILITE : LE SAUT NE REPOND PAS, ET RIEN N'ATTEND QUE LES NIVEAUX SOIENT CHARGES

Trois defauts releves par l'owner le 2026-08-27, sur la Shield, apres que la memoire et le
pre-calcul aient ete valides par lui.

## DEFAUT 1 — LE BOUTON DE SAUT NE FAIT RIEN (BLOQUANT : le jeu n'est pas jouable)

Owner : « la touche saut (X sur PS2, A en Xinput) ne fonctionne pas a la manette ».

MESURE (Shield, manette **8Bitdo SF30 Pro**, reconnue via `Vendor_045e_Product_02e0.kl`,
disposition Xbox) : le moteur VOIT la manette et recoit des evenements —

    sdl_button=9 pressed=1 (real gamepad)
    sdl_button=1 pressed=1 (real gamepad)

Numerotation SDL : 0=A, 1=B, 2=X, 3=Y, 9=LEFTSHOULDER. Donc le moteur recoit la gachette gauche
et B. **L'index 0 (A) n'apparait JAMAIS dans la trace.** Le probleme n'est pas le code du saut :
c'est que l'evenement du bouton A n'arrive pas, ou arrive sous un autre index.

Pistes, a trancher par MESURE et non par lecture :
- Les 8Bitdo changent de disposition selon leur mode d'allumage ; en mode Nintendo, A et B sont
  intervertis. Verifier ce que la manette envoie REELLEMENT (getevent) avant de toucher au moteur.
- Verifier la table de correspondance SDL utilisee pour ce VID/PID.
- Ne pas "corriger" en decalant les index a l'aveugle : ca casserait les autres manettes.

## DEFAUT 2 — LE JEU DEMARRE SANS ATTENDRE QUE LE NIVEAU SOIT CHARGE

Owner : « quand on revient de geyser rock la cinematique avec Samos declenche un fly over de la
plage et le niveau n'est pas charge assez vite donc il manque des elements. Pareil pour l'ecran
titre, le logo est visible bien apres le son d'intro ou il est sense apparaitre (et le niveau
apparait d'un coup), c'est mieux qu'avant mais c'est toujours pas nickel. »

Et sa demande, qui est la BONNE architecture :

    « Limite il devrait y avoir un mecanisme de chargement qui s'assure que tout le necessaire
      soit bien charge avant de lancer l'ecran titre, la on dirait que ca y va meme si rien n'est
      charge, c'est problematique quand ca charge pas assez vite ! »

Il faut donc une **barriere de chargement** : la scene ne demarre que lorsque ce dont elle a
besoin est reellement pret. Aujourd'hui le moteur lance la sequence sur une horloge et le rendu
rattrape comme il peut — d'ou le son en avance sur l'image, et le decor qui apparait d'un bloc.

Contraintes :
- Ne PAS resoudre en ralentissant tout le monde : sur une machine rapide, rien ne doit changer.
- La barriere doit porter sur ce dont la scene a BESOIN, pas sur "tout le niveau".
- Mesurer l'ecart son/image avant et apres, en millisecondes, sur la meme sequence.

## DEFAUT 3 — LE POP-IN AU RETOUR DE GEYSER ROCK

Meme cause probable que le 2 : le survol de la plage commence avant que ses elements soient la.
A traiter avec la meme barriere, et a prouver sur cette sequence precise.

## CE QUI EST DEJA ACQUIS — ne pas le casser

Valide par l'owner le 2026-08-27 : memoire du jeu 1370 -> 744 Mo, un niveau 122,1 -> 40,6 Mo,
textures au demarrage 6208 -> 571 ms. Sur la Shield : 4 min stables, pic 817 Mo, 0 tueur memoire,
0 plantage, pire blocage de texture 98 ms. **Toute correction doit conserver ces chiffres.**

## PIEGE DE LIVRAISON

Quand le format des niveaux change, un appareil deja equipe refuse de demarrer avec
`version mismatch when loading tfrag3 data. Got 43, expected 44`. Ca ressemble a un bug moteur,
c'est une livraison incomplete : repousser `out/jak1/fr3/` ET le zip d'assets HD.

## PERIMETRE APPAREILS

Shield (192.168.1.32:5555) et Redmi (eae4df44) autorises : installer, lancer, arreter, pousser des
assets, lire logs et mesures. **INTERDITS** : `pm move-*`, `settings put`, `sm`, `adb reboot`,
adoption ou migration de stockage. Eveil de la Shield : `KEYCODE_DPAD_DOWN` puis `KEYCODE_DPAD_UP`
toutes les minutes, uniquement quand le lanceur est a l'ecran, jamais pendant le jeu.
