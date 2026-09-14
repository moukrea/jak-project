DIRECTIVES v775512c234

Essai 4 : reprise depuis le handoff, sans répétition de la course ON.
Le contrat demandé sous prompts/ existe sous .autoport/prompts/ ; lecture complète effectuée.
L’entrée backlog ne comporte que des modifications préexistantes de statuts/verdicts.
Aucun SCOPE-ao-prepass-tie-alpha ni proof_plan de cet item trouvé.

Contrôles de cet essai :
- bash .autoport/lib/pick_device.sh : code 0, sortie eae4df44.
- Lecture de validator-003.txt : refus unique de ao_tie_prepass_defects absent.
- Le producteur existant ao_tie_alpha_probe.cpp:277 reste diagnostic_only.
- generic.sh:181-182 contrôle une ablation présente, sans demander un bras absent.
- ao_static_probe.h:127-130 consomme la référence ; proof.txt porte compared=1 et baseline_saved=0.
- Aucun build, aucune course, aucun appel du validateur ; aucune preuve actuelle revendiquée.

Empreinte de la preuve historique conservée : SHA256 629dbf6b053af4ce8738f735ae5d6b1de0b69e8f5f6a93a89bf86c32feca7fe4.
Identité : proof_run_id=20260914T171948Z-345561-e6efad49, proof_attempt_id=ao-prepass-tie-alpha@3#1789406274.
Les huit lignes du rapport sont extraites automatiquement et étiquetées historiques ; proof.txt n’est jamais écrit.

Décisions nécessaires avant reprise, soumises au superviseur par ces artefacts, pas des ordres ajoutés au backlog :
1. Réconcilier la clause de correction dans la prépasse avec la table préalable démontrant l’alpha de mesure à 1.
2. Résoudre explicitement l’exigence OFF du contrat et sa condition d’autorisation dans DIRECTIVES.
3. Si le contrat complet est conservé, inscrire un proof_plan autorisé nommant les trois vues et bornant les bras.
4. Ce plan doit couvrir identité couleur AO éteinte et fragments couleur changés ; la logique actuelle ne les mesure pas.
5. Préciser le périmètre autorisé du producteur de ces comparaisons et de leur agrégation par preuve.
6. Prévoir référence native puis comparaison du même binaire pour la sonde existante, sans modifier ses critères.
Pas d’auto-autorisation de campagne ni d’instrument neuf, pas de modification du validateur pour créer un vert.

Travail autonome restant dans le périmètre courant : signalement, rapport et handoff ; terminé à cet essai.
Le critère machine est toujours non satisfait ; aucune clôture revendiquée.
