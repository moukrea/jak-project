DIRECTIVES v6fca51fe40
Essai39 — même build, éclairage seul ON/OFF.
Contrat actif : .autoport/tools/refset_qualification.md.
Les fichiers on-capture.json/off-capture.json réemploient bootstrap essai17, pad neutre,
village1-out aux huit heures ; phases2/3 séparées, master1 et HDR1 communs.
Chaque capture utilise le runner acquis :
python3 .autoport/tools/refset_campaign.py run --campaign "$PWD/.autoport/reports/lighting-census/notes/essai39-lighting-pair/campaign" --name on-capture --root "$PWD" --env-json "$PWD/.autoport/reports/lighting-census/notes/essai39-lighting-pair/on-capture.json" --timeout 100 --data custom_assets --data managed_assets
Remplacer on par off pour l’autre capture. Le reçu donne reference_root.
Construire qualification-plan.json version2/roots depuis ces deux chemins ; aucune pièce copiée.
Rejeux : mêmes recettes, OG_REFSET=replay et OG_REFSET_DIR=reference_root ; noms on-replay/off-replay.
Le runner appelle exclusivement proof_run.sh lighting-census x86, jamais --off.
Tests de fixtures isolées != preuve jeu ; build et logs de tests dans ce dossier.
Un checkpoint automatique du constructeur (6d8fd414ed) a absorbé une partie du header
pendant les éditions ; aucun changement n’a été annulé ni attribué au build antérieur.

Version finale : sous-dossier final/, après fermeture du défaut pair-assets et
lecture de l’option wind effective (aucun comportement de brise modifié).
Les quatre runs de campaign/ sont le premier binaire3c50ae6265162571, archivés.
La campagne finale est final/campaign/ et emploie le certificat final/source.json.
Même recette, timeout80s après achèvement des8cas vers LF3563 lors du premiercycle.
