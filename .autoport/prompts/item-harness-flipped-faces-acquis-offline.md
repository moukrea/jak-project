# Le garde-fou des faces a l'envers relit les assets hors ligne, et le moteur ne porte plus d'instrumentation de ce sujet

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de lighting-flipped-faces-everywhere, non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
(1) `.autoport/acquis/flipped-faces.sh` s'appuie sur l'instrumentation MOTEUR (flip_census) : CONFLIT avec l'ordre de l'owner du 25/09 (« Pourquoi le moteur devrait porter le truc des flipped faces defects si c'est un truc qu'on fait sur les assets ») ; (2) `game/graphics/opengl_renderer/flip_census.cpp` + `floor_probe.cpp` restent compiles dans gk ; (3) `.autoport/acquis/_lib.sh:62-73` (acq_x86_log) cache une garde x86 sur le sha de gk + arguments, jamais sur les DONNEES chargees (fr3/*.meshweld, pack) : apres une recuisson, la garde rend un resultat perime.

## Livrable
1. acquis/flipped-faces.sh relit les fichiers corriges du pack HORS LIGNE (tools/mesh_audit --check-orient) + grep des shaders ; plus aucune course du jeu.
2. Retirer flip_census.cpp / floor_probe.cpp de gk (et des deux CMakeLists) si plus rien ne les lit.
3. Le cache des gardes x86 inclut l'empreinte des donnees chargees.
4. `flipped_acquis_leftovers` ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`flipped_acquis_leftovers == 0` dans `reports/harness-flipped-faces-acquis-offline/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-flipped-faces-acquis-offline x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
