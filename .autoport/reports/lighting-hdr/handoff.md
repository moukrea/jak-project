# Handoff — lighting-hdr essai42
DIRECTIVES v708c60642a
## ÉTABLI
Rendu inchangé essai41 : genouSDR.96/libab2f8019a399c9c1 ; aucun build, aucune campagne image42.
Helper soleil modifié : blancOFF non obligatoire si orange ; luma/p99,saturation,violet270..330° contre enveloppeOFF, aireROI/mesures/noir contrôlés.
Disque+2rayons,blancsattendus/détail/aplats toujours exigés,absent nonjugé ; autrescas et porte inchangés. Tests271passés puis62soleil/ciel après derniersgardes.
Sources41soleil relues diagnostic seulement : luma192.025<minOFF192.807,violet.176440>maxOFF.173457 ; notes/essai42/sun-judgment.json.
Nouveau run officiel menu312s/crash1/frames1680/hits943585/defects5 ; notes/essai42/menu-off/proof.txt intact, même lib locale/appareil.
Menu27→51→27→18(save-game-title)→11(memcard-data-exists),crash après acquittement ; LightingOFF jamais atteint.
PCvector-matrix*!+0x18/LRhd-mtx-check-all+0x51c ; objet0x1eb6c4,champ+0x1dfc déduitFFFFFFFF,k20,p19.
Adresses X2=FFFFFFFF+128*21=100000a7f,X3=1000009ff,fauteee_base+X2=8000000a7f ; logs/mémoire/code conservés menu-off/proof-engine.log.
Seul writer normal hd-draw-check3094 reçoit DMA align64 ; init implicite activate gkernel1763..1766 efface champs : init manquante non démontrée.
Piste cache hd-scan-companions rawrefs face compaction/spawns ; deux spawns17:24:26.515/.527,crash17:24:27.067,aucun déplacement objet tracé.
RéglagesSHA78108670…52fd6 exacts restaurés,props identiques,PID14537 stable20s ; acquiscrashes39/menuONretourON39/alpha40 non rejoués.
## TENTÉ
Navigation menu historique n’atteint pas Options : ne pas répéter les taps aveugles. PersistanceOFF/ombresOFF nonprouvées,absence log ombres insuffisante.
Diagnostic crash : A16x16-clobber faux signal,ADDobjet+LDR légitime ; pas dernier écrivain trouvé,pas garde-1 ni init spéculative.
Nuages41h12 : deltaR ONLF1601..1661 33743.8→34577.9,OFF1675..1735 34756.2→35716.8 ; UV sky-tng155..167 dérivent,pas repinnés.
Donc différence moyenne ne sépare pas format/animation ; ni gamma/doublealpha/multiplicateur erroné trouvé,aucun correctif rendu justifié.
Portail41ROI7020px ratiosRGBavant(.706,.692,.690),déficit troiscanaux ; shade.glsl371..388 module volontairement éclairage. Pas attribution dessin.
## RESTE
Priorité : établir origine FFFFFFFF dans hd-mtxarea ou invalidation cachecompagnon, corriger cause mémoire bornée sans toucher modèles/effets.
Finir persistanceOFF/ombresOFF par navigation runtime réelle après stabilité ; ne pas refaire menuON/retourON acquis39.
Nuages/soleil puis sol/portail indépendantséco ; comparabilité UVnuages nonprouvée,soleil ROIinclut fond,pas attribution esthétique.
Sol vraiehutte : caméraessai32(-138.451,49.300,203.282),ancragesage(-132.659,46.198,213.468),aucuneROIsol établie,HUT_VIEWSvide.
Portail10s animé aprèspurge acquis41 mais déficitnoncorrigé ; éco29/30 conservé,aucune nouvelle répétition négative.
Cinqcas restent requis,0passé officiel ; couverture21niveaux8h/ciels/intérieurs/vraiehutte nonexécutée. Binaire41 preuves42menu crash rouge5.
Validateur orchestrateur,aucun owner-ok ; rapport≤40lignes,preuve officielle neuve ; notes42diagnostic.md contient détails/recherche.
