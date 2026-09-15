# soft_bake : baseline hors ligne (schéma 1)

DIRECTIVES v1707e53cb2

```sh
./tools/soft_bake/soft_bake --census
# Analyse ciblée, sans écraser la baseline complète :
./tools/soft_bake/soft_bake --census --level snow --out chemin/snow.json
```

Le wrapper compile seulement `main.cpp` contre le `libcommon` de l'arbre `build`
existant, avec les mêmes includes et defines que `mesh_audit`, puis
`-ffp-contract=off`. Aucune reconfiguration CMake. Les entrées sont triées ; le
calcul est monothread, sans hasard ni horloge. Les 25 fichiers de niveau sont
recensés ; `GAME.fr3` contient les assets globaux et est exclu. Les 64 matériaux
sont publiés, y compris ceux à zéro. Les triangles de collision sont les triplets
du flux `CollisionMesh.vertices`, `pat-material = (pat >> 6) & 63` ; leur aire
3D est la demi-norme du produit vectoriel, calculée en double. Conversion :
4096 unités par mètre, 16777216 unités² par mètre².

Le processus de décodage épingle `OG_MESH_WELD=0` : aucun index ne peut être
repointé vers un sommet d’une autre instance par la soudure runtime.

Le SHA-256 de chaque `.fr3` est calculé avant ET après son analyse ; une entrée
modifiée pendant le calcul interrompt la publication. `baseline.json` et
`baseline_json.h` sont chacun publiés par renommage atomique. Le hash inclus
dans le header identifie les octets exacts du JSON, permettant de détecter une
interruption entre les deux renommages. Le header est le snapshot embarqué :
une nouvelle baseline demande seulement de recompiler son consommateur C++, puis
de relier/reconditionner le binaire. Elle ne demande aucune copie d'ISO.

## Congères : attribution conservatrice, pas de correspondance inventée

Les composantes deepsnow sont connectées par positions de sommets exactes. Leur
ordre suit celui des triangles du `.fr3`. Géométrie TIE 0 uniquement : les autres
arbres sont des LOD alternatifs. Le dépaquetage officiel donne les positions
monde, `matrix_groups` donne le numéro de matrice de chaque sommet et chaque
`vis_group.tie_proto_idx` fournit le prototype. Le flux d'indices est décodé
avec les redémarrages et la parité des strips. Les triangles d'instance qui
mélangent plusieurs matrices ne sont pas pris pour une instance.

Un rayon vertical bidirectionnel passe par le **centroïde de chaque triangle
de collision**. Pour chaque instance, on retient l'intersection verticale la
plus proche en valeur absolue à moins de 10 m, toutes faces rendues confondues.
Le signe est `y_rendu - y_collision` : une valeur négative reste négative.
Aucune liste de noms supposés neige n'intervient. Les candidats qui couvrent au
moins la moitié des centroïdes sont conservés et triés par couverture, puis RMS
des distances. Une instance est attribuée si elle est seule, ou si sa couverture
est strictement meilleure ET son RMS inférieur au second candidat, ou, à
couverture égale, si son RMS est au moins deux fois meilleur avec une marge
supérieure à 5 cm. Cette règle géométrique est une attribution inférée,
reproductible, non un lien de provenance sérialisé. Les candidats secondaires,
la marge RMS et les absences (`absent_surface_samples`) restent publiés ; une
absence de surface n'est pas assimilée à un échec d'attribution. Les cas sans
dominance restent en gap. Les valeurs négatives restent des résultats mesurés.

`vertical_gap` publie min/médiane/max (et moyenne) des **échantillons**, en unités
et mètres. Ce ne sont pas les extrema continus de la différence entre deux
surfaces triangulées. La médiane paire est la moyenne des deux valeurs
centrales. `matched_samples` et `samples` exposent la couverture sans masquer
les manques. Les candidates ne représentent pas une preuve du prototype source
de collision : ce lien n'est pas sérialisé dans le `.fr3`.

## Densité : domaine précis

