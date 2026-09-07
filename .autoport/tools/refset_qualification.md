# Qualification des deux bras d’éclairage

DIRECTIVES v6fca51fe40

Le contrat actif compare la refonte lighting ON (phase2, HDR tonemappé SDR)
à lighting OFF (phase3, éclairage par défaut) dans le même build. Recharged
reste ON dès le démarrage. Textures, modèles HD, herbe, brise et autres options
hors éclairage restent identiques. Les noms de répertoires acquis restent
`recharged` et `origine-lumiere`. La phase1/master OFF et la baseline historique
ne sont plus admissibles à la qualification de cette priorité.
Les anciens fichiers restent archivés, sans crédit pour ce contrat ; copie du
contrat précédent : `reports/lighting-census/notes/essai39-lighting-pair/historical-not-validated/`.

## Entrées et recette

Sceller une seule fois après le build incrémental :
`python3 .autoport/tools/refset_provenance.py seal --root "$PWD" --role candidate --output /chemin/source.json`.
Le certificat lie les sources et le binaire disponibles ; il ne démontre pas
une compilation reproductible. Les outils baseline sont conservés pour archives.

Utiliser `refset_campaign.py` (documentation `refset_campaign.md`) avec deux
recettes mono-phase `OG_REFSET_PHASES=2` puis `=3`. Chaque bras est capturé une
fois puis rejoué une fois. Garder les mêmes vue, heures, bootstrap, pad replay,
réglages, données et calendrier de chargement. Une séquence `2,3` dans le même
processus ne démontre pas un état ON/OFF identique à la même frame.

Les recettes essai39 dans `reports/lighting-census/notes/essai39-lighting-pair/final/`
partent de village1-out aux huit heures, bootstrap essai17 déjà acquis et
`OG_REFSET_LOAD_SETTLE=1200`. `OG_RECHARGED=1`, `OG_HDR=1`,
`OG_REFSET_QUALIFY_STATE=1` et `OG_REFSET_REQUIRE_LOADED=1` sont communs.
`OG_HDR=1` reste composé avec le maître lighting : le bras OFF doit rester LDR.
Les références sont réservées dans une nouvelle racine par capture ; ne jamais
copier les images entre racines. `--off` désarme le recensement, ce n’est pas
le bras lighting OFF.

## Qualification produite par le moteur

Le manifeste contient uniquement des chemins :

```json
{"version":2,"roots":["/racine/capture-on","/racine/capture-off"]}
```

Chaque capture écrit `qualification-capture.json` ; chaque rejeu écrit un reçu
neuf dans `qualification-replays/`. Un seul rejeu exact par racine suffit ; tous
les échecs présents sont relus. Reprendre un succès ne crée pas une exécution.
Les états reconstruits, sidecars, ressources consommées et sources restent liés
aux reçus et sont contrôlés par le producteur. Le témoin postdispatch couvre RNG,
horloges, acteurs observés, réglages PC et caméra ; il n’est pas un snapshot
exhaustif des variables privées et coroutines de tous les acteurs.

Chaque paire vue/heure exige la même identité de build/données/entrées/réglages/
bootstrap, les mêmes frames et les mêmes octets d’état observé. Les options
`effective_options` sont lues au readback et comparées au rejeu : master ON,
lighting/temps réel/HDR selon le bras, autres réglages identiques entre bras.
Le schéma effectif porte exactement `master`, `lighting`, `rt_light`, `hdr`
et `others` ; `hdr` compose l’activation de chaîne et son format flottant.
Les ensembles de ressources consommées ON/OFF sont également exigés identiques ;
les noms des snapshots et checkpoints restent libres. Une invalidité de qualification
reste 255 dans la porte globale, même si la couverture est partielle.
L’égalité d’images porte uniquement sur la capture et le rejeu du MÊME bras.
Aucune égalité d’image n’est exigée entre lighting ON et OFF.

La couverture agrégée reste 448 cas : 28 vues × 2 bras × 8 heures, 21 niveaux,
au moins quatre intérieurs, ciel 150..900‰ pour chaque niveau à ciel/bras/heure.
Sunkenb reste exigé. Un manque produit `incomplete`/254 et sa liste ; une pièce
invalide produit 255. Seule une qualification complète produit une adoption et
permet `refset_replay_maxdiff=0`. Un lot partiel exact garde la mesure distincte
`refset_replay_run_maxdiff=0` sans fermer la priorité.

Seul `lib/proof_run.sh` écrit `proof.txt`. Le validateur générique reste inchangé
et l’orchestrateur le lance. Ni ces reçus x86 ni leurs tests ne valident la qualité
HDR, Android ou le jugement de l’owner sur les blancs, teintes et hautes lumières.
