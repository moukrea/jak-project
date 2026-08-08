# OWNER VERIFY QUEUE — à tester au réveil (2026-08-04)
# Protocole nuit (owner ~01:55) : le framework avance en continu ; le superviseur fait une PRÉ-GATE
# humaine (vérifie ce qu'il peut : device, logs, captures grossières) et pose le token owner-ok pour
# ne pas bloquer la chaîne. TA vérification reste le verdict FINAL — tout item pré-gaté ici doit être
# re-testé par ton œil ; on rouvre ce qui ne te va pas.

## Légende
- [PRÉ-GATÉ ✅/⚠️] = passé par la pré-gate superviseur (✅ = confiant, ⚠️ = réserves notées)
- [EN COURS] = le framework bosse encore dessus
- [À TESTER] = prêt pour ton verdict

## 0. ⛔ BLOQUANT — LE REDMI EST REVENU MAIS IL EST VERROUILLÉ (mis à jour 2026-08-07 15:17)
**Une seule action est demandée : DÉVERROUILLE le Redmi eae4df44 avec ton code PIN.**
Le rebranchement est déjà fait, il n'y a plus rien à brancher. Rien d'autre n'est bloqué — le build
du cycle 8 est fait, vérifié et prêt à partir, et il démarrera TOUT SEUL dès le déverrouillage.

Historique, à la seconde près (log noyau puis état du téléphone) :
```
août 07 13:41:07  kernel: usb 1-6: USB disconnect, device number 22   <- il a quitté le bus
août 07 15:11     eae4df44 réapparaît sur le bus (usb:1-6)            <- il a REDÉMARRÉ
août 07 15:17     dumpsys user -> State: RUNNING_LOCKED               <- il est au verrou
```
Le téléphone n'a pas seulement été débranché : il a **redémarré** (uptime 363 s à 15:13). Après un
redémarrage, Android garde le stockage chiffré **fermé tant que le PIN n'a pas été saisi une fois** :
`/storage/emulated/0/OpenGOAL` n'existe littéralement pas pour l'instant. Or c'est là que vivent ton
`settings.ini`, le pack d'assets et tout ce que la campagne doit lire et écrire. Tant que c'est
verrouillé, il n'y a rien à faire sur le téléphone — et surtout rien à forcer.

⚠️ **Ce que le déverrouillage va réparer :** la jambe interrompue de 13:41 avait déjà poussé
`physics? = #f` / `quality = 1` et son nettoyage n'a pas pu tourner — **la physique est restée
COUPÉE** et ton `settings.ini` non restauré. La sauvegarde exacte (2697 octets) est sur le disque et
sa restauration est l'étape 0 de la campagne : ne juge aucun rendu avant qu'elle ait tourné, sinon
tu regarderas un build sans physique et tu me diras à juste titre que rien n'a changé.

**Tu n'as aucune commande à taper.** Un veilleur tourne déjà et surveille l'état du verrou ; dès que
le téléphone est déverrouillé il enchaîne tout seul : restauration de tes réglages → installation →
les 4 jambes de preuve → rapport → validator. Suivi en direct :
```
tail -f .autoport/reports/Grecharged-secondary-motion/autoclose.log
```
Et si tu préfères la lancer à la main, c'est la même chose en une commande :
```
bash .autoport/physics_c8_close.sh
```

