# Handoff superviseur Codex → session Claude existante

16/09/2026, 15:28 CEST. Demandé explicitement par l'owner : prévenir Claude du travail
effectué pendant son absence et arrêter le côté Codex avant sa limite hebdomadaire.
Destinataire : session jaunt `claude:fc2d3cfc`, déjà active. Aucun nouveau superviseur lancé.

## Arrêt et état partagé

- Deux contrôles des processus : aucun orchestrateur, launch, veille Codex ou worker
  `codex exec` actif. Rien à tuer ; aucune relance effectuée pour cette passation.
- Les PID enregistrés des démons build/livraison, 311261 et 59525, sont eux aussi
  absents au contrôle final. Ils n'ont PAS été redémarrés. Leur autorisation antérieure
  portait sur la configuration normale, sans surcharge `ADB=false`, avec gardes USB.
- `.autoport/.backend.json` désigne encore `codex`, switching=false. Ne pas supposer
  que l'envoi de ce handoff a effectué une bascule technique. Coordonner la reprise
  depuis ta session existante ; éviter deux superviseurs ou deux orchestrateurs.
- HEAD observé avant ce handoff : `89d1388e86`. Arbre moteur propre. Modifications
  partagées non commitées : `.autoport/backlog.yaml` et `.autoport/.release_notes_hash`.
  Ne pas les écraser : le backlog courant contient les derniers états de l'orchestrateur.
- TMPDIR doit rester hors `/tmp` (quota utilisateur saturé). Répertoire utilisé :
  `/home/emeric/.cache/autoport-supervisor-tests`.

## Validations owner : ne pas les redemander

- `perf-dma-chain-copies` VALIDÉ par l'owner, phrase verbatim dans owner_ok ; build
  testé non identifié (`build_sha: null`). Garde `.autoport/acquis/perf-dma-chain-copies.sh`.
- `shrub-trunk-contact` VALIDÉ par l'owner. Il avait déjà dit les mini-palmiers bons,
  puis a dû rappeler explicitement sa validation. Ma demande de mesures supplémentaires
  était erronée : elle a été retirée. Ne jamais le remettre dans les éléments à tester.
  Garde `.autoport/acquis/shrub-trunk-contact.sh`, item de protection terminé.
- Le retour owner confirme aussi AO des shrubs bonne et disparition damier/pixelisation
  sur son build testé. Il ne valide PAS le contact mur/toit. Capture conservée :
  `.autoport/owner-feedback/2026-09-15-ao-hut-contact.png`. Texte original dans backlog.

## Priorité AO : cause du flou établie, correction encore partielle

Lire `.autoport/reports/ao-prepass-tie-alpha/handoff.md`, `FINDINGS.txt`, puis
`notes/attempt12-summary.md`, `attempt12-comparison.json` et `attempt12-build-delivery.json`.
Ne pas repartir du diagnostic ancien « alpha-test TIE » : corrigé/rectifié antérieurement.

L'owner voit une bande de mur claire exactement au raccord mur/toit. Il a proposé
l'hypothèse d'un flou diluant l'AO de contact ; les mesures l'ont confirmée localement.

- Essai10 / `adafa03109` : noyau de flou centré, déplacement supprimé. Sur téléphone,
  bande GTAO maximale 7 → 2 pixels ; résidus SSAO2/HBAO1/GTAO2. Identification physique
  de 425 pixels / 15 contacts mur/toit. Causalité locale vérifiée avec mêmes entrées.
  Six courses sans crash ; pas de validation globale, un côté manque toujours.
- Essai11 / `17b659564c` : reconstruction après flou assombrit le premier pixel, mais
  conserve pic clair à +1 ; le lecteur « préfixe » rendait zéro malgré ce défaut.
  Plusieurs milliers de pixels hors raccord changent : candidat NON qualifié.
- Essai12 / `c1581d95da`, sauvegarde WIP `89d1388e86` : reconstruction11 RETIRÉE.
  Les 36 sorties locales sont bit-identiques à la référence pré11 ; conservation du
  flou centré10 et ridge historique. Ce retrait n'est PAS une correction du contact.
  Trois variantes rejetées ; réduire le support détruit l'annulation du motif4×4 au pli
  (environ28 niveaux R8 de variation). Ne pas réintroduire ces variantes.
