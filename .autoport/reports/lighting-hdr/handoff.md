# Handoff — lighting-hdr, recentrage rendu après essai43
DIRECTIVES v3909a9767c
## ÉTABLI
Owner : refonte lumière/HDR uniquement ; aucune poursuite HD/cache/allocateur/menu. Crash Swamp43 documenté dans essai43/crash-b3-review.md, pas rejoué.
Correction livrée : shade.glsl non-PBR shd_mul=vec3(1), RT_COOL retiré ; lit_mul/occlusions/poids/produit conservés, PBR/defaults/tone map inchangés.
Le supplément solaire reste occultable, mais ombre limitée au baked et amplitude réduite ; aucune nouvelle teinte/gain ni décomposition physique complète.
Build gk12.27s/repack28.68s/install22.74s ; APK5d3d6a416c12f690/lib0f1a5b25e21ebb4a,28CGO/bundle inchangés, empreintes device vérifiées.
Portail officiel401s/crash0/4620frames,4PNG/21SHA ; extérieur164s/crash0/1620frames,3pairesh0/12/18,12PNG/37SHA. Aucun échec GLSL recherché,cfg_bad0,fallback0.
Attente portail après purge :ON55.171/110.809s,OFF42.753/84.917s, animées. Notes essai43-rendu/portal/.
Pièce luma ON/OFF64.223/91.365→91.299/91.099 ; détail15.767/20.222→20.191/20.216 ; ratios RGB avant sprites .706/.692/.690→1.0046/1.0001/1.0033.
Extérieur midi delta luma image −9.933→+3.874, chemin gauche −51.697→+5.763 ; ground-comparison.json conserve h0/12/18,couleur,détail et rectangles.
Portail reste rouge : clipped disque403/329.5, détail26.714/27.543 ; excès image207. Dernière proof extérieure defects4/ownerpassed0/missing5,quality_bad0 ne vaut pas validation.
SettingsSHA78108670…52fd6 exacts restaurés,propsvides,PID8310stable12s,verrou absent. realtime-lighting?=#f dans fichierowner ; tests forcentRT=1, préférence non changée.
## TENTÉ
Cause assombrissement B attribuée par ablation43 puis correction mesurée ; ne pas rejouer ablationquatreprops ni neutraliser toute refonte.
Sol précis non attribué : traces distinguent ciel/sprites, pas terrain/TIE/shadow-geo ; rectangles chemin/entrée sans violet avant/après. Pas ROI owner fabriquée.
Résidu portail : groupeSprite3 entier, maxbleu15.3/17.2 ; middot/harddot superposés, blend Cs*As+Cd, sourcebornée/destinationHDR. Pas doublealpha/double dessin démontré.
Les sources/alphas des sprites diffèrent entrebras ; witnesses.json filtre harddot, engine.log contient aussi middot. portal-residual-review.md donne compteurs et limites ; aucun patch blend justifié.
PNG fixes320×180 ; compteurs natifs conservés, aucun instrument nouveau ni campagne21niveaux dans ce cycle. Anciennes captures restent diagnostic, pas preuve nouveau binaire.
## RESTE
Poursuivre corrections rendu sur vues exploitables : résidu portail puis nuages/soleil/éco et petites zones sol ; pas de détour crashs/allocateur/menu.
Préserver comparaisons couleur/éclat/détail et sources ; ne pas remplacer déficit pièce désormais mesuré par nouveau réglage global spéculatif.
La couverture21niveaux×8h/ciels/intérieurs/vraie hutte et les cinqcas restent requises et non acquises sur cette lib. Pas de somme de flags entre campagnes temporellement incompatibles.
MenuOFF/persistance/ombres perçues et crash0 global non prouvés ; rapport≤40lignes/8lignes proof livré. Validateur orchestrateur, aucun owner-ok.
