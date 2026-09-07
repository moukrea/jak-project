# Handoff — lighting-census, essai 17
DIRECTIVES v6fca51fe40
## ÉTABLI
- gk1e505342c58a9875 build incrémental rc0 ; garde npc-flicker47 ; proof60s crash0 frames3294.
- OG_BOOT_REPLAY_BOUNDARY=actors-sweep + OG_BOOT_REPLAY_CONTINUE=village1-hut :5880records scellés79fb964dc17507ec capture/replay.
- Dispatch10/PID12 ;178entity-links,51processus présents,294aid ; types/états nommés, aucun pointeur restauré.
- Rejoués1115disponibilités RPC,970décisions login,44paquets pad,39EE-timer ; RPC prêt attend la vraie donnée avant retour.
- Flux notes/essai17-rpc/fork-bootstrap.bin ; session OS neuve + options ci-dessus + OG_BOOT_REPLAY_REPLAY=<flux>.
- Checkpoint voit village1 active, beach loading : aucune garantie sur acteurs/chargements après cette frontière.
- legacy/origine/h00 compared1 maxdiff195 diffpx57581 flaky254 census_replay_runs0 ;575SHA historiques avant/après OK.
- Draws1685650 stock/classifiés0 résiduel0 rb_mismatch0 GPU9,3062ms ; data56f0364a8789c816 config6ab6da1dcc8defb1.
## TENTÉ
- Première frontière atteinte dispatch8/577records exacts mais target-title : preuve archivée essai17-title, pas qualification village.
- Continue fixé AVANT initialize!/restart/start ; village capturé4376records mais rejeu échoue2255 goal-slice-slot.
- Cause dépendance chargement async ; wrapper GOAL rpc-busy? corrige ce rejeu sans stub, poll1ms/borne5s, natif inchangé.
- Test parser rc0 ; aucun GOAL/renderer/HDR modifié, aucun candidat adopté, aucune sentinelle retirée.
- Pristine c4bc4d3ff4691902ff023319cb33df71c0040501 / gk615f120e4e0de8f6 inchangé ; pas de nouveau run avec ses CGO distincts.
## RESTE
- Ne plus reporter seulement bootstrap au pristine : ABI réelle des CGO livrés à résoudre (audit141exports absents,117référencés PC).
- Pristine sans actors-sweep-complete : observer retour ORIGINAL méthode15 level-group, sans second appel ni modification ND ; compteur frame/pad à adapter.
- Finir provenance effective (octets ouverts/textures/obj loose), état après chargement des niveaux requis et qualification origine indépendante.
- Implémenter producteur/consommateur qualification v2 : refset.cpp1680 manque baseline/état ;1919 v1seul ;1980 sentinelle254 légitime.
- Candidat distinct complet trois modes/21niveaux/8heures/≥4intérieurs ; Sunkenb+ciel manquants ; cinq rejeux exacts après qualification.
- non prouvé : images/couverture/qualification/HDR/SDR/Android. Aucun rendu HDR corrigé, aucun appareil ni owner-ok.
- Notes recovery-essai17.md et run-rpc-essai17.sh ; flux/entrées/traces essai17-rpc ; generic orchestrateur seul.
