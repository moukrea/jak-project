# Handoff — lighting-census, essai 13
DIRECTIVES v6fca51fe40
## ÉTABLI
- Build incrémental rc0 ; gk sha256=eb489df0c9eb6060 ; garde npc-flicker47.
- Preuve unique150s : crash0 frames8510 compared37 gate254 ; census_runs0 couverture_manquante244.
- Draws3487130 residual0 rb_mismatch0 ; GPU7.1897ms.
- 575 SHA historiques OK (572PNG+3témoins), preuves/écarts antérieurs archivés notes/essai12-avant13.
- Capture candidate partielle1case origine/h00 : .autoport/refset-candidates/essai13-provenance-v2 ; rc0 captured1.
- Sidecar v2 : binaire/config/PNG/frame + data56f0364a8789c816/inputf97b073c2df76fb4 ; état non restauré tracé.
- Clone pristine propre /home/emeric/code/jak-original-v033 HEADc4bc4d3ff4691902ff023319cb33df71c0040501.
- Son gk build/Release/bin/game/gk SHA256 2801189bff17a731e2697971deccd224a590d902ee54c0b28eb9eb0955fde38a.
- GAME/ENGINE/FR3 fork≠pristine ; SUB.DGO identique (notes/baseline-identities-essai13.json).
- 485f09d6c07bc24c historique=FNV64 binaire, PAS SHA source ; ancien gk exact non retrouvé.
## TENTÉ
- Patch refset.cpp : marqueur v2, sidecars chaque image, scans stricts ; archives jamais réécrites.
- V2 non qualifié : census=0/gate254 ; aucun faux vert par cinq autorejeux. Lecture v2 non exécutée.
- Empreinte data modifiée : invalide anciennes clés v1 du ledger, lignes conservées.
- Audit : aucun checkpoint restore. start recrée Jak ; actors-update drawable.gc:928 porte naissances.
- reset-actors entity.gc:966 altère permanences/quota ; ni cela ni reseed après start ne restaurent monde.
- Arrêt harnais : correctif superviseur déjà présent, neuf tests forensics passent ; pas nouveau patch harnais.
## RESTE
- Implémenter frontière PC commune pré-naissance avec niveaux/permanences/acteurs/RNG/horloges/visibilité/caméra/pas.
- Adapter cette frontière et capture au pristine (aucun hook REFSET/PAD_REPLAY/LEVEL_WARP), build incrémental existant.
- Définir et vérifier données communes compatibles ; qualifier origine à état identique avant toute adoption.
- Compléter provenance producteur sources/config/état : data/input actuels sont empreintes fichiers initiales seulement.
- Produire candidat complet trois modes/21niveaux/8heures/≥4intérieurs ; Sunkenb8 manques conservés.
- Puis cinq rejeux exacts seulement quand qualifiable ; ne pas répéter le run historique identique.
- non prouvé : bit-identité, état, qualification, couverture complète, HDR/Android ; tonemap SDR non corrigé.
- notes/recovery-essai13.md donne détails ; builder PID2541075 repris, aucun appareil ; generic.sh orchestrateur seul.
