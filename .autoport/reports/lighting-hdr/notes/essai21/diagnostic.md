DIRECTIVES vb7966a3839
# Essai 21 — diagnostic et décisions

## Lecture HDR
Dans le lot ancien 20260908T024828-3604150, engine.log:54522 rapporte A42 err=0 et px=00000000 ; la ligne 54523 refuse la sonde suivante avec GL1282. Les six refus présentent cette même succession. Le glGetError A42 précédait sa lecture GL_RGBA/GL_UNSIGNED_BYTE, inadaptée à la scène flottante.
Le correctif TFragment.cpp choisit le type à partir de l’attachment réellement dessiné : GL_FLOAT sans clamp pour le HDR, octet pour le normalisé. Il restaure READ_FRAMEBUFFER et son choix de buffer. Aucune erreur après lecture n’est consommée ; une tentative non mesurée reste explicitement signalée.
Lot neuf 20260908T031039-3623650 : 32 captures, 32 sondes, 16 paires qualifiées ; readback-check.json compte 21 traces A42 dont 13 lectures float, zéro erreur A42 préexistante et zéro refus before-probe.
Build incrémental : un objet TFragment et édition de liens, puis repack sans compilation GOAL/NDK supplémentaire (build-deploy.log). Bibliothèque déployée SHA256 ec1726c1202f3983a2ed0d6ff06da360efdee6a70f6b5088f34a088264804721, MD5 build/APK/Redmi e9611463df5d877d04d428061a9e92d3.
Le nouvel exécutable invalide la provenance binaire stricte des anciennes paires. Aucune compatibilité inter-binaire n’est supposée : nouvelle campagne essai21-readback ; anciennes sources et binaires conservés pour diagnostic.

## Remplacements de vues
Swamp : conserver la position native swamp-start et orienter la caméra 60:0:50:25 ; want.levels=swamp,village2, want.display=swamp,display. Le lot ancien 20260908T030348-3616431 puis le lot courant 20260908T032102-3631467 mesurent chacun 185‰ de ciel aux huit heures, huit paires qualifiées. Les arrivées déplacées dock/cave1 ayant crashé ne sont pas corrigées ; leur couverture est assurée par cette vue de remplacement autorisée.
Sunkenb : amorçage sunkenb-helix, puis caméra sunkenb-start:-8:90:0:2700 au-dessus de la surface. Le lot 20260908T031529-3628144 mesure 303–304‰ de ciel aux huit heures et conserve l’intérieur helix : 16 paires qualifiées. La candidate précédente à +160 m donnait zéro ciel malgré des captures colorées.
La première tentative surface 20260908T031349-3626217 a produit SIG11 fault=0xfffffffffffffc à la frame 109, avant warp=300 ; collecte officielle en 20 s. Le retry qualifié remplace explicitement chaque demande de ce lot et du lot 031039, sans retirer leurs sources.
Les mappings et réglages exacts sont enregistrés dans les manifestes proof_run et campaign-runs.jsonl. Aucun manifeste ni champ de preuve n’est écrit manuellement.

## Couverture et délai Ogre
Recapture des vues compatibles connues : recapture-status.json contient les commandes et résultats de 21 processus. Les vingt premiers lots sont complets ; aucun retry de ces lots.
Le lot Ogre 20260908T035142-3669416 atteint seulement 540 frames dans la limite erronée de 160 s, sans crash ni paire. Le lot historique qualifié 20260908T021549-3571369 avait pris 359 s avec les mêmes réglages et le même passage lent (environ 724 ms/image aux frames 480–540). Ce délai était déjà présent avant le correctif.
Reprise ciblée Ogre : limite 450 s, aucune modification de rendu/cadence, huit remplacements explicites du lot incomplet. Commande et résultat dans ogre-repair.json.
Courbe Fidélité 0, exposition 1 et genou 0,95 conservés. Le bilan quantitatif équilibré final et les pires résidus sont consignés dans quality-review.md ; aucun jugement artistique déduit des mesures.

## Incidents de conduite
Le premier lanceur a posé son verrou de déploiement avant proof_run, provoquant une attente interne de 30 s ; son propre verrou a été retiré avant mesure. Aucun verrou nu conservé.
La première syntaxe want.levels=swamp a été refusée (need-two-levels), puis corrigée en swamp,village2 avant le lot qualifié.
Aucun validateur, owner-ok ou backlog modifié par ce worker. Les agents researcher, implementer et tester ont terminé ; aucune sous-session Claude.
