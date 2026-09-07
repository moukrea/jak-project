# Lots REFSET x86

DIRECTIVES v6fca51fe40

`refset_campaign.py` conserve les tentatives et permet leur reprise. Il appelle exclusivement
`.autoport/lib/proof_run.sh lighting-census x86 --timeout N` depuis le worktree demandé.
`--proof-run /chemin/main/.autoport/lib/proof_run.sh` sélectionne un producteur
partagé existant pour un arbre historique ; le défaut reste celui du worktree.
Son chemin absolu et son SHA256 participent à l’identité. Le cwd, les données et
la sélection/restauration du backlog restent ceux de `--root`.
Il ne compile rien, ne lance aucun démon, ne touche aucun appareil et ne modifie aucun
validateur. Les reçus sont des données de suivi : **le runner ne certifie rien**. Le
producteur moteur reste responsable de l'agrégation, des témoins et de la qualification.
Aucune référence n'est copiée/assemblée pour fabriquer une racine qualifiée.

```sh
python3 .autoport/tools/refset_campaign.py run \
  --campaign /chemin/campagne --name lighting-on-capture --root /chemin/worktree \
  --env-json /chemin/capture.json --timeout 90 \
  --data /chemin/overlay --input /chemin/autre-entree
python3 .autoport/tools/refset_campaign.py status --campaign /chemin/campagne
```

`--timeout` accepte 1 à 300 secondes. L'attente de build de proof_run est bornée à
60 secondes ; le garde externe ajoute 90 secondes au timeout demandé. `status` est
strictement en lecture seule, même si la campagne n'existe pas.

Le JSON est un dictionnaire de chaînes `OG_*`, par exemple :

```json
{"OG_REFSET":"capture","OG_REFSET_VANTAGES":"legacy","OG_REFSET_PHASES":"2","OG_RECHARGED":"1","OG_REFSET_HOURS":"0","OG_PAD_REPLAY_REPLAY":".autoport/refset/neutral.inputs"}
```

Pour rejouer, fournir `OG_REFSET=replay` et `OG_REFSET_DIR` pointant vers une racine
existante. En capture, le runner remplace `OG_REFSET_DIR` par `attempt-.../captures`,
qui n'existe pas avant le lancement. Il alloue aussi `OG_REFSET_ASSET_MANIFEST`,
`OG_PAD_REPLAY_TRACE` et un UUID `OG_REFSET_RUN_ID` neufs. Ces sorties ne participent
pas à l'identité de reprise ; la racine de référence replay, elle, y participe.
Les autres variables du `proof_env` de lighting-census sont conservées. Les `OG_*`
ambiants sont retirés de l'environnement enfant pour éviter des paramètres cachés.

La sélection runtime du backlog est indispensable : proof_run réapplique son
`proof_env` après l'environnement du processus. Sous le verrou natif de backlog,
le runner sauvegarde avant/durant et ne change que ce champ de lighting-census.
Il le restaure par comparaison exacte, en conservant les autres champs/items. Une
écriture concurrente du même champ provoque un refus de restauration explicite dans
le reçu. SIGINT/SIGTERM arrêtent le groupe du seul processus lancé et restaurent la
sélection ; SIGKILL/panne machine ne permettent pas de cleanup. Dans ce dernier cas,
le reçu `prepared`/`running` et `proof-env-selection.json` restent pour diagnostic ;
aucune récupération aveugle du backlog n'est faite.

Deux `flock` exclusifs non bloquants (campagne et worktree) sérialisent les runners.
Ces verrous ne coordonnent pas les appels directs à proof_run, ni les modifications
externes des fichiers. Aucun appel direct concurrent ne doit utiliser les sorties
lighting-census du même worktree. Les empreintes avant/après détectent un changement
persistant d'entrée, pas une mutation temporaire remise exactement à son état initial.

Chaque tentative possède un répertoire neuf, un reçu atomique de progression, le
log du wrapper, les copies **inchangées** de la preuve originale et du log moteur
s'ils sont nouveaux. Aucune ligne de preuve ou porte n'est produite par le runner.
Une preuve doit porter un started_at nouveau et le SHA tronqué du binaire mesuré.
Les SHA256 couvrent le binaire, `game/{graphics,kernel,system}`, `game/main.cpp`, `common` (shaders et bootstrap inclus), scripts du runner,
`out/jak1/{iso,fr3}`, `build/game/{assets,custom_assets}`, les settings portables,
bootstrap/pad replay, manifest de qualification, `OG_REFSET_BUILD_PROVENANCE` et chaque `--data`/`--input`.
Ces options sont répétables et **sélectionnent les fichiers à empreinter**, sans
changer les arguments moteur. Ajouter tous les overlays/racines externes réellement
sélectionnables : le runner ne déduit pas les routes externes du moteur, et n'invente
aucune variable d'overlay. Une entrée absente est représentée explicitement par null.
Les choix graphiques de l'hôte sélectionnés sont enregistrés ; ni pilote installé
ni GPU ni contenu de toute variable non OG ne sont certifiés.

Une reprise ne regarde que la dernière tentative du même nom. Elle exige identité
avant/après identique, exit zéro, restauration réussie et run complet : unique
`REFSET done`, steps positifs, captures/compares conformes, crash zéro, frames
positives, provenance_bad zéro ; replay exige maxdiff/diffpx zéro et `refset_replay_run_maxdiff=0` (le compteur global peut rester à 254 pour un lot partiel avant adoption), aucune référence
manquante/invalide. PNG et sidecars doivent exister ; tous les artefacts archivés et
références doivent garder leurs empreintes. Seuls `*.png`, `*.provenance.txt`, `*.state.bin`, `captured-by.txt`,
`refset-format.txt` et `qualification-capture.json` participent aux empreintes de
référence, ainsi que le snapshot immuable `assets_path` nommé dans le reçu capture.
Le snapshot du seul replay courant est hashé séparément et archivé avec son reçu ;
les nouveaux snapshots des autres replays ne changent pas les inputs. `assets_path`
doit être absolu et `assets_fp` doit correspondre au hash producteur du fichier.
Ledgers, adoption et reçus des autres replays sont des sorties producteur
conservées intégralement, exclues de cette identité. Le JSON de l’UUID propre au run
est empreinté séparément et archivé. Avec `OG_REFSET_QUALIFY_STATE=1`, le reçu doit
aussi être présent, clean/reconstructed, avec zéro état invalide et son capture_fp
égal au hash producteur du véritable qualification-capture.json. Ce contrôle de
reprise ne remplace pas l’adoption du producteur, qui relit tous les échecs. Un nom distinct par capture/rejeu et bras identifie chaque processus : une reprise
ne crée jamais un nouveau run. Le contrat courant exige un rejeu par racine. Un échec reste au
registre, et empêche de reprendre silencieusement un succès plus ancien du même nom.

Tests isolés, producteur factice uniquement en répertoires temporaires :

```sh
python3 -m unittest discover -s .autoport/tests/tools -p test_refset_campaign.py -v
```

Le contrat actif est décrit dans `refset_qualification.md` : deux racines mono-phase
2/3 du même build, master ON constant. `--proof-run` pour arbre historique reste
une capacité archivée, sans crédit pour cette priorité. Aucune tournée automatique
ni cinq rejeux par racine ne sont nécessaires pour commencer la première paire.
