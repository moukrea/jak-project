DIRECTIVES vb7966a3839
## ÉTABLI
- Proof officiel 2026-09-08T03:59:09Z, 360 s, Redmi eae4df44 : hdr_tonemap_defects=0, crash=0, frames=840, hits=71072.
- Campagne essai21-readback : 25 lots conservés, 22 retenus, 200 paires, 168/168 cellules, 21 niveaux, 25 vues ; tous ciels/intérieurs/hutte couverts ; erreurs et quality_bad=0.
- TFragment A42 corrigé : lecture float du HDR, états READ restaurés ; 225 traces/103 lectures float, zéro erreur A42 ou refus before-probe dans les lots retenus.
- Build incrémental + repack livré ; lib SHA256 ec1726c1202f3983a2ed0d6ff06da360efdee6a70f6b5088f34a088264804721 ; MD5 build/APK/Redmi e9611463df5d877d04d428061a9e92d3.
- Anciennes paires incompatibles avec ce nouveau binaire : sources et anciens exécutables conservés pour diagnostic ; campagne entièrement recapturée via proof_run.
- Swamp 032102-3631467 : start caméra60:0:50:25, ciel185‰ aux8h ; Sunkenb031529-3628144 : helix puis start −8:90:0:2700, ciel303–304‰ aux8h et intérieur helix.
- Dernier lot035912-3673185 : tonemap_sites=1, hdr_probe_max_x1000=10898 ; groupes chaîne3/5/6=0.
- Fidélité0/exposition1/genou0,95 conservés ; luma équilibrée+4,6032/255,94 cellules plus claires/74 plus sombres. Diagnostics : notes/essai21/quality-review.md.
## TENTÉ
- Swamp : vue native inclinée remplace les arrivées dock/cave1 crashées, sans les déclarer corrigées.
- Sunkenb première vue +160m :16paires mais ciel0‰ ; première tentative surface SIG11 frame109 avant warp, collecte20s ; reprise qualifiée remplace explicitement ces deux lots.
- Ogre première limite160s :540frames sans paire ; ancien lot réussi359s ; limite450s reprend seulement Ogre et produit16captures en348s.
- Tous échecs/mappings conservés dans manifestes et notes/essai21/campaign-runs.jsonl ; aucune preuve/manifeste écrite à la main.
## RESTE
- Orchestrateur : lancer generic ; aucun validateur ni owner-ok produit par ce worker.
- Owner : Options > Recharged, ciels Swamp/Sunkenb, Beach/Training/hutte à midi, Ogre/Rolling. Le zéro machine ne vaut pas satisfaction artistique.
- Résidus : Beach h12 écrêtage ON15545 pixels/distance teinte0,360 ; Ogre h18 luma+37,630 ; aplats Ogre h12+0,11387. Aucune correction locale déterminée par ces seules mesures.
- non prouvé : résolution SIG11/GRV des arrivées abandonnées, tous acquis, ordre/identité GPU complet, Filmique1, coût GPU, sortie HDR native, calibration locale.
- Aucun besoin de rejouer les200paires si rendu/config/binaire inchangés ; toute modification exige compatibilité démontrée ou reprise des seules données invalidées.
- Redmi relancé normalement, debug vide, aucun verrou ; publieur existant laissé actif. État exact : notes/essai21/device-restored.json.