- Nouveau lecteur complémentaire `attempt12-analyze.py` juge les profils entiers,
  y compris pics/plateaux après le premier pixel sombre. Garder les anciens critères,
  les populations figées et les manquants/censurés ; pas de zéro artificiel.
- Rejeux locaux prêts : `attempt11-replay.py`, `attempt12-analyze.py`, commandes dans
  `attempt12-commands.md`. Shaders compilés GLSL/GLES et Android. Essais11/12 sans
  appareil, sans nouvel APK ni preuve. Leurs résultats Intel/Mesa ne valent pas preuve USB.
- Campagnes historiques 9/9 et 6/6 consommées ; pas de course supplémentaire autorisée
  dans les dernières reprises locales. Ne pas réutiliser proof.txt historique comme
  preuve actuelle. Item actuellement blocked max_retries10 : ce texte masque le bilan
  technique ci-dessus ; ne pas augmenter le budget pour rejouer le même essai.

## Autres avancées et blocages

- `ao-static-probe-deterministic`, `harness-delivery-stale-bake-recovery`,
  `dead-literals-round-3` sont terminés selon backlog (pas validations visuelles owner).
- Résolution : essai4 avait couvert 108 états et 1500/1500 transitions sans défaut,
  640×480=307200 pixels et 800×600=480000. Redémarrage réel et monotonie sous DRS
  restaient non prouvés. Il y a eu des essais ultérieurs : lire SON dernier handoff,
  ne pas prendre cet ancien bilan comme résultat final. Actuellement blocked max_retries6.
- `perf-mips2c-neon` : diagnostic initial de noyaux scalaires faux, plusieurs déjà
  vectorisés/inactifs. Candidat3D rejeté par comparaison des fonctions complètes :
  226 contextes divergents x86,335 ARM, mémoire différente. Aucun gain exact livré.
  Bancs locaux et diagnostic terminés ; nouvelle piste justifiée nécessaire.
- `perf-codegen-arm64-calls` : appels2 instructions sur47 sites, mais comparaison
  refset refuse le changement de CGO inclus dans l'empreinte data. 255 est ici une
  sentinelle de refus, PAS une différence RGB mesurée. Référencea2 immuable ; anciens
  écarts de répétabilité non résolus ; symboles proches/lointains incomplets. Aucun gain
  temporel démontré. Diagnostiquer le contrat de comparaison avant nouvelle course.
- Océan clipmap et coût de l'herbe actuellement blocked max_retries6 : consulter leurs
  derniers rapports avant arbitrage. `soft-baseline` a terminé côté machine ; voir ses
  FINDINGS non triés. Les anciens items lumière supplantés, HUD et Jak2 restent parqués.
- Dette signalée : packaging appelle `.autoport/apply_owner_tuning.py` absent sans
  échouer. Impact sur les réglages owner non établi, déjà remonté à l'owner.

## Harnais et méthode de reprise

Garde CMake première configuration réparée (`5471f0f7c6`,46 tests) ; permission
exécutable de `lib/build_x86.sh` restaurée. Suite la plus récente lue : 928 tests,
zéro rouge,160.1s, dans le dernier journal d'orchestrateur. Cela ne valide pas le jeu.
Le marqueur `.last_apk_build_commit` était resté ancien : ne pas promettre un build
publié sur la seule base d'un build local ou d'une installation de preuve.

Superviseur : backlog/harnais seulement, pas de code jeu ni de contact appareil.
Les messages owner sont verbatim ; aucun jeton inventé. Lire handoffs ET FINDINGS.
Le compteur max_retries ne remplace pas un diagnostic ni une nouvelle piste.
Utiliser un index Git privé pour commiter son propre travail, puis synchroniser les
seuls champs/fichiers concernés dans l'index partagé : des workers peuvent commiter
en même temps. Aucun rollback global, aucun git add global sur cet arbre partagé.

Codex laisse la main à Claude et ne relance plus son côté après cette passation.
