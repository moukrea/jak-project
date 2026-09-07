# Bootstrap premier dispatch et provenance — essai 16
DIRECTIVES v6fca51fe40

## Modifications

OG_BOOT_REPLAY_BOUNDARY=first-dispatch étend le protocole existant de façon explicite.
Sans option (ou before-play), ancien ordre/format conservé. Le nouvel identifiant de
frontière est comparé dans le flux, donc entre dans son empreinte et dans la clé du registre.
Le pré-play conserve ses checkpoints puis arme le premier ListenerFunction.
Sur la pile GOAL : play(#t,#f), puis initialize!(game-info,game,#f,#f), donc continue normal.
Les deux retours sont des checkpoints vides ordonnés ; aucune valeur GOAL n'est restaurée.
Au retour du premier kernel-dispatcher, sur pile hôte avant les warps : checkpoint de frontière,
RNG GOAL/natifs, display et next-pid. Le flux est scellé uniquement après ces comparaisons.
RNG natifs : buffers 8192 et mt19937 de restauration déplacés sur le tas, octets inchangés.
Aucun fichier ND ni shader ni modèle d'éclairage modifié.

La frontière ne certifie pas les acteurs : play peut déjà appeler birth(level/bsp), et
initialize! enfile un restart ; son premier passage suspend AVANT start. next-pid n'est
qu'un compteur d'activations, pas un état ni une identité complète des acteurs.
Les horloges RTC/EE/unix sont enregistrées jusqu'à la nouvelle frontière ; les décisions
__pc-slice-expired? (steady_clock, load_gate.cpp) et disponibilités asynchrones ne le sont pas.

La provenance compose maintenant ISO base+overlay et FR3 base+custom par nom logique,
avec priorité overlay/custom. Enhanced reste exclusivement celui de base/enhanced.
Sans override l'identité historique est conservée. Les catégories obligatoires se jugent
après union ; erreurs d'accès restent zéro. C'est un inventaire de données sélectionnables,
PAS une trace des octets ouverts. Textures/obj loose demeurent hors inventaire.
Aucune sentinelle d'adoption ni de couverture supprimée ; aucune référence nouvelle adoptée.

## Qualification indépendante : obstacles précis

Pristine c4bc4d3ff4691902ff023319cb33df71c0040501 reste identifié par essai15.
Ses CGO diffèrent des CGO livrés du fork. Le fork exporte pc-refset-* appelés par ses CGO
(hud-classes-pc.gc1889), absents du pristine. Un même --proj-path permet de sélectionner
un arbre commun, mais sa compatibilité et le rendu à état égal restent à mesurer.
Le nouveau protocole n'a pas encore été reporté au pristine : refaire une course avec ses
CGO distincts ne qualifierait toujours pas les données livrées.

## Exécutions

Build initial rc1 (const Ptr, operator-> non const), corrigé ; final rc0/22,797s/5étapes.
Ninja a régénéré sa configuration automatiquement au premier build ; aucun cmake -B exécuté.
Garde npc-flicker47 ; tests CPU bootstrap rc0, fingerprint b6ede934ecf3e6a1 ; provenance18 rc0.
Binaire2ea43efcd6b1a2cdfe605d122a363b9873b0c736ab85d5e81bf96017ddd25ee9.
run-essai16.sh rc0 : capture20s (rc124 timeout), puis proof_run60s ; aucun nouveau PNG.
29 records capture/replay, même5364e1590a9215b3 ; six ee-timer aux indices14..19.
after-first-dispatch index20 ; contrôles RNG/display indices21..27, next-pid index28.
Les permanences et états d’acteurs ne sont pas enregistrés ; identité scalaire seulement.
proof.txt : crash0 frames3398 maxdiff202 diffpx794 compared1 census_runs0, historique inchangé.
Origine1402218draws stock, classifiés0, GPU8,3035ms, résiduel0, rb_mismatch0.
575SHA historiques avant/après OK ; binaire/CGO/input5SHA inchangés ; archive essai15-avant16.
Config ea73fcc511fc35e7 ; données56f0364a8789c816 inchangées sans overrides.
Builder2541075 vérifié idle, STOP/CONT par scripts longs avec traps, repris Ss.
La preuve finale ne ferme pas la porte ; generic inchangé et non lancé.

## Détails utiles pour la suite (audit, non mesurés)

Permanences game-info : pointeurs perm-list+96, task-perm-list+100 (offsets basic).
entity-perm-array : length+0, allocated-length+4, data+12 stride16.
entity-perm : status+8/2octets, task+11/1octet, aid+12/4octets. Les huit premiers octets
sont user-object pouvant contenir des pointeurs ; NE PAS copier toute la structure.
Vérifier chaque pointeur,0≤length≤allocated-length et limites EE avant lecture.
Listener : pile d’exécution32Kio ;256 correspond seulement à la sauvegarde.
Sources : all-types.gc1749,1953,9827,14377,14423 ; gkernel-h.gc51 ; gkernel.gc181..209.
Reporter les seules entrées bootstrap pertinentes au pristine, sans importer renderer ni
aucun stub masquant des exports GOAL manquants. Les ressources fork restent à qualifier.
