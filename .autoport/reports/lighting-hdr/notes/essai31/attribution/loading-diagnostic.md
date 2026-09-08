DIRECTIVES ve7fcbe0116
Lecture seule : comparaison sky-before31 et portal27.
Sky31 engine.log:13854 LOADSCREEN-SHOW arm5 frames1, :17796 frames240 pendant captures, :140730 frames5760 ; masque dessiné persistant.
loading-screen-pc.gc:640 émet fond noir plein cadre, :650 publie ce compteur dans le chemin draw ; saturation0 des24captures concorde sans preuve visuelle.
Sky31 :11794 LOADSCREEN-FRAME episode5 masque4 images298 ; :13693 episode6 masque4. LS_HOLD_TARGET=4 dans main-h.gc:299.
Target attend les niveaux actifs (target-death.gc:114) puis all-visible? != loading (:180) ; trace absente pour départager ces attentes.
Pose identique sky31 :11792 et portal27 :13545 : -126,46,212 cap163. Cam override0 contre1 ; éclairage seul ON/OFF effectif.
Sky31 :18778 WANT-LEVELS-FAIL need-two-levels spec=village1 ; même erreur portal27 :20637. Pas une cause suffisante.
Sky31 :37979 WANT-DISPLAY village1,display arrive11:18:28 après fin captures11:18:10 ; aucun WANT-DISPLAY portal27.
Portal27 :14862 BLACKCENSUS bg-a src=target terminé ; aucun LOADSCREEN-SHOW ni CLOCK dans ce lot.
Non prouvé : pourquoi TARGET reste tenu ; aucun contournement écran loading recommandé.
