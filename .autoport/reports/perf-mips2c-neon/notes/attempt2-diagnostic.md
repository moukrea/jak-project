# Reprise diagnostique — essai 2
DIRECTIVES vaff5c1afea

## Décision avant toute course
Aucun proof_run lancé. Les références plage Android manquent et la cause de hutte233 reste inconnue.
Les trois wrappers spéculatifs ont été retirés ; aucune nouvelle cible SIMD introduite.
Aucune origine, propriété appareil, scénario ou seuil changé. Aucun transfert de référence.
L’appareil USB eae4df44 est disponible (pick_device.sh, sortie 0).
Les preuves de l’essai 1 restent historiques : empreintes dans attempt2-preservation.txt.
Le validateur-001.txt disait : mips2c_parity_defects=3 viole le critère == 0.

## Fonctions, chemins et activité
Toutes les mesures de jeu ci-dessous viennent du run historique 20260914T211200Z-949576-04ffe282.

| Fonction | Chemin | Activité historique | Décision |
|---|---|---|---|
| bones-mtx-calc | bones.gc:532, branche alternative | proof.txt:905-906 : 0 opération, 0 image | Retrait wrapper |
| cspace<-parented-transformq-joint! | process-drawable.gc:308, joint-mod-h.gc:234, joint.gc:1253 | proof.txt:908-909 : 20183198 opérations, 13886 images | Retrait wrapper sans gain établi |
| sp-launch-particles-var | sparticle-launcher.gc:15/348 | proof.txt:915-916 : 159438 opérations, 1634 images | Retrait wrapper sans gain établi |
| new-bones-mtx-calc-asm | bones.gc:371/477/527, *use-new-bones*=#t | Sélection dans le source ; pas de compteur individuel fourni | GOAL déjà vectoriel, aucune redirection |
| sp-process-block-2d | sparticle.gc:273-274 | A35-SPART : 1620 appels/96000 itérations par 60 images | Fast-path voisin Gperf-particles conservé |

proof-engine.log:686932, gframes=13920 :
`3d=0.88ms/180c/7680it 2d=10.13ms/1620c/96000it launch=0.38ms/180c`
2D est une troisième fonction active et chronométrée ; cela ne démontre pas une nouvelle optimisation SIMD pertinente.
Les seaux goal_bucket_ms_* ne classent pas individuellement tous les noyaux. Aucun classement global des trois plus chauds établi.
Les coûts x86 précédents incluaient l’oracle : notes/buckets-x86.md. Aucun gain nouveau publié comme mesure.

## Code machine lu par le researcher
new-bones x86 : out/jak1/obj/bones.o SHA256 a96b38083c702405d3968dc9291f79e442598605c0012131963c0cd66bcdba3c.
Relocation top-level 0x334 vers main 0x7f4 : 1071 octets, 223 instructions ; 51 vmulps, 32 vaddps, 3 vsubps, 1 vdivps.
new-bones ARM : membre bones de out/jak1-arm64-full/iso/ENGINE.CGO SHA256 2a27828e99f93fcdcd3f562e19f01a3b4f3c15f158b5437ce836d790f0658a0a.
Relocations top-level 0x6d4/0x6d8 vers main 0xcd4 : 1236 octets, 309 instructions ; 51 fmul, 32 fadd, 3 fsub, 1 fdiv vectoriels.
Exemple ARM : 0xdbc fmul v24.4s,v19.4s,v24.4s. Correspondance déploiement de ces objets non vérifiée.
sparticle ARM objet SHA256 975e82f84c535268ad42475016d7dcedd1f88f747b1b8c47e39df2c771a678ff.
2D : 4884 octets, 1221 instructions, 6 arithmétiques .4s ; 3D : 3740 octets, 935 instructions, 3 arithmétiques .4s.
Le fast-path Gperf-particles, sparticle.cpp:680-740, n’est pas modifié.
Les trois sources retirées sont identiques octet par octet au parent de 8363e895b1 ; OOB et ripple préservés.
L’infrastructure de parité reste disponible ; les wrappers n’ont plus de consommateur moteur.
Fenêtre de coût avec trois nouvelles populations et oracle arrêté : non prouvée, aucun run entrepris.

