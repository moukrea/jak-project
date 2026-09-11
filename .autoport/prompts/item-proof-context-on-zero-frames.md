# Une course qui ne dessine rien dit POURQUOI, au lieu de se lire comme un moteur mort

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker lighting-legacy-purge (11/09) : proof_run ne savait pas distinguer « le moteur est casse » de « le systeme empeche de dessiner ». Cause reelle trouvee au 6e essai : l'app-op MIUI 10020 a `ignore` — corrigee au point de production. Mais CINQ courses avaient ete brulees, et trois essais entiers ont diagnostique a partir de zero. Le worker s'est aussi trompe en chemin : proximite et lumiere ambiante ne sont PAS deux temoins independants, c'est la meme puce.

## Livrable
`zero_frames_without_context` = 0 : toute course rendant frames=0 publie, a cote, l'etat qui l'explique ou l'exclut — fenetre focalisee, verrou d'ecran, app-op 10020, surfaceDestroyed, et le dernier marqueur de rendu atteint. Un frames=0 sans ce bloc est un defaut de l'instrument. Deux temoins cites comme independants doivent venir de composants differents : le publier.

## Preuve exigee
`zero_frames_without_context == 0` dans `reports/proof-context-on-zero-frames/proof.txt`.
Le proof se produit par `lib/proof_run.sh proof-context-on-zero-frames device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : instrument ; owner_test=false.

## Hors perimetre
Ne pas toucher au moteur. On documente la course, on ne la repare pas.
