# Handoff — lighting-hdr, essai52 : x86 exécuté, HDR non validé
DIRECTIVES v0ba5e280ac
## ÉTABLI
proof_run accepte désormais les lots x86 ; snapshots binaires/sources/config/OG_* scellés, plateformes distinctes, critères inchangés.
Build gk incrémental réussi ; SHA256 e183b62155e2e97c165a41b32550dcf0e195f40519c7e74369a75ba6a4cea4f4.
OG_SPRITE_INSTANCE=1 réutilise Sprite3 Android existant ; PATH instanced=true, ROI solaire/portail/éco présentes (instance-analysis.json).
Portail acteur1395 : attente repin→sample ON≥11,081s/OFF≥10,759s, alpha/couleur variables ; luma115,68/129,52, blancs46/62.
Éco acteurs10012/10013 :24captures,96événements composition ok ; ROI10012h12 blancs57,83/31, détail31,62/33,12, échec jugé.
Soleil :36captures ; disque+rayons identifiés, lumaON193,14<minimumOFF193,89 ; pas disparition universelle des blancs démontrée.
Cumul final :160/168couples,736captures,56erreurs ; hdr_tonemap_defects=4 ; snow8h/ciels16cellules/hutte8h manquent (final-coverage.json).
Reprises isolées : village3 huit paires, snow zéro (OFF achromatique) ;32captures chacun, crash0, manifestes errors[].
USB constaté absent le09/09à05:33:07Z : pick_device rc3 (notes/essai52/usb-availability.json), aucun Android testé52.
313tests initiaux puis39ciblés finaux passent ; détails/traces dans notes/essai52/test-traces.md. Aucun validateur exécuté.
## TENTÉ
Commandes et résultats exacts : notes/essai52/*-command.json, *-run-result.json ; preuves officielles et captures conservées.
Campagnes essai52-x86-instance-{portal,sky,eco,coverage}, même binaire récent ; anciens lots non instanciés seulement diagnostic.
Couverture3 20260909T053055-325144 :13cas expected region not drawn, snow15/18/21 seulement black or achromatic OFF.
Reprises20260909T054517-344531 et20260909T054700-348832, mappings explicites conservés ; aucune substitution forcée.
check_owner_replacement refuse village3 via clouds failed de scène non dessinée ; question signalée, garde intacte.
L’attente jusqu’au timeout après paires rejetées est corrigée : arrêt sur derniers compteurs terminaux concordants, défauts inchangés.
Premier script modifié pendant run a échoué après collecte ; agrégation officielle seule a restitué timestamp original, aucun proof manuel.
## RESTE
Pas de nouvelle correction esthétique livrée52 : cause des petites zones du sol et résidu composition portail non attribués.
PBR x86 actuel=#t, Android43=#f ; ne pas attribuer leurs écarts à correction43. shade.glsl43 conservé, aucune préférence changée.
Priorité sol vraie hutte/portail : cadrage exploitable et contribution exacte avant réglage ; pas rejouer global knees41 ni ablationB43.
Lire replacement-guard-review.md en notes/essai52 ; ne pas effacer les3achromaties snow comme erreurs de chargement établies.
HUT_VIEWS vide :8heures vraie hutte restent absentes ; captures320×180 ne prouvent pas détails pleine résolution.
non prouvé : cinqcas corrigés, couverture finale21×8/ciels/intérieurs/hutte, menuOFF/persistance, fraîcheur/crash0 Android.
Exécuter x86 via commandes notes52, DISPLAY=:0 et XAUTHORITY du Xwayland courant ; pas attendre USB pour diagnostic partagé.
Dès USB disponible : proof_run lighting-hdr device ; aucun vieux binaire/preuve substitué, aucun owner-ok, generic réservé orchestrateur.
