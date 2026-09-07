# Handoff — lighting-census, essai 30
DIRECTIVES v6fca51fe40
## ÉTABLI
- Baseline x86 CONSTRUITE : /home/emeric/code/jak-lighting-baseline, source a9ea15a69062a57335278db7680cd647df3c1e1d.
- gk baseline41dfc6d8185a8433 ; candidat27a30abe4f7ccc99 ; gk seuls, PNJ47 PASS, aucun Android/appareil.
- Patch COMPLET31fichiers : notes/essai30-baseline/full-baseline.patch ; applique au commit ci-dessus, pas à HEAD.
- Renderer historique adapté seulement ABI/protocole/mesures ; shaders historiques INTACTS ; data-root build/game/data -> ../.. local.
- Dix exports Jak1 + DEUX communs réels (baseline_pc_compat.*) ; pas de stubs, cadence historique non modifiée.
- Copies CoW indépendantes ISO/FR3/obj/custom_assets/managed_assets/config ; prepare-data.sh et data-snapshot.log.
- Deux bras corrected : bootstrap5880/79fb964dc17507ec, dispatch10/PID12 ; aucune recapture du bootstrap17.
- Guard opt-in OG_REFSET_REQUIRE_LOADED=1 : snapshots après scellement17, fenêtre8, échéance fixe, pas de capture non prête.
- Deux refus IDENTIQUES captureLF2282/snapshot2282 : beach=loaded(need active), captured0 ; sortie1 propre sans SIGSEGV.
- Baseline2392frames/46s ; candidat2405frames/47s ; proof_run actuel produit les proofs dans chaque worktree.
- Ensembles finaux :4FR3/486objets/787textures identiques ; ISO756vs755 (EXINTRODSTR offset49152 taille49152 en plus baseline).
- Shaders106vs108,95communs ; aucun checkpoint capture : ensembles finaux NE prouvent PAS les mêmes données d’une frame.
- 575SHA historiques préservés, zéro nouveau prélèvement ; v2 toujours missing-state-and-baseline, gate non obtenue.
## TENTÉ
- Premier core baseline : CALL symbole NULL pc-get-frame-rate-cap-override ; pc-set-uncap-menu manquait aussi (registre COMMON).
- Fournisseurs réels ajoutés, puis bootstrap17 exécuté ; aucun besoin de refaire audit FR3/export Jak1/bootstrap.
- Première échéance1501 précédait WANT-DISPLAY1800 : LOAD_SETTLE1200 fixe désormais échéance2101, après activation beach.
- Traces corrected : beach loading→loaded→active après WANT-DISPLAY→loaded après DERNIER rewarp ; refusLF2282.
- Core candidat initial : exit() GOAL détruisait statiques pendant GL ; _Exit(EXIT_FAILURE)+flush corrigé, refus propre retesté.
- Runs initiaux et corrected préservés ; pas de troisième campagne ni comparaison vide donnant faux zéro.
## RESTE
- Rétablir les demandes de niveaux/display APRÈS dernier rewarp (start play remet beach loaded), puis qualifier à frame fixe.
- Utiliser les binaires/builds EXISTANTS incrémentalement ; run-arm.sh <worktree> <baseline|candidate> <cycle-neuf> réserve sorties.
- Le script sélectionne/restaure proof_env sous lock ; builder2541075 vérifié idle, suspendu/repris par trap ; aucun démon lancé.
- Attester/comparer état acteurs/RNG/config effectifs postload ; comparer provenance consommée par cas, shaders séparés.
- Seulement ensuite nouvelles références qualifiées3modes/21niveaux/8heures/≥4intérieurs/ciel≥15%, puis5rejeux exacts.
- Les21niveaux, dont Sunkenb, restent non comparés ; voir report.txt/proof.txt. Aucun HDR/SDR/Android/owner-ok prouvé.
