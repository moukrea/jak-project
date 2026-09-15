## ÉTABLI
DIRECTIVES vd321fc8caf
Essai3 USB eae4df44 : preuve fraîche course20260915T014447Z-1553215-9541808a, frames5100/crash0.
47 sites, 5 marqueurs complets, maximum2 instructions ; codegen_lot_defects=1.
Référence a2 INCHANGÉE refs3a1feecef859c3a1 ; bin141bcc7b2d3081bb/data4eabb0fc1e6d0a6c/inputf97b073c2df76fb4.
Rejeu a3 : sample1081/ancre901/slip0 ; maxdiff57/diffpx550/compared1/provenance_bad0.
proof-engine.log:51811 : ledger runs=2 flaky=1 ; essai2 donnait61/577.
MD5 libgk local/appareil a65acc137c3f34e71c77c82f96ff62cc ; aucune source modifiée ni build refait.
Diagnostic a2 vérifié : seedlf3/repin902/179 pas particules et totaux acteurs identiques.
corner_w identiques ; rephase animation11/13 et temps mural5,220/5,900s différents, cause RGB non localisée.
Détail : notes/a3/researcher-diagnostic.txt et a2-diagnostic-excerpts.txt.
## TENTÉ
Lecture seule ciblée puis UN rejeu frais120s via proof_run.sh ; aucune recapture/ablation/campagne.
fixed_tick=0 conservé : pad replay force déjà le timestep ; l’activer seul au rejeu changerait le régime.
Aucune correction codegen justifiée ; pas de modification de refset ou d’une feature validée pour obtenir zéro.
Les preuves de build/goalc/CGO/encoding de l’essai2 restent dans notes/a2 ; ne pas les refaire.
## RESTE
Localiser la divergence avec un périmètre de diagnostic état/RNG explicite : empreintes complètes absentes au sample.
Ne pas recapturer a2 ni répéter des rejeux inchangés : deux rejeux divergent déjà, sans cause identifiée.
La parité ancien rendu reste non prouvée même si le candidat devient répétable.
Symboles dynamiques proches une instruction : manque garantie offsets/relaxation, non implémenté.
Gain goal_busy_ms et coût interne mips2c4->7 non prouvés ; acquis complets non prouvés.
Le validateur reste à l’orchestrateur ; rapport/FINDINGS décrivent le rouge, aucune fermeture revendiquée.
