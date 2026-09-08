DIRECTIVES v0ba5e280ac
Tester Codex usb_check, rôle tester/medium, et researcher hdr_diagnostic, rôle researcher/high, gpt-6-astra : terminés, résultats vérifiés par le manager.
Constat50 : adb devices -l vide, pick_device et unique proof_run rc3 sans ANDROID_SERIAL imposé ; notes locales donnent heures UTC et sorties exactes.
Le run est exécuté sur la règle corrigée USB quelconque/Honor, contrairement aux essais47–49. Aucun appareil choisi, aucune preuve jeu produite.
Version du contrat recalculée via directives.version('lighting-hdr') : v0ba5e280ac.
Aucune correction source déjà justifiée mais manquante identifiée par la revue bornée.
Vérification source : shade.glsl382–388 conserve shd_mul=vec3(1) non-PBR ; sprite3_3d_inst.frag26–29 borne source RGB/alpha ; Sprite3.cpp1136–1164 encadre le groupe complet.
Ces lectures ne sont pas une preuve d'exécution ; elles ne justifient aucun nouveau réglage de blend/gain/courbe.
Sol : notes/essai43/coverage-view-plan.md5–10 donne seulement le repère géométrique historique ; nouveau refset.cam localisant les petites zones requis.
Aucun instrument existant identifié séparant terrain/TIE/décal/ombre dans cette ROI ; ne pas répéter la paire43 ni fabriquer attribution/couverture.
Portail : notes/essai43-rendu/portal/command.json conserve temporal2/loadsettle660/settle660 ; nouveau lot avec série USB choisie et nom neuf uniquement.
Extraire du futur engine.log : grep -a -nE 'REFSET (repin-particules|sample|effective)|HDR-OWNER-SPRITE' ; relier reset, horodatages, particle_age et évolution numérique.
Particle_step configuré, âge et variations entre captures ne suffisent pas seuls à prouver dix secondes continues d'animation.
Le script historique portal/timing.py7–17 calcule seulement attente et témoins, puis écrit dans son propre dossier : ne pas relancer inchangé.
Toutes les consignes historiques eae4df44 obligatoire/Redmi-only sont obsolètes ; pick_device choisit le prochain USB disponible.
Aucun diagnostic négatif rejoué, campagne, build, test synthétique, déploiement ou ancien résultat promu pendant50.
non prouvé : localisation causale du sol, correction exacte du résidu portail, animation continue≥10s, cinqcas et couverture finale.
