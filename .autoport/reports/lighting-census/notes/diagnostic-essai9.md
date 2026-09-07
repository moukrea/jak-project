# Diagnostic borné — essai 9
DIRECTIVES v6fca51fe40

## Écarts : localisation nouvelle, cause non démontrée
Comparaison numérique avec le chargeur existant `tools/refset_compare.py`, sans inspection
visuelle : `ecarts-legacy-essai9.txt` détaille les 24 PNG archivés avant cette preuve.
Tous leurs pixels différents restent dans x285..315 / y13..72 sur 320×180.
ORIGINE/h00 = maxdiff202, diffpx794, bbox287,13,314,72 ;
ORIGINE-LUMIÈRE/h00 =200/716 ; RECHARGED/h09 =158/105.
Ce constat localise la différence ; il ne nomme pas l'objet dessiné.

Les positions HUD habituelles ne s'apparient pas directement à cette région :
`hud-classes.gc:608–609,636` (orbe x399/512), `:982–983` (cellule x256),
`hud-classes-pc.gc:1336–1343` (mouche x60,y380). FPS coupé sous refset (`pckernel.gc:738`).
Les trois mayorgears de `refset-capture.log:8966–8968` sont incompatibles avec le cadre
au cap163 publié par `REFSET pose` : centres projetés x808..840 au FOV64 initial.
Ce calcul dépend du FOV effectif, non journalisé ; ce n'est pas une attribution de pixels.

Piste restante : `hutlamp`, chargé capture.log:1795 et HDSKINMODEL:4811.
`village-obs.gc:765–766` initialise cyclegen.output avec rand-vu à sa naissance ;
`:755–756` oscille ensuite le joint3 selon cette horloge, période900.
Le réancrage refset dans hud-classes-pc.gc:1763 ne réinitialise que les particules.
Une phase née avant le reseed peut donc persister ; sa responsabilité pour la région
mesurée reste une hypothèse. Aucune position hutlamp trouvée dans les logs audités.
Ne pas réinitialiser arbitrairement cet objet ni recapturer les origines sur cette hypothèse.

## Compatibilité temporelle et identité
Capture historique : 564 étapes ; plan courant :672. Les ajouts intermédiaires décalent
les vues suivantes, tandis que les horloges vent/herbe emploient la frame logique absolue
(foliage_wind.cpp:244 ; GrassRenderer.cpp:1450). Même nom PNG ne garantit pas même instant.
Ce défaut n'explique pas les différences des premiers créneaux legacy.
Les lectures current_logic_frame depuis le renderer restent une piste distincte, non mesurée.

Correction livrée : census_config_fingerprint inclut les flags et valeurs des surcharges
de caméra, champ par champ, sans padding ni état dynamique. La couverture refusait déjà les
caméras de calibrage : ce changement complète l'identité, il ne suffit pas à corriger la porte.
Le README refset est corrigé : ancien plan, recapture destructive documentée à tort,
confusion entre drapeau sky et visibilité, et anciennes assurances de déterminisme retirées.

## Ciel et niveaux : limites conservées
Le champ sky propre à sunkenb est confirmé dans level-info.gc:903.
sky-tng.gc:901 appartient à make-sky-textures, pas sky-draw : il prépare une contribution
au ciel global sous conditions de poids, activité et adgifs. Des textures vil1-sky sont
présentes dans sunkenb-vis-alpha ; ce partage ne prouve pas un drapeau inutile.
Capture historique : 8 manques sunkenb à0‰ (refset-capture.log:1233165).
Le changement de niveau à l'émersion du palais empêche d'attribuer la vue village2 à sunkenb.
Aucun nouveau cadrage justifié. Aucun retrait de la liste ni changement des seuils.
L'index22 est intro ; halfpipe a des données mais pas de DGO livré trouvé. 22e jouable inconnu.

## Validation bornée
Build incrémental et une seule preuve150s confiés au tester, avec le diagnostic existant
OG_GECHO_MERC=1. Les résultats sont dans tests-essai9.md et proof.txt du runner.
Aucun generic.sh lancé par le worker, aucune ablation/capture/tournée supplémentaire,
aucun appareil touché. Le détail des preuves non obtenues est dans report.txt et handoff.md.
