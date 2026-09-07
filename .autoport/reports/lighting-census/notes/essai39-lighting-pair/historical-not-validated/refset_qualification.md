# Qualification et adoption des références v2

DIRECTIVES v6fca51fe40

Les références historiques restent à leur place. Une capture qualifiable réserve
une nouvelle racine v2 ; aucune conversion de version ni copie dans `.autoport/refset`
n'est nécessaire. Le moteur produit les reçus ; `proof_run.sh` produit seul la preuve.
Les tests autonomes utilisent des fixtures temporaires et ne constituent pas une preuve jeu.

## Provenance et état

Après le build incrémental, `refset_provenance.py seal --root WORKTREE --role
baseline|candidate --output NEW.json` archive le patch source et les empreintes.
`verify NEW.json` revérifie les fichiers, le binaire et le patch courant. Le rôle
baseline exige le worktree historique `a9ea15a69062a57335278db7680cd647df3c1e1d`,
ses shaders inchangés et les adaptations renderer déjà acquises dans le patch33.
Un autre binaire arbitraire ne devient donc pas la baseline. Le certificat décrit
le binaire et les sources disponibles ; il ne démontre pas une compilation reproductible.

Les lots passent par `refset_campaign.py`, décrit dans `refset_campaign.md`. Ajouter
aux entrées du lot :

- `OG_REFSET_BUILD_PROVENANCE` : chemin absolu du certificat scellé après build ;
- `OG_REFSET_QUALIFY_STATE=1`, `OG_REFSET_REQUIRE_LOADED=1` ;
- `OG_BOOT_REPLAY_REPLAY` : stream existant, frontière `actors-sweep` ;
- le même pad replay, les réglages et le calendrier de chargement entre les bras.

Le stream doit avoir été **consommé en replay** et entièrement vérifié. Le mode
capture d'un bootstrap ne peut pas attester sa propre reproduction. À chaque cas,
le moteur associe la chaîne rendue au témoin postdispatch LF ou LF−1 : RNG,
horloges, identités/états des acteurs observés, réglages PC et caméra/position cible.
Le témoin canonique est écrit dans `image.png.state.bin`, puis comparé en entier
au rejeu. C'est une reconstruction observée depuis le démarrage, pas un snapshot
exhaustif des variables privées, animations et coroutines de tous les acteurs.
La comparaison indépendante des images complète cette observation partielle.

L'adoption exige aussi que chaque racine porte l'empreinte CGO/DGO/FR3 du run
appelant, recalculée par le producteur. Un manifeste d'anciennes racines ne peut
donc pas qualifier un autre jeu de ces données. Pour chaque racine, les ensembles
de ressources consommées doivent être identiques entre capture et replays ; seuls
les noms de snapshots et checkpoints peuvent varier. Les ressources des deux
binaires indépendants ne sont pas supposées identiques.

## Lots et cinq rejeux

Un lot conserve son propre calendrier, son bootstrap et ses références : changer
la sélection des cas change son identité. Les vues supplémentaires gardent leurs
chemins `supplement-v1`. Les PNG ne se déplacent pas entre sous-plans.

Un lot candidat peut couvrir les trois modes et les huit heures d'une vue ; la
baseline ne doit couvrir que les cas origine correspondants, aux mêmes frames et
états. Une recette de démarrage différente exige son propre bootstrap vérifié.
Les options de caméra de calibrage empêchent la qualification.

Une capture terminée écrit `qualification-capture.json`. Chaque replay écrit un
reçu neuf `qualification-replays/<RUN_ID>.json`, lié au hash de cette capture.
Les fichiers d'état, sidecars, témoins binaire, sources et snapshots immuables du
manifeste des assets consommés restent associés aux reçus. Un identifiant ne peut
pas être réutilisé pour écraser un run. Les échecs présents sont tous relus.

Cinq noms de lots replay distincts produisent cinq exécutions effectives pour
chaque racine baseline et candidat. Réutiliser une tentative identique ne crée
aucun crédit supplémentaire. Une référence, une source ou une entrée modifiée
invalide les reçus associés ; les tentatives précédentes restent archivées.

## Transition du producteur

`OG_REFSET_QUALIFICATION` désigne un JSON de **chemins**, pas un verdict :

```json
{"version":1,"pairs":[{"baseline":"/racine/baseline-vue","candidate":"/racine/candidat-vue"}]}
```

À la fin d'un replay exact, le moteur relit ce manifeste, toutes les pièces et
tous les reçus. Il compare lui-même les PNG origine baseline/candidat, ainsi que
leurs états complets enregistrés. Les modes ON et OFF ne sont jamais comparés
entre eux. L'union doit couvrir les 672 cas de la table livrée : 28 vues, trois
modes, huit heures, univers des 21 niveaux, au moins quatre intérieurs et ciel
150..900‰ pour chaque niveau à ciel, mode et heure. Sunkenb reste exigé.

Pièces manquantes : statut `incomplete`, sentinelle254, liste explicite en log.
Pièce périmée, rejeu divergent ou provenance invalide : sentinelle255. Après
qualification complète seulement, le moteur écrit un artefact distinct
`qualification-adoption-*.json` et peut publier `refset_replay_maxdiff=0`.
Chaque nouvelle exécution revérifie les pièces ; le fichier d'adoption seul ne
donne aucun crédit. Le marqueur v2 et les références historiques ne sont pas modifiés.
Les compteurs de couverture déjà existants décrivent le lot courant ; les nouveaux
compteurs `refset_qualification_*` décrivent la qualification agrégée.

La voie est x86 : aucun résultat Android, aucune validation owner et aucune
correction du tonemap HDR/SDR ne se déduisent de ces reçus.
