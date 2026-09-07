# Récupération des références — essai 14
DIRECTIVES v6fca51fe40

## Ce qui change

La provenance input v2 vient désormais de `pad_replay::replay_input_fingerprint()` :
les octets du header et des records sont hachés pendant leur lecture. Le remplacement du
chemin ne change plus l'identité des records déjà chargés. La base historique refset est
conservée (1469598103934665603, et non la base FNV standard). Mode hors Replay, header
invalide, version inconnue, lecture partielle/erreur et fermeture échouée donnent zéro.
L'acceptation historique des records complets d'une queue partielle n'est pas changée ;
seule leur qualification est refusée. Le selftest existant vérifie ces cas.

Le registre des rejeux ajoute `input` ; la sélection des lignes exige aussi la même
configuration pour le calcul de stabilité. Les lignes antérieures restent conservées,
mais ne reçoivent pas de crédit d'identité d'entrée qu'elles n'ont pas enregistrée.
Les sentinelles de couverture, d'état et de baseline ne sont pas supprimées.

Le lecteur FR3 fork accepte explicitement la v43 du pristine. Les deux seuls champs
sérialisés ajoutés en v44 sont les vecteurs u16 `baked_tangents` en tête de TfragTree et
TieTree ; la lecture v43 les vide, sans consommer d'octets. L'écriture produit la v44,
avec header et footer cohérents. Version inconnue/footer incohérent restent rejetés.
Aucun fichier FR3 d'origine n'est réécrit, aucun renderer pristine n'est modifié.
Les tangentes absentes empruntent le fallback existant : ce n'est pas une qualification
photométrique du rendu enrichi. Le header partagé impose le build gk ET goalc.

## Frontière d'état — constat de lecture, pas preuve de restauration

L'audit corrige la piste du handoff 13 : `actors-update` est déjà trop tard.
`birth(bsp-header)` crée ambiances et caméras auparavant (entity.gc:859–915).
La frontière commune exploitable est avant le `play` final d'InitMachineScheme
(fork kmachine.cpp:5777, pristine:641), avant le premier KernelDispatch.
GAME a toutefois déjà initialisé des états à cet endroit : la graine de
`*knuth-rand-state*` vient de l'heure RTC dans pc/util/knuth-rand.gc:70, même dans pristine.
Les callbacks reseed actuels ne la couvrent pas. DecodeTime précède GAME et permettrait
une heure enregistrée/rejouée. Les horloges EE murales doivent aussi être traitées.

Piste bornée : session neuve par cas ; `(play #t #f)` puis méthode native
`initialize! *game-info* 'game #f "<continue>"` avant premier dispatch. Le titre reste
chargé par play ; ne pas prétendre que kernel-boot-level choisit ce niveau. Appels via
trampoline avec contexte de processus valide, RNG GOAL ET natifs et horloges enregistrés.
Ce protocole n'est PAS implémenté ni mesuré. Employer les CGO pristine communs ne
qualifierait que le moteur sur ces données, pas les CGO fork livrés (callbacks PC absents).

## Piste DMA écartée

Les deux sources dma_copy.{h,cpp} sont identiques, mais serialize_last_result n'a aucun
appel trouvé ni outil de rejeu. La chaîne seule ne porte pas les textures hors chaîne,
les pointeurs GOAL embarqués (TextureUploadHandler lit ee_mem + upload.page), ni l'état
persistant renderer/loader. Ce n'est pas un checkpoint monde ni rendu autonome.
Aucun nouveau harnais DMA ajouté, aucun gel supplémentaire de la simulation.

## Mesures

Les résultats exécutés sont dans build-essai14.log, input-selftest-essai14.log,
essai14-data/*.log et proof-run-essai14.log. Le test FR3 utilise une fixture produite
par la bibliothèque pristine, indépendamment du lecteur fork, et de vrais FR3.
La preuve officielle reste le seul résultat de lib/proof_run.sh.
La course est volontairement courte (60 s), un seul cas legacy/origine/h00 : elle ne
remplace ni la couverture complète ni cinq rejeux, et ne peut adopter une référence.
Les historiques et leurs écarts précédents sont conservés dans essai13-avant14/.

Résultat test indépendant : `fr3-compat PASS inputs=27` (fixture + les 26 FR3 pristine,
dont GAME et sunkenb). Pour chaque entrée : `reused_clear=1 roundtrip_exact=1`.
Quatre rejets incohérents par SIGABRT (signal=6). Le writer pristine porte sa bibliothèque
identifiée dans essai14-data/artifacts.sha256 ; les commandes exactes sont conservées.
Ces tests sont une compatibilité de sérialisation, PAS une qualification du rendu ni une
preuve de visibilité de Sunkenb. Aucun build du pristine n'a été nécessaire.