La géométrie tfrag 0 est mesurée avant soudure/subdivision runtime. La sélection
baseline utilise les noms de textures contenant `snow`, `sand` ou `beach`,
`abs(ny) >= 0.7`, puis le support collision le plus proche verticalement à moins
de 0,5 m du centroïde, de matériau sand ou snow, hors mode MUR. Les trois arêtes
de chaque triangle retenu sont comptées : une arête partagée compte deux fois.
Le JSON donne le nombre de candidats et de centroïdes sans support. Il s'agit
d'une sélection baseline reproductible, pas de la classification finale des
coques (profils de pente, faces retournées et exclusion eau de `soft-bake`).
Les compteurs de sommets/triangles réellement dessinés appartiennent au runtime.

## Limites de fermeture

Les gaps d'attribution sont déduits des tables et restent non nuls si les
projections manquent ou se superposent. La présence de statistiques n'efface pas
ces gaps. La décision d'épaisseur doit tenir compte des échantillons absents,
des valeurs négatives et de l'absence d'extrema continus. Aucun fichier de
preuve du harnais n'est écrit par cet outil.

## Mesure en jeu et comparaison des deux cibles

Le census runtime est activé uniquement pour l'item `soft-baseline` armé.
Il compte les références de sommets soumises (hors restart), et les triangles
à trois indices distincts, par système et image, après culling, multipasses
comprises. Ce ne sont ni les sommets uniques ni les exécutions de vertex shader.
Les compteurs couvrent la géométrie du moteur Jak1 ; ImGui tiers est hors scope.
Les deux sites hfrag Jak3 publient un manque au lieu de prétendre être comptés.
Les durées CPU du comptage et de publication sont exposées séparément.

Le banc utilise de vraies textures R16 UNORM et un FBO privé : 16 uploads et
16 quads par taille (64², 128²), chaque opération attendue par `glFinish`.
Le temps publié inclut la soumission CPU et l'attente de completion ; il n'est
pas un temps GPU isolé. Pas de remplacement par R16F si R16 est indisponible.
La complétude FBO et les erreurs GL sont vérifiées ; aucun readback ne mesure
le contenu du texel. Les bindings et états modifiés sont restaurés.

La course x86 du producteur officiel est conservée dans les notes, puis :

```sh
python3 tools/soft_bake/collect_tiles.py .autoport/reports/soft-baseline/notes/x86-proof.txt
```

Ce collecteur vérifie cible, absence de crash, empreinte du binaire, tailles
et mesures positives. Il écrit `data/soft-baseline/x86_tiles.json` et son header,
avec l'empreinte de la course et du code du banc. Le build Android suivant
embarque cette mesure x86 ; sa course USB publie les valeurs côte à côte.
La course x86 seule laisse volontairement le terme des deux cibles non nul.
Ni le collecteur ni l'outil hors ligne n'écrivent de fichier de preuve.

Test CPU des compteurs (utilise le vrai publicateur, aucun contexte GL) :

```sh
c++ -std=c++17 -O2 -DFMT_HEADER_ONLY -I. -Ithird-party/fmt/include \
  tools/soft_bake/test_draw_census.cpp \
  game/graphics/opengl_renderer/soft_draw_census.cpp game/system/autoport_proof.cpp \
  -pthread -o build/test_draw_census
AUTOPORT_FEATURE=soft-baseline AUTOPORT_FEATURE_ARMED=1 build/test_draw_census
AUTOPORT_FEATURE=soft-baseline AUTOPORT_FEATURE_ARMED=0 build/test_draw_census
```

La frontière d'erreurs GL précède le premier appel du banc : chaque erreur
antérieure est conservée sous `soft_tile_prior_gl_error_<n>`. Au plus 16 lectures
cherchent `GL_NO_ERROR` ; sans file vide, aucune mesure n'est autorisée. Une erreur
antérieure ne devient pas une erreur R16 ; une erreur des appels privés reste
bloquante. Le coût du census complet est publié et peut dépasser le plafond
200 µs de la SPEC : ce plafond n'est donc pas revendiqué par cette baseline.

`soft_draw_frame_snapshot` est la ligne de référence pour comparer les systèmes
d'une même image : `frame;system:draws,vertex_references,triangles,unmeasured_draws`.
La valeur complète est publiée sous un seul verrou. Les clés scalaires restent
utiles individuellement ; un flush concurrent du fil GOAL peut les observer
entre deux écritures, donc leur regroupement ne remplace pas cette ligne.
