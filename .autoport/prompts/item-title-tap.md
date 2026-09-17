# « Appuie sur start ou touche l'ecran » et le tap au titre

## Defaut cite
- 2026-09-11 : « TERMINÉ, MAIS RÉGRESSÉ! SUR ANDROID (AVEC TACTILE, SUR SHIELD ON DEVRAIT AVOIR « Appuie sur start ») ON A « Appuie sur start » AU LIEU DE « Appuie sur start ou touche l'écran » »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh title-tap x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'ecran titre : le texte et un tap sur l'ecran.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