## Références : inventaire, empreinte, provenance
Lecture USB par `adb -s eae4df44 shell run-as org.opengoal.gk.jak1`, sans lancement du jeu.
Sortie conservée dans attempt2-usb-refset-inventory.txt.
USB origine/ et origine-lumiere/ : huit hXX.png et captured-by.txt seulement, dates 2026-09-07.
USB origine/h09.png : SHA256 d128995109adedbcd2a99c7746398fb4ae459cacd9912b48ff0e4ce0fa70fcd9 ; 128093 octets.
USB origine/captured-by.txt : 7cea45a11be8c9ae, flavour=normal, conforme au témoin publié par l’essai 1.
USB actual/origine-h09.png : 124470 octets, horodatage 2026-09-14 23:13. Aucun traitement visuel.
Local x86 origine/h09.png : SHA256 583eff6e2a379ac842eec289031fde6a1821127be100b2ac9a61548edfa1d89c.
Local x86 origine/beach-start-h09.png : SHA256 387ef20ef0c019c49492c8b799aff6db0350a0aa0b6190b81e7be0867cb5f712.
Témoin local x86 : 485f09d6c07bc24c, flavour=normal. Aucun origine/beach-sun-h09.png trouvé.
Capture x86 historique : h09 étape 3, plage étape 51, 564 étapes (refset-capture.log:12118,100274,1229713).
Le README impose deux origines immuables et références x86/Android séparées ; ces fichiers x86 ne réparent pas la plage USB.

## Causes certaines et inconnues
proof-engine.log:4991-4993 : origine/h09, origine/beach-start-h09, origine/beach-sun-h09, phase 1, heure 9.
refset.cpp:2866 sélectionne identifiant OU continue-point ; beach-start et beach-sun ont le même continue-point.
Aucun cas retiré : réduire la sélection ne créerait toujours pas la référence beach-start Android manquante.
proof-engine.log:51753-51755 : beach-start reçoit (-116,14,40), coordonnées de la hutte.
refset.cpp:1641 pose env POS vide ; kmachine.cpp:5979 reprend alors la propriété Android persistante.
Piste précise de correction : distinguer getenv(POS)==nullptr de getenv(POS) présent mais vide avant fallback propriété.
Retirer seulement la propriété changerait aussi le premier warp avant apply_step_config (refset.cpp:3433) et son état accumulé.
Cette piste moteur hors des trois noyaux n’a pas été appliquée ; elle n’explique pas l’écart hutte antérieur.
proof-engine.log:51748 : hutte maxdiff=233, diffpx=57597. Cause précise non établie.
proof.txt : refs_fp=0000000000000000, provenance_checked=0 ; input=0 dans proof-engine.log:5096.
L’item arme le replay manette sur x86 mais pas la propriété padreplay USB ; neutralité USB non établie.
Capture Android refset-capture-032947.log:58019 : h09 étape 9 sur 24, contre étape 0 dans cet essai.
Manifeste complet, entrée et état accumulé équivalents non établis : aucune correction de distribution suffisante démontrée.

## Reste nécessaire
Identifier une optimisation sur trois cibles actives sans altérer les acquis ; conserver le classement mesuré comme limite.
Résoudre référence plage Android et équivalence hutte par une décision explicite de périmètre si aucun existant qualifié ne peut être retrouvé.
Réparer la priorité env vide/propriété et épingler l’entrée seulement avec preuve de régime équivalent.
Avant le cycle déjà autorisé : noter cibles/références effectivement changées, puis vérifier les 600 images, hd-mtx-check-all, replay=0 et coûts sans oracle.
Aucune campagne supplémentaire, aucune nouvelle origine et aucun contrôle positif autorisé par cette reprise.
