# Le jeu plante au demarrage sur le Honor de l'owner

## Defaut cite
- 2026-09-05 : « Alors j'ai supprimé les assets sur le HONOR pour mettre ceux de la dernière release sortie et mis à jour l'APK... Instant crash au startup »

## Cause connue
MESURE SUR LE HONOR DE L'OWNER (AREE026206000788, 2026-09-05 19:35, capture complete dans reports/honor-boot-crash/honor-logcat-2026-09-05.log). Le jeu boote CORRECTEMENT : packs a jour (CGO cfd93a73779c5, custom c1a5d489139ca), assets-v0.3.0 15 fichiers gardes, KERNEL.CGO charge, InitMachine retourne 0, niveau `title` charge et lie, « kernel: machine started », le rendu demarre. Puis SIGSEGV a la QUATRIEME IMAGE (`A36-TREE at-crash frame=4`).
PILE RESOLUE sur le libgk.so local :
  TFragment::setup_for_level  ->  unique_lock<mutex>  ->  std::mutex::lock()  -> SIGSEGV
Le verrou est celui pris dans `render_state->loader->get_tfrag3_level(level)` (TFragment.cpp:559) : c'est l'OBJET MUTEX qui est invalide, donc `render_state->loader` est nul ou detruit au moment ou le rendu attaque le niveau `title`.
AUTRE FAIT : la garde anti-boucle a deja tire — « 2 consecutive boots died before gameplay », elle a remis pbr-displacement a Off et pbr-test-preset a default. Le plantage PERSISTE apres ce reset : ce n'est donc pas un reglage PBR.
CONTEXTE : l'owner venait de supprimer ses assets pour installer ceux de la derniere release et de mettre l'APK a jour. A verifier en premier : le meme APK + les memes assets plantent-ils sur le Redmi ? Si oui c'est une regression pure ; si non, chercher ce que le Honor fait de different (Snapdragon 8 Elite, 60-120 Hz).

## Livrable
Le jeu survit au moins 600 images apres le demarrage du rendu, sur le Redmi ET sur l'appareil de l'owner. Le moteur emet `boot_crash_frames_survived`. Le correctif doit expliquer POURQUOI le mutex du loader etait invalide, pas seulement le rendre non nul.

## Preuve exigee
`boot_crash_frames_survived >= 600` dans `reports/honor-boot-crash/proof.txt`.
Le proof se produit par `lib/proof_run.sh honor-boot-crash device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : lance le jeu : il doit atteindre l'ecran-titre et y rester.

## Hors perimetre
Ne pas se contenter d'un garde-fou contre le pointeur nul : nommer la cause.
