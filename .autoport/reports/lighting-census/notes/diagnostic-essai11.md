# Diagnostic — essai 11
DIRECTIVES v6fca51fe40

## Corrections livrées

Le diagnostic ROI existant distingue maintenant changements RGB, changements alpha
et changements alpha seulement. Il conserve le nombre RGBA antérieur, les indices
de draw/texture, et ajoute bbox RGB, amplitude RGB et hashes RGB avant/après.
Les unités séparent RGBA8 et float HDR ; aucune tolérance ou modification de pixel.

Le producteur de références écrit les sidecars des futurs suppléments après le
roundtrip PNG réussi. Les sept champs sont version, case, config, bin, flavour,
png et capture_lf. Le rejeu vérifie les champs, leur unicité, les nombres complets,
le témoin du suffixe, le hash PNG et la frame enregistrée avant créditer la comparaison.
Une erreur interdit le crédit et le registre ; les sentinelles restent non nulles.
Le hash du registre inclut les sidecars et témoins du suffixe ; les historiques
gardent leurs chemins et calcul d'empreinte. hash_file refuse les erreurs de lecture.

Les 108 chemins supplémentaires sont tous absents de .autoport/refset/supplement-v1.
Ce correctif prépare leur production ; il n'en adopte ou fabrique aucun.
La frame enregistrée décrit l'agenda, pas une sauvegarde/restauration d'acteurs.
Les sidecars ne portent pas les empreintes CGO/DGO/FR3 du producteur ; leur provenance
ne suffit donc pas à établir l'identité complète de l'état ou des données historiques.

## Recherches bornées, sans nouvelle course

Les deux chercheurs natifs ont lu code, historique git et traces existantes.
Premier HDSKINMODEL hutlamp : capture historique ligne4811, essai10 ligne6076.
Les lignes HDSKINEV voisines situent les deux rendus à frame logique607 et donnent
les mêmes valeurs medres-jungle aux frames607–611 ; swaps682/683 distincts.
Cela ne mesure pas l'instant exact de naissance de la lampe ou sa phase.

La valeur b872b73f9b7e5d2e est fnv64(model->name), Merc2.cpp:3680 : un hash du NOM,
pas de géométrie, matrice ou texture. Les indices429/430/431 sont tree_tex_id,
résolus dans lev->textures ; aucun contenu historique associé n'est enregistré.
Historique ligne1795 et essai10 ligne2524 : tris128, draws3, effects1.
Les témoins historiques contiennent seulement 485f09d6c07bc24c et flavour=normal.

village-obs.gc:765–766 initialise clock.output avec rand-vu ; :727–730 accumule
inc*time-adjust-ratio en float ; :755–756 produit le quaternion du joint3.
La source ND de la lampe n'a pas changé depuis2025. Aucun delta depuis89db5b7d8a
des shaders Merc, de la sélection de ses ressources ou du réensemencement identifié.
Le reseed après start ne restaure pas les acteurs déjà nés ; le repin existant ne
restaure que les particules. Aucune phase historique n'a été retrouvée.

Le lanceur historique ne pose pas explicitement OG_LIGHTING=0 au boot, contrairement
à proof_env. Les deux traces montrent toutefois override0 avant chargement village
(capture1099/1774, essai10 187/2503), et sélection STOCK du village.
Aucune cause nouvelle n'est établie : la phase n'est qu'une hypothèse, au même titre
que les données de pose/matériau/texture non conservées.

## Vérification CPU

provenance-test-essai11.cpp inclut les vrais helpers de refset.cpp, compilés avec
sections éliminables pour éviter de lancer le jeu. Compilation et test : code0.
provenance-test-essai11.log : valid roundtrip=1 rejected=32.
Cas : champs absents/dupliqués, nombres invalides/débordement, identité de cas,
version/config/bin/flavour/PNG incohérents, frame décalée, témoin dupliqué,
sidecar absent. Le hash du registre change avec le PNG et manque sans sidecar.
Les fichiers de test sont dans un répertoire temporaire distinct, nettoyé ensuite.
Ce test ne couvre pas intégralement consume_capture ni la publication runtime.

## Limites conservées

Pas de reset arbitraire de lampe, gel d'acteur, suppression de draw, recapture,
masque ou tolérance. Les 564 historiques restent intacts.
Pas de nouvelle tournée de cadrages : sunkenb reste manquant jusqu'à attribution
de sa visibilité par son chemin de rendu, pas sur les seuls cadrages à zéro.
Non prouvé : restauration complète par cas, cinq rejeux exacts, couverture complète,
108 références établies, cause historique de divergence et qualité HDR.

## Exécution unique x86

Build incrémental code0, sha82b403292cbf2cec ; proof_run150s code0/crash0/frames8399.
La garde de build npc-flicker rapporte47 propriétés tenues. Les575 SHA des références
et les24 PNG legacy restent identiques à l'essai10 ; origine/h00=202/794, hors ROI0.
Capture1 Merc id0/1/2, first_index34395/34488/34583, slots texture429/430/431 :
RGB590/117/58, maxdiff168/128/151, alpha_only0 ; bucket52 RGB765/maxdiff168.
roi-essai11.log contient les5 lignes exactes du moteur avec hashes RGB et bboxes.
37/672 comparaisons, couverture244 manques, census_replay_runs0, maxdiff254.
Provenance_checked0 : aucun supplément atteint, le test CPU ne remplace pas ce constat.
GPU7.4360ms avec diagnostic ; GL_INVALID_OPERATION7290, non-régression GL non prouvée.
Le builder2541075, suspendu idle par PID exact avec trap, est repris Ss.
Voir tests-essai11.md pour commandes, logs et signatures ; aucun second run.
