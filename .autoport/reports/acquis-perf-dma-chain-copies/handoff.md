# ETABLI
DIRECTIVES vf72d3bd470
Commit implementation 1ac061ea25 ; garde, census, banc et proof_props livres.
Course USB unique 20260915T000803Z-1325842-2c13369e sur eae4df44.
proof_run rc=0 et dma_check_proof rc=0 ; preuve scellee 47816 octets.
dma_acquis_defects=0, 115 cas passes ; 4200 images, 8400 parcours, max=2, crash=0.
MD5 local/appareil identique 5ff265dc1ae1cfdb3313faa0a6410b70.

# TENTE
Banc isole puis unique course device --timeout 60, tous deux aboutis.
Aucun build, campagne additionnelle ou appel worker de generic.sh.

# RESTE
L'orchestrateur doit lancer generic.sh et ses portes de fermeture ; aucune validation owner a ajouter.
Ne pas relancer de mesure tant que cette preuve fraiche convient aux portes.
Les limites hors perimetre sont dans FINDINGS.txt ; rien a retester par l'owner.
