DIRECTIVES v3909a9767c
Correction partielle mesurée de l’assombrissement pièce/sol ; HDR reste non validé, hdr_tonemap_defects=4.
Recentrage owner appliqué : seul shade.glsl change dans le jeu ; aucun nouveau chantier HD/cache/allocateur/menu.
Composition non-PBR : terme sombre/froid remplacé par1 ; le baked est conservé, l’occlusion retire le supplément solaire existant, amplitude d’ombre réduite.
Gain/teinte éclairés, directions, PCF, poids astraux, produit des facteurs, PBR, alpha, portes et tone map restent inchangés.
Build gk incrémental12.27s, repack28.68s, install22.74s ; aucun iso/GOAL ni NDK complet. 28CGO et bundle inchangés.
APK5d3d6a416c12f690 ; lib0f1a5b25e21ebb4a vérifiées appareil ; aucun échec GLSL recherché, hdr_cfg_bad*=0 et fallback=0.
Huit lignes de la dernière preuve officielle proof_run.sh, vue extérieure :
source=device
serial=eae4df44
sha=0f1a5b25e21ebb4a
duration_s=164
crash=0
frames=1620
FEATURE lighting-hdr armed=1 hits=220312
hdr_tonemap_defects=4
Portail/pièce :401s/crash0/4620frames,4captures/21SHA conformes ; extérieur h0/12/18 :164s/crash0,12captures/37SHA conformes.
Attentes animées après purge portail : ON55.171/110.809s, OFF42.753/84.917s (portal/timing-and-witnesses.json).
Pièce, luma ON/OFF avant41 :64.223/91.365 ; après :91.299/91.099. Détail15.767/20.222→20.191/20.216.
Avant sprites portail, ratios RGB ON/OFF .706/.692/.690→1.0046/1.0001/1.0033 (portal-comparison.json).
Extérieur midi : delta luma ON−OFF image −9.933→+3.874 ; rectangle chemin gauche −51.697→+5.763 (ground-comparison.json).
Ces rectangles ne montrent pas de violet270..330 avant/après : aucune correction des petites zones exactes owner n’est prouvée.
Échec portail conservé : disque clipped403/329.5, détail26.714/27.543 ; image clipped1627/1370.5, excès officiel207 au-delà tolérance.
Le surplus apparaît dans le groupe Sprite3 additif ; sources animées et couches superposées diffèrent. Aucun blend fautif ni correctif supplémentaire démontré.
Deux campagnes distinctes, configurations temporelles/caméras différentes ; aucun cumul artificiel ni ancien lot requalifié sur le nouveau binaire.
Extérieur quality_bad0 mais owner_passed0/missing5/failed1 ; portail quality_bad1 et failed2. Ces absences/échecs restent rouges.
Owner : comparer LightingON/OFF avec sous-option temps réel active ; pièce, chemin/sol devant hutte, puis portail après dix secondes animées.
Le fichier restauré porte realtime-lighting?=#f ; les tests activent explicitement cette sous-option. Préférence conservée, visibilité hors test à distinguer.
non prouvé : cinq cas owner, petites zones violettes précises, ombres perçues, détails pleine résolution (PNG320×180), menuOFF/persistance.
non prouvé : couverture21niveaux×8h/ciels/intérieurs/vraie hutte et crash0 global sur nouveau binaire ; crash Swamp43 documenté, non rejoué.
Réglages restaurés exactement SHA78108670…52fd6, props vides, PID8310 stable12s, aucun verrou (final-audit.json).
Notes et sources avant/après : notes/essai43-rendu/ ; captures brutes et défauts conservés. Handoff à jour ; validateur orchestrateur, aucun owner-ok.