## 1. Menu overhaul (parké AVANT la nuit — rappel, rien de nouveau)
- [À TESTER, déjà connu] Structure 5 catégories OK (tu l'avais acceptée) ; esthétique holo/drone
  PARKÉE à ta demande (dégradé violacé plein écran ≠ holo bleuté gauche + drone). On y revient après HD.

## 2. HD Jak (Grecharged-hd-models3) — [EN COURS, cycle défauts]
### VERDICT OWNER 08:00 (Honor) : ✔ défauts 5 (PNJ cinématique) + 6 (Jak fantôme) CONFIRMÉS corrigés.
### Restent : long jump (repro exacte : avancer+R1/R2+saut => cancelled), Jak invisible au logo ND,
### gap cran→cheveux (on voit l'intérieur de la tête), yeux blancs, visage inanimé, clipping.
### PRÉ-GATE 03:20 [⚠️ faux vert intercepté — cycle défauts CONTINUE]
- Le validator a re-passé à 02:59 MAIS sur le rapport d'AVANT la réouverture (aucune preuve nouvelle) :
  faux vert intercepté par le superviseur. Validator DURCI (preuves plus récentes que le début de cycle
  + lignes de résolution explicites long-jump et fantôme-cinématique exigées). Phase rouverte, worker
  reparti (attempt 2/6). Le vrai travail du cycle (harnais A/B long-jump, analyse movie/ghost) était
  en cours mais pas fini — rien de perdu.
### PRÉ-GATE 02:20 [✅ base / ⚠️ défauts en cours]
- Vérifié par le superviseur : validator+close-gate PASSÉS (attempt 3) ; deploy_verify PASS sur le
  Honor (le device fait tourner le build frais, prouvé) ; capture de preuve du worker regardée :
  **Jak HD cohérent et texturé, visible en jeu** (cheveux blonds, tunique bleue, Daxter au dos),
  zéro crash. → La base M1 est réelle.
- Décision : PAS de token — phase ROUVERTE pour brûler TES 7 défauts (long jump + Jak fantôme en
  priorité, rédhibitoires). Le worker exécute son propre runbook défaut par défaut, preuves device.
- À TON RÉVEIL : re-tester les 7 points sur le DERNIER build du Honor (surtout long jump R1/R2+X,
  une cinématique avec PNJ, et les yeux/gap de près).
Jalon acquis : Jak HD VISIBLE + animé sur Honor. Ta liste de défauts (01:45) est le brief du worker :
  (7) long jump cassé [priorité 1] · (6) Jak fantôme figé dans les cinématiques où il ne doit pas
  être [priorité 1] · (1) yeux blancs sans pupilles · (2) gap bandeau/cheveux (2 hypothèses : cheveux
  trop hauts OU pièce manquante) · (5) PNJ qui clignotent en cinématique · (4) visage inanimé ·
  (3) clipping vêtements (bleu/blanc jambes, col/lanière).
À ton réveil : re-tester ces 7 points sur le DERNIER build (le tien datait d'avant plusieurs fixes).

## 3. Keira/Samos plus cursed (fix village1 stock) — [PRÉ-GATÉ ✅ mécaniquement]
La village1.fr3 cursed a été écrasée par la stock sur le Honor (vérifié par taille/bytes).
À ton réveil : un coup d'œil au village (Keira au chantier du zeppelin, Samos dans sa hutte) → normaux.

## 4. (sera rempli au fil de la nuit : HD-models4 Daxter/Keira/Samos si M1 passe, etc.)

---
(Le superviseur ajoute une entrée datée à chaque pré-gate avec : ce qui a été vérifié, comment,
les réserves, et EXACTEMENT quoi tester toi-même.)

### PRÉ-GATE 09:00 [✅ token — M1 avancé, M4 démarre]
- Vérifié (4 min) : deploy_verify PASS (Redmi = HEAD frais), rapport 08:40 frais, défauts 5+6 prouvés
  (device + ton œil). **Long jump = PAS un bug HD** : rate aussi en stock sur device (A/B 2 runs), x86
  ON==OFF avec ta combo exacte → coupable probable = overlay tactile (vitesse de stick trop basse au
  moment du R1+X) → PISTE SÉPARÉE à ouvrir (pas HD).
- À TESTER (toi, sur le prochain build jak-builds) : ① le long jump à la MANETTE si tu en as une sous
  la main (si ça marche manette et pas tactile → confirme l'overlay) ; ② logo ND : Jak encore
  invisible (fix prévu en M4) ; ③ yeux/gap/visage/clipping : inchangés pour l'instant.
- M4 (Daxter J3-cine / Keira J2-1ère-cutscene / Samos J3-cine) DÉMARRE avec le fix logo dans son scope.

### 09:35 — Long jump tactile : requalifié RÉGRESSION (ton fait "ça marchait avant")
Piste dédiée créée : Gtouch-longjump-regression (passera juste après M4, avant les looks bonus).
Approche : bisect (suspect n°1 = refonte menu/zones tactiles) + injection touch réelle de ta combo.
Rien à tester pour toi là-dessus tant que la piste n'a pas produit un build.

### PRÉ-GATE 10:25 [✅ token M4] — DAXTER/KEIRA/SAMOS HD + fix logo, device-prouvés
- Vérifié (5 min) : deploy_verify PASS, rapport frais, les 3 nouveaux personnages APPENDÉS + rendus
  en vrai gameplay (Daxter jak3-ciné SANS pantalon sur l'épaule ; Keira jak2 1ère-cutscene AVANT
  bottines près du zoomer ; Samos jak3-ciné sur sa mezzanine) + **fix « modèle partout »** prouvé
  (l'acteur Jak du logo ND est maintenant couvert — plus d'invisible au logo). Capture Keira regardée :
  cohérente, plus de cursed. Zéro crash.
- À TESTER (toi, build jak-builds) : ① séquence logo ND → Jak HD visible (plus invisible) ;
  ② Village : Keira (zoomer) + Samos (hutte) en HD cohérents ; ③ Daxter HD sur l'épaule partout ;
  ④ cinématiques avec eux trois ; ⑤ les polish M1 restants (yeux/gap/visage/clipping) : inchangés.
- Phase suivante lancée : Gtouch-longjump-regression (ton long jump tactile).

### 11:00 — Ton verdict M4 (logué) : rendus OK mais qualité pas là — cycle défauts 2 spécifié
Daxter SANS mâchoire (cursed, priorité 1) + fourrure transparente ; yeux/verres blancs x3 (fix
systémique eye_id) ; visages immobiles x4 (blerc — barre owner : TOUTES les anims faciales, pas juste la mâchoire) ; doigts Keira + barbe Samos (mapping d'os) ;
sourcing Keira bottines à vérifier (peut-être déjà bottines en 1ère ciné — on te dira).
Lancement : juste après la phase long-jump tactile en cours.

### 11:10 — Menu (parké) : régressions fonctionnelles loguées pour la reprise
Sélecteur displacement (parallax/tess/none) cassé + réglages qui se marchent dessus. Corrigés quand
la phase menu reprendra (après les HD) — logué dans son brief avec audit ligne-par-ligne exigé.

### PRÉ-GATE 11:55 [Gtouch-longjump] — LONG JUMP TACTILE : ta combo PROUVÉE 5/5 sur le Redmi, PAS une régression du binaire
- Vérifié (validator PASS) : ta combo exacte (courir + pilule R1/R2 maintenue + X) injectée en VRAIS
  événements tactiles multi-doigts (TouchReplayPlayer, pas cpad) : **5/5 wheel→wheel-flip** sur 5 runs
  indépendants depuis le spawn (traces d'états + dump des gates à chaque edge : stick 0.99, toutes
  portes vertes). Archéologie git : zones R1/R2 de l'overlay inchangées au byte près depuis le 23/06,
  pad.gc/target.gc intouchés — rien à bisecter côté code.
- CE QUI TE FAIT RATER SYSTÉMATIQUEMENT (mécanique du jeu d'origine, pas un bug) : la décision
  wheel est UNE-SEULE-CHANCE à l'instant où R1 s'enfonce. Au tactile tu MAINTIENS la pilule : si
  l'appui tombe avant que Jak coure, sur une pente, ou contre un obstacle → duck-walk, et duck-walk
  n'a AUCUNE sortie wheel tant que R1 reste tenu → chaque X suivant = saut normal. À la manette on
  relâche naturellement la gâchette entre les essais, au tactile non → impression de "systématique".
- À TESTER (toi, au tactile) : cours D'ABORD sur du plat dégagé, presse la pilule R1/R2 PENDANT la
  course, X aussitôt après — et RELÂCHE la pilule entre deux essais. Si ça rate encore comme ça sur
  du plat, dis-le : on instrumentera TA session en live (les dumps de gates sont dans le build).

### 12:15 — Long jump tactile : CLOS (ton verdict + preuves worker convergent)
Pas une régression (5/5 en injection, code input inchangé depuis juin). Ton "timing très tight" =
piège duck-walk au tactile (R1 tenu tôt + pouce stick qui ralentit — la manette n'a pas ce problème).
AMÉLIORATION ERGO NOTÉE AU BACKLOG (après la piste HD) : fenêtre de tolérance côté overlay tactile
(garder la vitesse de stick "récente" valide quelques frames quand R1 arrive) pour détendre le timing.
### 12:15 — M4 ROUVERT en cycle défauts 2 (backport COMPLET par définition)
Daxter mâchoire (prio 1) + fourrure, yeux/verres x3, visages TOUTES anims x4, doigts Keira,
barbe Samos, sourcing Keira — le worker repart dessus maintenant.

### 19:00 — Ton verdict cycle-2 : VISAGES VIVANTS ×4 ✔ (jalon majeur) — cycle 3 lancé
Régression PNJ-clignotement (prio 1, était corrigée) · Daxter troués/tête transparente (fourrure jak3
mal backportée) · Jak gap+clipping (survivants) · Samos barbe clip/bout · Keira yeux noirs au blink.

### PRÉ-GATE ~19:00 [Grecharged-hd-models4] — CYCLE DÉFAUTS 2 : les 6 classes traitées, prouvées sur le Redmi (validator PASS)
- Racine commune trouvée : le rip GLB perdait les draws mod/blerc du donor (mâchoire de Daxter = géométrie
  BLERC, pas un os !), les yeux gardaient les slots du donor, les modes de draw étaient dégradés (fourrure
  transparente). Le bake cycle-2 passe tout par stamp (modes/eye/effets EXACTS du fr3 donor) + remap yeux
  vers TES drivers + PORT COMPLET du blerc (targets remappés sur les canaux driver).
- Par classe : C = parité géométrique totale donor==appendé (mâchoire Daxter restaurée, draws 17/17,
  gap crâne→cheveux Jak = même racine, restauré) ; A = yeux liés aux slots driver x4 (close-up intro :
  iris BLEUS, plus blancs) ; D = doigts Keira mappés pivot_err 0.0000, barbe Samos suit son parent mappé ;
  E = modes fourrure byte-identiques au donor ; B = canaux blerc : Jak 14/14, Daxter 28/30, Keira 26/29,
  Samos 26/30 (les 9 canaux découverts = zéro similarité géométrique dans le donor, documentés un par un) ;
  F = VERDICT SOURCING : la Keira de la 1ère ciné Jak 2 a DÉJÀ des bottines (aucune variante sandales
  dans tout le dump jak2 — tes sandales, c'est le look Jak 1). Le modèle actuel est le bon.
- Preuves device (eae4df44, build frais deploy-verify PASS) : vraie cinématique d'intro avec les 4
  compagnons HD (slots visage tenus, zéro crash), le visage HD de Jak S'ANIME (yeux ouverts → clignement
  dans leg3-talk.mp4). Captures : leg3-intro-1.png (close-up yeux bleus), leg2a-samos-idle.png,
  leg2b-keira-idle.png + 3 vidéos (.autoport/reports/Grecharged-hd-models4/).
- À TESTER (toi) : ① intro + cinématiques → les 4 visages s'animent (bouche/yeux/sourcils) ;
  ② Daxter : mâchoire présente, fourrure opaque ; ③ yeux/verres x4 ; ④ doigts Keira, barbe Samos en ciné ;
  ⑤ clipping vêtements Jak. Si une expression précise reste figée, nomme le MOMENT exact (les 9 canaux
  sans contrepartie sont listés dans le rapport — on chassera canal par canal).

### 20:05 — Intro : CRASH (prio 0, routé) + yeux précisés
Crash après "this place just gives me the creeps" (chargement Daxter ottsel ?) — le worker doit
étendre sa preuve à l'intro COMPLÈTE. Paupières de Jak broken aussi (classe blink générale). Pupilles :
confirmé structurel — l'eye-remap sert les pupilles JAK 1 ; le port des iris du donor est exigé.

### 23:15 — Deux missions consignées au backlog framework
1. Gmenu-flag-off (passe AVANT les looks bonus) : la refonte menu cassée sort des builds (flag OFF
   par défaut, ancien menu fonctionnel restauré — displacement de retour). 2. Grecharged-secondary-motion
   (après M5) : jiggle Keira, barbe Samos, vêtements/lanières/cheveux de Jak en vraie physique,
   cheveux longs (Keira/Samos/Jak/Gol), Maia+archéologue en étude de faisabilité.

### PRÉ-GATE 01:30 [✅ token cycle-3] — crash intro FIXÉ + disparitions PNJ re-corrigées (compteurs)
- Crash ottsel : root-causé (spawn pendant un teardown de niveau) + prouvé : intro COMPLÈTE 9,5 min
  jusqu'au gameplay, zéro crash. PNJ : suppression fail-open => blackout structurellement impossible
  (device 169k appels, 0 blackout/0 gap). deploy_verify PASS.
- À TESTER (toi) : ① l'intro complète (la cinématique qui crashait) ; ② cinématiques village (plus
  de disparitions) ; ③ re-vérifier Daxter (trous/tête), gap Jak, clipping, barbe, doigts ;
  ④ pupilles/blink : voir rapport worker (peut rester en cours — pas re-testé si inchangé).
- Phase suivante : Gmenu-flag-off (l'ancien menu fonctionnel restauré dans les builds).

### PRÉ-GATE 04:58 [✅ token Gmenu-flag-off] — L'ANCIEN MENU FONCTIONNEL EST DE RETOUR
- Prouvé : refonte compilée-out (OFF par défaut dans tous les builds livrés), audit complet des
  bindings (zéro collision, zéro paramètre fantôme), **displacement parallax/tess/none DE RETOUR et
  opérationnel** (testé runtime), toggles HD/PBR accessibles depuis l'ancien menu. deploy_verify PASS.
- À TESTER (toi) : ouvrir le menu → l'ancienne structure ; régler le displacement ; vérifier tes
  réglages favoris ne se marchent plus dessus.
- Phase suivante : M5 (looks bonus, chaque personnage complet d'entrée).

### 08:15 — Ton verdict build cumulé : ÉNORMES progrès actés
✔ clipping Jak · ✔ Daxter parfait · ✔ barbe Samos · ✔ yeux HD (iris donor) · ✔ PNJ stables.
Cycle 4 (après M5) : restaurer le CLIGNEMENT (le fix anti-noir a supprimé le blit de paupière = plus
de blink visible) + bretelles Keira qui clippent l'avant du corps.

## 5. HD BONUS LOOKS M3 (Grecharged-hd-models5) — [À TESTER] (2026-08-05 ~09:00)
Les 5 looks bonus de cinématiques sont sur le Redmi (build da5e00544d + pack 9 modèles) :
- **Menu → RECHARGED → 4 nouvelles lignes** JAK/DAXTER/KEIRA/SAMOS LOOK (juste après ENHANCED
  MODELS) : ORIGINAL / HD / et les bonus — Jak: JAK II + JAK 3 ; Daxter: PANTS ; Keira: JAK 3 ;
  Samos: YOUNG. Changement de look EN DIRECT (despawn/respawn ~1 frame). Défaut = HD (M1/M2).
- **NOTE**: ton « Keira Jak2 bottines » est DÉJÀ le modèle HD par défaut de M2 — il n'existe
  qu'une seule Keira highres dans tout jak2 et elle porte les bottines (aucune version sandales).
  Le seul nouveau look Keira est donc le Jak 3 (bottines + visage remodelé).
- Device-proven (captures dans .autoport/reports/Grecharged-hd-models5/): legA*(hut Samos/Keira,
  les 4 bonus rendus), legB (Jak 3), legC-talk.mp4 (intro complète, Young Samos PARLE — face anim).
  Zéro crash sur toute l'intro, flicker 0/0, tes settings restaurés à l'octet.
- À TESTER toi-même : ① chaque carousell dans le menu (le changement doit être instantané en jeu) ;
  ② l'ESTHÉTIQUE de chaque look (vigilance : proportions Young Samos sur le rig du vieux, le
  pantalon de Daxter, les tenues Jak II/3 sans cloth-sim jak1) ; ③ ORIGINAL = stock pur ;
  ④ une cinématique avec les bonus actifs. Ton œil = verdict final.

### PRÉ-GATE 09:25 [✅ token M5] — LES 5 LOOKS BONUS SONT LÀ
- Prouvé device : Jak-J2, Jak-J3, Daxter-PANTALON, Keira-J3 (bottines+visage), Young Samos —
  visibles + animés (visages/blerc actifs), sélecteur par personnage dans l'ancien menu
  (JAK/DAXTER/KEIRA/SAMOS LOOK : Original / HD / bonus — défaut HD), switch de look en live.
- À TESTER (toi) : ouvrir le menu → les 4 lignes LOOK ; essayer Jak-J2 puis Jak-J3 ; Daxter pantalon ;
  Keira J3 ; Young Samos ; vérifier le retour à HD/Original. Une cinématique avec un look bonus actif.
- Phase suivante lancée : cycle 4 (clignement restauré + bretelles Keira), puis LA PHYSIQUE.

### 10:35 — M5 ACCEPTÉ par ton verdict (« impeccable ») ✔
Carry : bretelles Keira clippent aussi sur keira3-hd -> le fix cycle-4 couvrira les 2 looks.
Nouveau : look bonus « Jak 3 masque baissé » = masque AUTOUR DU COU, visage découvert (l'actuel jakc = masque sur le visage, on le garde aussi) — 5e option JAK LOOK.

### 11:05 — Extension : TOUS les looks ciné de Jak (J2+J3) — recensement exhaustif demandé au worker
La liste complète de ce qui existe arrivera dans son rapport ; intégration de tout au carousel ensuite.

### 11:55 — Physique : périmètre élargi ferme (accessoires + toutes variantes de look + tous PNJ
cheveux longs y compris Maia — injection d'os sur modèles stock pour les non-HD).

## 6. HD MODELS M2 — CYCLE 4 COMPLET (blink + bretelles + Jak-3 masqué) — [À TESTER] (2026-08-05 ~12:50)
Build cycle-4 sur le Redmi (deploy_verify PASS, pack 10 modèles md5-vérifié) :
- **① LE CLIGNEMENT EST DE RETOUR** : chaque personnage HD cligne avec la PAUPIÈRE DE SON DONOR
  (texture d'eyelid jak2/jak3 portée par modèle, peinte à la position de paupière du driver — le
  mécanisme de blink jak1 d'origine, sans le noir). Compteurs renderer sur device : paupière
  donor peinte dans 100% des fenêtres, excursion fermé/ouvert visible sur les 8 slots d'yeux,
  ZÉRO événement « stock lid » (le bug yeux-noirs est compté et reste à 0). Toute l'intro : les
  4 visages clignent en cinématique. Nuance honnête : Young Samos n'a pas de texture de paupière
  propre dans le dump (yeux peints dans son visage) → il cligne avec celle du vieux Samos.
- **② BRETELLES KEIRA fixées sur SES DEUX LOOKS** : les 4 joints *Strap2 (scale 0.103 identique
  des deux côtés) étaient classés orient-copy → les clés de TRANSLATION du driver étaient jetées
  (0.36-0.44 u de dérive dans la poitrine). Reclassés mode-1 (replay des vraies anims : erreur
  4e-12) sur keira-hd ET keira3-hd ; toutes les autres tables sont restées BYTE-IDENTIQUES.
- **③ NOUVEAU LOOK « JAK 3 MASKED »** (5e option JAK LOOK : ORIGINAL/HD/JAK II/JAK 3/JAK 3 MASKED) :
  il n'existe PAS de modèle ciné masqué séparé dans jak3 — le masque baissé est un blend-target
  (target 15 : 614 verts lens+métal+sangle, prouvé contre le target goggles du Jak gameplay) ;
  il est BAKÉ dans les verts à l'append → masque baissé en permanence, visage/lipsync 100% vivants
  (le target baké est retiré du runtime, les canaux faciaux inchangés). Device-proven : submits
  found=1, blink actif, cinématique complète sans crash (flicker 0/0 sur 147600 calls).
- À TESTER toi-même : ① regarder les yeux de près (Jak/Daxter/Keira/Samos) — un vrai clignement
  naturel, pas de noir ; ② Keira (les 2 looks) de face en mouvement — plus de clip des bretelles ;
  ③ menu → JAK LOOK → JAK 3 MASKED (lunettes baissées sur le visage, visage animé en ciné) ;
  ④ une cinématique complète — PNJ stables, visages vivants. Illustrations :
  reports/Grecharged-hd-models4/legM-jakm-idle.png + legM-jakm-pan.mp4. Ton œil = verdict final.

### PRÉ-GATE 12:55 [✅ token cycle 4] — blink restauré + bretelles ×2 + MASQUE BAISSÉ
- Prouvé aux compteurs : **clignement visible ×4** avec la paupière DU DONOR (zéro œil noir — mesuré) ;
  **bretelles Keira fixées sur SES DEUX looks** (cause : 4 joints Strap2 en mode orient-copy qui
  jetaient les clés de translation → traversaient le buste) ; **JAK 3 MASQUE BAISSÉ ajouté** (jakm-hd,
  5e option JAK LOOK — astuce : le masque baissé est un blend-target du même modèle, baké en position
  basse, visage toujours animé). deploy_verify PASS.
- À TESTER (toi) : ① le clignement des 4 (naturel ? peau du bon modèle ?) ; ② les bretelles de Keira
  (les 2 looks) ; ③ JAK LOOK → « Jak 3 masque baissé ». 
- CARRY : l'inventaire exhaustif des looks ciné de Jak (prison J2, etc.) = prochain cycle HD, après
  la physique (dis-moi si tu le veux AVANT la physique).
- 🚀 PHASE SUIVANTE : **LA PHYSIQUE** (Grecharged-secondary-motion, périmètre élargi complet).

### 14:00 — Ton verdict cycle-4 : ✔ clignements BONS · bretelles bien meilleures (résiduel par-anim)
· BUG : les 2 looks Jak 3 sont identiques (masque baissé sans effet) — cycle 5 après la physique.

### PRÉ-GATE 15:55 — PHYSIQUE SECONDAIRE M1 (Grecharged-secondary-motion, jiggle/chaînes HD)
- Prouvé aux compteurs (x86 5 legs + device D-MAX/D-OFF, deploy_verify PASS) : chaînes verlet
  ressort-vers-la-pose-animée sur LES 10 LOOKS HD — Keira poitrine (rBoob/lBoob) + cheveux +
  bretelles + lunettes ; Samos barbe/queue/cheveux/bûches/ventre ; Jak cheveux/col/12 lanières/
  pans de tunique ; Daxter (x2) oreilles/joues/queue ; Jak 2/3/masqué cheveux+cornes+sangle ;
  Young Samos. Bornées (5-19 cm max en jeu réel), retour au repos exact (sag Keira = équilibre
  analytique à 1%), zéro NaN, OFF = zéro pas de sim (stock bit-exact).
- À TESTER (toi) : ① Keira dans la hutte de Samos — poitrine/cheveux/bretelles « rien de fou »,
  naturel ? ② Jak en mouvement/saut — lanières + pans de tunique + cheveux vivants ? ③ menu
  OPTIONS GRAPHIQUES : PHYSICS on/off (coupe TOUT en jeu) + PHYSICS DETAIL LIGHT/FULL/MAXIMUM
  (l'échelle se sent ?) ④ chaque look bonus du carousel (tous ont leurs chaînes propres).
- RÉGLAGE : recharged_assets/physics_chains.txt (adb push + changer de LOOK = reload à chaud) —
  dis-moi « plus/moins de X sur Y » et j'itère les paramètres.
- CARRY M2 (conçu, pas encore implémenté) : riders sur modèles STOCK — PNJ à cheveux longs
  Y COMPRIS MAIA (os de chaîne déjà dans les rigs stock, census prouvé), capes de Gol,
  l'archéologue, + les looks ORIGINAL du carousel. Aucune injection d'os nécessaire nulle part.

### 15:55 — PUSH checkpoint PHYSIQUE (ordre owner : MAX+OFF device-verts = go build)
Premier build --physics sur jak-builds. Prouvé device : niveau MAX (sim complète, bornée, zéro
crash/NaN) + toggle OFF (stock intact). EN COURS de preuve : les niveaux intermédiaires (que chaque
cran du menu applique bien SES paramètres) — si tu testes un niveau du milieu et que la perf semble
étrange, c'est la partie en vol.
À TESTER (toi) : menu → toggle PHYSICS + niveau de précision ; le jiggle de Keira (« rien de fou » ?),
la barbe de Samos, les vêtements/lanières/cheveux de Jak — subtilité et cohérence, ton œil tranche.

### PRÉ-GATE 16:25 [✅ token PHYSIQUE] — la phase est validée, le build 15:58 est LE final
- Sim verlet/ressort dans les companions : gravité, contraintes, cônes d'angle, collisions corps
  (gatées par niveau), sécurité anti-NaN (0 déclenchements). OFF = stock bit-exact. Chaînes sur LES
  10 LOOKS (poitrine Keira native — rBoob/lBoob existaient dans le rig ! —, barbe+queue+bûches Samos,
  cheveux+col+12 lanières+pans de tunique+ceinture Jak, oreilles+queues Daxter, etc.).
- BONUS itération : les paramètres (raideur/amorti/gravité/angles par chaîne) sont dans
  recharged_assets/physics_chains.txt, HOT-ÉDITABLE et livré dans le pack — ton feedback de tuning
  s'appliquera sans rebuild complet.
- Ton verdict visuel = la suite du tuning. Phase suivante : CYCLE 5 HD (jakm identique + bretelles
  résiduelles — peut-être déjà réglées par les chaînes physiques ! — + inventaire des looks de Jak).

### 16:40 — Ton verdict physique : cycle 2 spécifié
Conflit faux-vent×physique (clipping vêtements Jak) · cheveux entiers qui bougent (ancrage racine à
verrouiller) · poitrine Keira inerte · lunettes manquantes · BUG menu : Physics Detail ouvre le mesh
browser. Lancement après le cycle 5 HD en cours — dis-moi si tu veux la physique cycle 2 AVANT.

### 16:50 — Principe directeur physique acté : partout où c'est logique, sur TOUT le cast
(vêtements/cheveux/lunettes/binocle Samos/poitrines/fesses/ventres — le pêcheur ! —/chapeaux/objets
suspendus). Méthode : les canaux de fake-motion de ND = la carte des sites à physicaliser.
Extension PNJ = généralisation de la sim aux modèles stock (par vagues, après le cycle 2).

### 19:30 — Ton verdict : Jak3/Jak3-masqué INVERSÉS (swap) · jakf barefoot À RETIRER · prison J2
NICKEL (verrouillé) · bretelles Keira CLOSES. Après swap+retrait -> PHYSIQUE CYCLE 2.

### 22:00 — Cycle 5 CLOS sur parole owner (swap + retrait jakf = trop basique pour un test).
PHYSIQUE CYCLE 2 lancée : conflit faux-vent×physique (clipping vêtements Jak), ancrage des cheveux
au crâne (gradient racine->pointes), jiggle Keira INERTE à réveiller, lunettes de Keira, COLLIDERS
sérieux (capsules suivant les os, rayon des chaînes, résolution de pénétration), BUG MENU « Physics
Detail ouvre le mesh browser ».

## ====== À TESTER AU RÉVEIL (nuit du 06/08) ======
Le framework tourne toute la nuit ; chaque build part AUTOMATIQUEMENT sur jak-builds
(app-jak1-HD-recharged.apk + jak1_hd_assets.zip — prends les deux).
PHYSIQUE CYCLE 2 attendu : jiggle Keira VISIBLE mais sobre · cheveux ancrés au crâne (plus de
chevelure "détachée") · vêtements/lanières de Jak qui ne traversent plus (colliders + audit
pénétration à 0) · faux-vent neutralisé (fin du combat des deux animations) · lunettes de Keira
· fix du menu "Physics Detail" (n'ouvre plus le mesh browser).
Puis (si la nuit le permet) : vague physique cast-complet (PNJ, ventres/poitrines/chapeaux, binocle
de Samos...). Chaque livraison ajoute sa ligne ici.

### PRÉ-GATE 02:30 (06/08) — PHYSIQUE CYCLE 2 (tes 5 défauts du 16:40 + les colliders du 17:35)
Build `--physics` refait, installé et vérifié sur le Redmi (deploy_verify PASS, md5 GAME.CGO +
physics_chains.txt identiques device/local). x86 5/5 legs verts, device D-MAX + D-OFF verts.

- **BUG MENU (E) — CORRIGÉ.** Cause : le câblage indexait la queue du tableau à la main
  (`length-3`) en **oubliant la ligne MESH BROWSER** — la queue fait 4 lignes. Le libellé
  « PHYSICS DETAIL » était donc peint sur le **bouton MESH BROWSER**, et comme le dispatch des
  boutons lit le `name` STATIQUE et jamais le `name-override`, la ligne ouvrait le mesh browser.
  Correctif : les 2 lignes se **localisent toutes seules** (plus aucun offset compté à la main) ;
  preuve permanente au boot `[PHYS-MENU] static audit: toggle=26 detail=27 next-is-meshbrowser=1`.
- **FAUX VENT × PHYSIQUE (A) — CORRIGÉ.** Il n'y avait pas deux écritures : le faux vent de ND est
  dans les **canaux d'animation** des os secondaires, qui arrivaient dans la CIBLE du ressort. Pire
  cas trouvé : les pans bleus de Jak (`shirtL/Rthigh`) rejouaient **tout le balancement de jambe**
  du driver. Maintenant la physique REMPLACE le canal (os remis en pose de repos porté par le
  parent) ; là où le canal est du **jeu d'acteur** (oreilles/queue de Daxter, barbe de Samos) il est
  réinjecté comme simple **force**, jamais comme 2e écriture.
- **CHEVEUX (B) — CORRIGÉ.** La racine était un os libre : elle est maintenant **verrouillée au
  crâne** (aucune intégration, aucune écriture) + gradient racine→pointes. Preuve : `rootdev=0.0000`
  sur TOUTES les fenêtres, x86 et device.
- **POITRINE KEIRA (C) — CORRIGÉ.** Elle n'était pas cassée, elle était **inerte** : 0,8 cm de
  débattement. Maintenant **5,7 cm (x86) / 6,6 cm crête, 4,4 cm moyen (device MAX)**. Le compteur
  global ne pouvait pas le voir (noyé par cheveux/bretelles) → il y a désormais une mesure
  **par chaîne**.
- **LUNETTES (D) — CORRIGÉES, 2 causes.** (1) classées « accessoire » donc coupées au niveau où tu
  jouais ; (2) surtout : les **verres** (87 % de la géométrie) étaient des enfants non simulés — les
  animer aurait **arraché les verres du pont**. Nouvelle passe qui recolle les descendants (elle
  sert aussi à Samos : 10 descendants).
- **COLLIDERS (17:35) — FAITS.** 68 **capsules** qui suivent 2 os animés (torse, hanches, cuisses,
  bras, cou/crâne), épaisseur de la chaîne prise en compte, **friction au contact**, et surtout un
  compteur de **pénétrations résiduelles = 0** partout. Rayons **mesurés** sur les rigs, pas devinés
  (un audit préalable a trouvé les cheveux de Keira **encastrés de 182 unités** dans le torse —
  corrigé avant le build).

**À TESTER (toi)** : ① le menu → « PHYSICS DETAIL » doit ouvrir le **sélecteur LIGHT/FULL/MAXIMUM**
(plus le mesh browser) ; ② Keira dans la hutte — poitrine visible mais « rien de fou » ? cheveux
attachés au crâne ? lunettes qui bougent un peu ? ③ Jak en course/saut — les pans bleus clippent-ils
encore ? ④ chaque cran de précision se sent-il ?
**RÉGLAGE** : tout est dans `recharged_assets/physics_chains.txt` (push + changement de LOOK =
rechargé à chaud). Dis « plus/moins de X sur Y » et j'itère sans rebuild.
**PAS DANS CE CYCLE** (volontaire, ton ordre) : l'extension PNJ/cast complet (poitrines, fesses,
ventres du pêcheur, chapeaux, binocle de Samos, Maia) — c'est la suite, par vagues.

### PRÉ-GATE 02:55 [✅ token PHYSIQUE CYCLE 2] — build DÉJÀ EN LIGNE (poussé 02:02)
Prouvé (x86 5 legs + device D-MAX/D-OFF, deploy_verify PASS) :
- **Bug menu ROOT-CAUSÉ** : le libellé « PHYSICS DETAIL » était peint sur la ligne MESH BROWSER
  (décalage d'un cran, dû à un offset compté à la main — même classe que le bug du menu overhaul).
  Corrigé + garde-fou : un mauvais ordre affiche désormais une erreur FATALE au lieu de mal câbler.
- Faux-vent neutralisé, cheveux ancrés (rootlock+gradient), **jiggle Keira réveillé** (amplitude
  mesurée chest max≈272 / avg≈182), lunettes, colliders réels (**resid=0** = zéro traversée).
- Menu : toggle PHYSICS + PHYSICS DETAIL (LIGHT/FULL/MAXIMUM) persistés.
À TESTER (toi, build jak-builds 02:02) : ① le jiggle de Keira — sobre mais visible ? ② cheveux qui
ne partent plus en bloc ③ vêtements/lanières de Jak qui ne traversent plus ④ menu : PHYSICS DETAIL
change bien la précision (et n'ouvre plus le mesh browser) ⑤ lunettes de Keira.

### PRÉ-GATE 07:25 [✅ token VAGUE 2 — PHYSIQUE SUR TOUT LE CAST] — build en ligne (poussé 06:28)
- La sim est devenue RIG-AGNOSTIQUE : elle ne dépend plus des modèles HD, elle tourne sur les os des
  acteurs stock. **458 rigs scannés** ; chaînes déclarées par nom.
- Trouvailles concrètes du recensement : tresses+sangles de chapeau de la géologue, moustaches +
  haut-de-forme + cravates + **VENTRE du maire**, **ventre du pêcheur**, barbes des sages, les os
  littéralement nommés « Dangler » de Klaww… Note honnête : **la binocle de Samos n'a AUCUN os**
  (74 joints, aucun pour l'oculaire) → non animable telle quelle, documenté.
- Preuves device : rigs-seen=27 en scène, **rootdev-bad=0** (rien de détaché), **resid=0** (rien ne
  traverse), deploy_verify PASS.
À TESTER (toi) : ① promène-toi au village et regarde les PNJ (le maire, la géologue, le pêcheur) —
cheveux/moustaches/ventres qui bougent ? ② Keira/Jak/Samos comme prévu au cycle 2 ③ menu PHYSICS
DETAIL (LIGHT/FULL/MAXIMUM) ④ toggle OFF = tout redevient stock.

### PRÉ-GATE 14:15 [✅ token CYCLE 3 + 3b/3c/3d] — APK + assets EN LIGNE (jak1-rtlight-wip, 14:12)
deploy_verify PASS sur eae4df44 (HEAD e62938ffbc), rapport 13:55, x86 7/7 + device 3/3, 0 crash.
Ce qui a changé, point par point (tes retours du 06/08) :
- Oreilles de Daxter : le `rootlock` binaire est SUPPRIMÉ — c'était la CAUSE du cran, pas un réglage.
  Son oreille n'a que 2 os (earBaseL->earMidL), donc profil 0.55 → 1.00 (marche de 0.45, contre
  0.00 → 1.00 avant). Sa queue (4 os) : 0.15/0.43/0.72/1.00, marche max 0.29. **Ton œil juge.**
- Col de Jak (intro, allongé) : jitter d'intro 72 → 35, projection amortie, plus de réinjection de
  vitesse, état de repos engagé. `stickmax` ≤ 7 partout.
- Lunettes de Keira : la saisie est détectée (pic à 1.390 de longueur de chaîne) et la physique se
  suspend puis reprend. Chaîne mesurée à 218,1 unités (elles étaient inertes).
- Poitrines : `mass=2.6` — Keira (2 looks, 6 variantes), Maia, la bird lady. 490,6 unités en
  gameplay / 628,9 sur le rig stock (272,4 au cycle 2). Objectif : de la MASSE, pas de la gelée.
- Maia + Gol : 10/10 et 12/12 chaînes actives dans l'intro, `resid=0` (les cheveux ne traversent
  plus). Oreilles ajoutées à tout le cast, y compris lurkerpuppy / swamp-rat / lightning-mole / Klaww.
À TESTER : ① le cran des oreilles de Daxter ② le col de Jak dans l'intro (allongé, gros plan)
③ le jiggle de Maia et Keira — masse ou gelée ? ④ les lunettes de Keira quand elle les saisit
⑤ Maia au spawn vue de loin ⑥ toggle physics OFF = tout redevient stock.
PAS FAIT (dit honnêtement) : l'anneau du plastron et la boucle du dos de Jak, + la binocle de Samos
— aucun os dans les 458 rigs, il faut les injecter au prep HD (lot séparé).

### BUILD INTERMÉDIAIRE 19:05 — "HANG" SEULEMENT (à ta demande) — APK en ligne, PAS le cycle 4 complet
CE QU'IL CONTIENT : la direction de repos dictée par la GRAVITÉ (`hang=`) sur 292 chaînes —
poitrines 14/14, col 6/6, chemise 4/4, cheveux 28/28, oreilles 84/84, lanières 50/50. C'est la
réponse à ta question "as-tu défini un haut et un bas". Parser `hang`/`swing` présent dans le libgk.
CE QU'IL NE CONTIENT PAS : la baisse de l'hystérésis (freering mesuré mais pas encore corrigé),
ni la mesure de dérive à vide. Le cycle 4 complet suivra.
MESURES DEVICE SUR CE BUILD EXACT (jambe D-INTRO) :
  * Maia : `push=66617` — le système de collision SE DÉCLENCHE ENFIN (il était à 0, d'où tes cheveux
    qui traversaient). 10 chaînes actives, `resid-bad=0`. À vérifier en jeu.
  * Gol : `push=0` — SES collisions ne se déclenchent toujours pas. Défaut connu, non corrigé.
  * Jak : `resid-bad=11` — pénétration résiduelle sur 11 fenêtres (marge de rayon fautive, le worker
    l'annule dans le cycle en cours). Donc du clipping sur Jak est ATTENDU sur ce build.
  * Poitrine Keira : 738,1 unités.
⚠️ TAILLE : 1,0 Go au lieu de ~580 Mo — c'est de l'espace mort de packaging Gradle (défaut connu,
pas du contenu). Le build du cycle 4 sera repacké propre.

### PRÉ-GATE 23:40 [✅ token CYCLE 11 — LE BLOCKER EST LEVÉ] — APK + pack EN LIGNE
deploy_verify PASS (HEAD 6cab2acb0d), 0 crash, 0 ligne d'échec dans le rapport, cliquet satisfait.
LE BLOCKER : `resid-bad = 0 sur 109 fenêtres`, avec **28 800 tests pendant-tissu réellement
exécutés** — et le contrôle positif a bien tiré : run ARMÉ `inject=140` sur chaque chaîne =>
`injected=15274`, `push=39066`. Le zéro n'est donc pas creux. Pire résidu restant : 1,11 unité,
soit 27 micromètres sur un personnage de 2,3 m.
ACQUIS MESURÉS : restdevA 948 -> 5,08 (retour à la forme du modèle) ; lenmin 0,9951 / lensim 0,9998
(plus aucun écrasement) ; autorité anim qui se rend (engage==release) ; Maia sortie des fautifs.
⚠️ CE QUI N'EST PAS CORRIGÉ, ET QUE TU VERRAS ENCORE :
  * la FORME de la poitrine : `couple=3.6` est toujours une déviation POSITIONNELLE, donc la
    « giga pointe / quasiment plat » persiste. La règle rotation-au-lieu-de-translation est écrite
    dans le solveur mais pas branchée sur ce paramètre. C'est le premier sujet du prochain cycle.
  * les lunettes qui tombent pendant que la main les tient (Sandover, boucle Zoomer).
  * Maia sur-amortie (amortissement 0,14 vs 0,26 chez Keira — inversé par rapport à l'intention).
À TESTER : ① est-ce que quelque chose traverse encore un corps, sur N'IMPORTE quel personnage ?
② les pans de veste de Jak restent-ils chacun sur leur jambe ? ③ cheveux de Maia dans son corps ?
④ toggle physics OFF = tout redevient stock.

---

## FOLIAGE WIND — ROUND 2 (2026-08-08 03:2x) [À TESTER] — validator PASS, HEAD 25987e18e4
Ton verdict round 1 : « on voit aucune feuille qui bouge, aucun palmier, nada ! »

**LA CAUSE, mesurée et pas devinée — et ce n'était PAS l'amplitude.** Le vent TIE d'origine de jak1
n'est pas faible, il est GLACIAL : il courbe déjà la cime d'un palmier d'environ 1,2 m, mais il
oscille à **0,051 Hz, soit une période de VINGT SECONDES**. Les palmiers n'ont jamais été immobiles :
ils étaient *penchés*, et dérivaient bien trop lentement pour que l'œil lise ça comme du mouvement.
Le round 1 ne faisait que multiplier ce même terme par 3 — ce qui multiplie la courbure ET la vitesse
ensemble, donc ça ne pouvait pas corriger la fréquence, la seule chose qui était cassée. Pire : à x3
la cime se courbait de 3,3 à 5,3 m (une tempête) sans bouger pour autant.

**CE QUI EST LIVRÉ.** Multiplicateur remis à 1,0 (on laisse le vent du jeu tranquille) et tout le
mouvement vient d'une brise procédurale qui, elle, oscille vraiment ; spectre recentré sur 0,45 Hz ;
frémissement des palmes par sommet. Mesuré sur device, même run, même pose, à Sentinel Beach :
mouvement par image **x6,7 à x7,9 par rapport au jeu d'origine**, période **20 s -> 3,2 s**, et la
courbure REDESCEND de 0,187-0,300 (round 1) à 0,079-0,101. Plus de mouvement, moins de flexion.
Village1 confirme (x5,4-5,7). OFF = strictement l'original (ratios exactement 1,000 au runtime).

**À TESTER :**
① Sentinel Beach : avance vers les palmiers et RESTE IMMOBILE. Les cimes bougent-elles visiblement
   sur un cycle de ~3 s, et les palmes frémissent-elles au lieu que l'arbre glisse en bloc ?
② Brise ou tempête ? La cime est maintenant à ~1,5 m de la verticale sur un palmier de 17,5 m (8 %
   de sa hauteur). Trop ? Pas assez ? Dis juste le sens, j'ai un réglage direct.
③ Sandover : les 65 palmiers `palm-02` bougent. Les 27 plus GRANDS (`palm-01`) NE bougent pas — voir
   le trou ci-dessous, ce n'est pas un bug de ce build.
④ Buissons/arbustes : frémissement plus fin et plus rapide. Dosage ?
⑤ OFF doit être exactement le jeu d'avant.

**⚠️ TROU DE COUVERTURE CONNU, NON CORRIGÉ, C'EST TON ARBITRAGE.** Recensement complet des 218
prototypes TIE : `palm-01.mb` porte stiffness 0,1 dans BEA.DGO et 0,0 dans VI1.DGO — le MÊME
prototype de 23,9 m, animé à la plage et figé au village pour 27 instances. Et la jungle n'a AUCUN
vent TIE du tout (toute la canopée est statique : 153 + 121 + 74 + 21 instances). C'est une
incohérence d'auteur dans les données d'origine, pas un bug du moteur : l'appartenance au vent est
cuite dans les .fr3. La corriger impose de ré-extraire les niveaux, ce qui déplace les comptes de
draws/sommets et touche l'empreinte du bake PBR .meshweld — donc je ne l'ai pas fait tout seul dans
une phase dont le défaut annoncé est « rendre la brise visible ». C'est chiffré et prêt en round
séparé si ça te gêne à l'œil.

**PAS PROUVÉ, dit honnêtement :** le compteur fps est quantifié par pas de 60 images et ne sait pas
trancher le « <= 0,5 fps » demandé (OFF et ON lisent tous les deux 18,00 dans le même run) ; et le
gel de la brise quand le jeu est en pause est codé mais jamais testé (paused=0 sur tous les
échantillons).

**Réglages à chaud, sans rebuild** (`adb shell setprop`, relu en ~2 s) :
`debug.opengoal.foliage.tie_amp` (force de la brise, 0.12) · `.frond` (frémissement des palmes, 0.14)
· `.shrub_amp` (buissons, en mètres, 0.16) · `.tie_mult` (amplifie le vent D'ORIGINE ; 1.0 = neutre,
le round 1 livrait 3.0).
Clips pour ton œil uniquement (caméra volontairement figée, donc tout ce qui bouge à l'image EST le
feuillage) : `.autoport/reports/Grecharged-foliage-wind2/device/fw2-beach-{OFF,ON-default}.mp4`,
`fw2-beach-ON-strong-frond0.22.mp4`, `fw2-village1-ON-default.mp4`.

### PRÉ-GATE 03:45 [✅ token VENT SUR LE FEUILLAGE, ROUND 2]
deploy_verify PASS (HEAD 09034051cf), 0 crash, OFF==stock prouvé.
LE DIAGNOSTIC, ET IL EST BON : « le vent de jak1 n'a JAMAIS ete faible, il etait GLACIAL ». Le jeu
d'origine plie deja une couronne de palmier d'environ 1,1 m — mais 55 % du budget d'amplitude
partait dans un terme a 0,14 Hz, soit une inclinaison de 7 SECONDES. Invisible a l'oeil, pas parce
que c'est petit, parce que c'est LENT. Le round 1 avait attribue ca a l'amplitude : c'etait la
PERIODE. Correctif : depenser l'amplitude ou l'oeil la voit (flutter de fronde 0,14 -> 0,22,
reglable a chaud par propriete debug, sans rebuild).
⚠️ TROU ASSUME ET ANNONCE, C'EST TOI QUI ARBITRES : dans village1, 27 des palmiers LES PLUS HAUTS
(palm-01, 23,9 m) sont GELES pendant que les 65 palm-02 a cote d'eux bougent. Le meme prototype
porte stiffness=0.1 dans BEA.DGO et stiffness=0.0 dans VI1.DGO — incoherence d'auteur du jeu
d'origine, et l'appartenance au vent est BAKEE dans le .fr3, aucun chemin runtime. Idem la JUNGLE
entiere (canopee, branches, troncs : 0 prototype de vent) et les arbres de fond.
A TESTER : ① les palmiers de la plage bougent-ils de facon VISIBLE maintenant ? ② le toggle OFF
rend-il bien le comportement stock ? ③ veux-tu qu'on force le vent sur les 27 palmiers geles et sur
la jungle (ca demande de re-baker les .fr3) ?
