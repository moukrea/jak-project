DIRECTIVES v0ba5e280ac
Essai 52 : reprise x86 réalisée ; HDR non validé, hdr_tonemap_defects=4, aucune correction esthétique nouvelle revendiquée.
Livré : lots proof_run x86 avec provenance scellée ; opt-in OG_SPRITE_INSTANCE=1 vers Sprite3 Android existant.
Arrêt x86 dès compteurs terminaux concordants, même si des paires sont rejetées ; seuils qualité inchangés.
Build gk incrémental réussi ; 313 tests initiaux puis 39 ciblés finaux passent (notes/essai52/test-traces.md).
Portail : 4 captures, 40 SHA vérifiés ; acteur 1395, animation échantillonnée après ON ≥11,081 s / OFF ≥10,759 s.
Portail luma ON 115,68 / OFF 129,52 ; éco 24 captures, 120 SHA, 96 événements composition ok ; soleil 36 captures.
Leurs mesures conservent des échecs ; voir notes/essai52/instance-analysis.json et campagnes instance-*.
Couverture : 6 lots, 736 captures, 160 couples comptés / 168 ; 56 erreurs conservées, donc couverture non validée.
Snow manque 8 heures ; ciel 16 cellules et vraie hutte 8 cellules absentes (notes/essai52/final-coverage.json).
Village3 repris avec 8 paires ; remplacements refusés sur anciennes ROI de niveau absent, doublons laissés rouges.
Snow repris séparément : 0 paire qualifiée ; aucune répétition ni correction annexe HD/cache engagée.
Huit lignes exactes de proof.txt, dernier run x86 20260909T054700-348832 :
source=x86
binary=build/game/gk
sha=e183b62155e2e97c
duration_s=49
crash=0
frames=1997
FEATURE lighting-hdr armed=1 hits=22818
hdr_tonemap_defects=4
USB absent au 09/09 à 05:33:07Z, pick_device rc3 (notes/essai52/usb-availability.json) ; Android non livré lors de cet essai.
Owner : vérifier sol vraie hutte, luminosité pièce/portail après 10 s, blancs nuages/soleil et éclairs éco dans Options > Recharged.
non prouvé : cinq cas corrigés, détails pleine résolution, couverture finale 21×8/ciels/intérieurs/hutte, menuOFF/persistance, validation USB.
Cause exacte sol/portail non attribuée ; PBR x86=#t contre Android43=#f, pas de conclusion croisée abusive.
Notes/commandes : notes/essai52/ ; handoff.md actualisé. Aucun owner-ok ; validateur laissé à l’orchestrateur.
