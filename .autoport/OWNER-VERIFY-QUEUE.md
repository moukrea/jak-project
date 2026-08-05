# OWNER VERIFY QUEUE — à tester au réveil (2026-08-04)
# Protocole nuit (owner ~01:55) : le framework avance en continu ; le superviseur fait une PRÉ-GATE
# humaine (vérifie ce qu'il peut : device, logs, captures grossières) et pose le token owner-ok pour
# ne pas bloquer la chaîne. TA vérification reste le verdict FINAL — tout item pré-gaté ici doit être
# re-testé par ton œil ; on rouvre ce qui ne te va pas.

## Légende
- [PRÉ-GATÉ ✅/⚠️] = passé par la pré-gate superviseur (✅ = confiant, ⚠️ = réserves notées)
- [EN COURS] = le framework bosse encore dessus
- [À TESTER] = prêt pour ton verdict

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
