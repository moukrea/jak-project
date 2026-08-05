# Grecharged-hd-models4 — HD MODELS M2 : remplacements PRINCIPAUX Daxter / Keira / Samos

## PRÉREQUIS ABSOLU
NE COMMENCE PAS tant que **Grecharged-hd-models3** (M1 = Jak seul, anim-retarget) n'est pas
**owner-accepté** (le HD Jak s'affiche correctement en jeu sur device, verdict de l'œil de l'owner).
M2 réutilise EXACTEMENT le même pipeline que M1 ; tout fix trouvé en M1 (positionnement/culling,
timing des os, ordre matriciel, chargement d'art-group externe) s'applique tel quel ici.

## LA ROADMAP DE L'OWNER (2026-08-03, verbatim consolidé — NE PAS dévier)
Toujours des modèles de **CINÉMATIQUES** (les plus détaillés). Sourcing par personnage :

1. **Daxter** = le modèle des **cinématiques de JAK 3, SANS pantalon**.
   - L'owner a VÉRIFIÉ que Daxter ne change pas de look entre Jak 1, 2 et 3 (il ne gagne un pantalon
     qu'à la toute fin de Jak 3 en cinématique). **Ne perds pas de temps à re-vérifier.**
   - Donc le plus qualitatif pour le Daxter de Jak 1 = cinématique Jak 3 (version SANS pantalon !).
2. **Keira** = le modèle « cinématique » de la **TOUTE PREMIÈRE cutscene de Jak 2**.
   - Après cette première cinématique elle change légèrement (sandales → bottines). La première
     version est donc la plus proche de son look Jak 1, au max de détail.
3. **Samos** = le modèle « cinématique » de **Jak 3** (il ne change pas de look entre les jeux,
   celui du 3 est probablement le plus détaillé).

C'est TOUT pour les remplacements principaux (avec le Jak de M1 : les 4 personnages couverts).
Les looks alternatifs (bonus) sont la phase SUIVANTE (Grecharged-hd-models5), pas celle-ci.

## MÉCANISME (identique à M1 — réutilise, ne réinvente pas)
Par personnage : rip du modèle cinématique (fr3_to_gltf foreground export sur le bon niveau du
decompiler_out de jak2/jak3 — dumps présents : iso_data/jak2 + iso_data/jak3) → prep GLB
(scripts/shell/prep_hd_actor_glb.py, garde le squelette HD) → art-group via build_actor (nom COURT
<16 chars, ex. dax-hd / keira-hd / samos-hd — limite fakeiso) → table k→e par personnage
(scripts/shell/retarget_fill_table.py, avec le driver jak1 correspondant : sidekick pour Daxter, etc.)
→ append merc au fr3 du niveau approprié (hd_merc_swap add ; Daxter=GAME.fr3/COMMON,
Keira/Samos=village1.fr3) → companion process par personnage (généralise jak-hd.gc ; le driver de
Daxter est `sidekick`, ceux de Keira/Samos sont leurs actors respectifs) → réglage/flag existant
(recharged-enhanced-models?).

## RÈGLES QUI S'APPLIQUENT (non négociables)
- **IP Naughty Dog** : assets dérivés jak2/jak3 = pack EXTERNE uniquement, gatés sur les dumps,
  JAMAIS dans l'APK/le binaire/git (recharged_assets/hd_* est gitignoré).
- **PAS de re-rig** (le REPLACE des poids = le « carnage » rejeté). Anim-retarget uniquement.
- Preuve device : le personnage HD est VISIBLE et suit ses animations en VRAI gameplay (l'owner est
  le juge visuel ; pas de « pas de crash » = validé). Ne livre RIEN d'invisible/cursed.
- Écris/adapte le validator de CETTE phase au démarrage (celui référencé est celui de M1).

## PROGRESSION AUTORISÉE (owner protocol) 2026-08-04 09:00 — M1 pré-gaté par le superviseur
M1 (hd-models3) validé + pré-gaté : défauts 5+6 corrigés (owner-confirmés), long jump INNOCENTÉ
(bug overlay tactile toggle-indépendant, piste séparée), l'owner re-vérifie depuis OWNER-VERIFY-QUEUE.md.
CARRY-OVERS dans TON scope (ils font partie de la généralisation multi-personnages) :
1. **Jak INVISIBLE au logo ND** : la suppression Merc2 d'eichar-lod0 s'applique à l'acteur du logo
   alors que le companion ne couvre que *target* → supprimé sans remplaçant. Le fix M4 = la
   suppression ne s'applique QUE quand un companion couvre CET acteur cette frame (per-actor
   coverage), ce qui est exactement le mécanisme dont Daxter/Keira/Samos ont besoin (leurs drivers
   sont des acteurs non-*target*). Règle owner : « le modèle choisi PARTOUT » (logo, cinématiques, jeu).
2. M1 polish encore ouvert (l'owner testera ; rouvrable) : yeux blancs (eye_id), gap cran→cheveux
   (on voit l'intérieur de la tête), visage inanimé (blerc), clipping vêtements. Si tes mécanismes M4
   règlent l'un d'eux au passage (eye_id du pipeline d'append, blerc généralisé), prends-les.

## ============================================================
## VERDICT OWNER 2026-08-04 ~10:5x (build M4 sur son Honor) — CYCLE DÉFAUTS 2 = la barre maintenant
## ============================================================
Les 3 primaires rendent, mais la qualité n'y est pas. Verbatim owner classé par MÉCANISME (il a
lui-même le bon diagnostic : « le transfert par liens de bones entre l'original et la version HD
n'est pas tip top ») :

### A. YEUX / VERRES BLANCS — SYSTÉMIQUE (3 personnages)
- Jak : yeux blancs (connu M1). Keira : yeux blancs. Samos : les VERRES de ses lunettes sont blancs
  au lieu de laisser voir les yeux. => le binding eye_id (texture œil dynamique 0xefffff00|id) manque
  pour TOUS les mercs appendés. UN fix pipeline (append + eye_id correct par personnage) règle les 3.

### B. VISAGES TOTALEMENT IMMOBILES EN CINÉMATIQUE — SYSTÉMIQUE (tous)
- Jak, Keira, Daxter, Samos : visage figé. => les companions ne pilotent AUCUN canal facial (blerc).
  Investiguer le mirror des canaux blerc du driver vers les blend-targets du modèle HD (les modèles
  ciné jak2/jak3 ont leurs propres targets). Si le mapping facial jak1->jak2/3 ne mappe pas,
  documenter honnêtement la limite ET voir ce qui est récupérable (au moins la mâchoire parlante).

### C. GÉOMÉTRIE MANQUANTE — CLASSE RIP/PREP/APPEND (2 cas)
- **Daxter : PAS DE MÂCHOIRE — cursed, dents qui flottent dans le vide** (le même symptôme que le
  vieux re-rig ! le rip/prep du daxter-highres perd le draw de la mâchoire, ou ses verts pèsent sur
  un joint non mappé). PRIORITÉ 1 de ce cycle.
- Jak : gap cran->cheveux (connu M1, on voit l'intérieur de la tête). Même classe : compter les draws
  donor vs appendé, et vérifier les joints des verts de la pièce manquante.

### D. PRÉCISION DU MAPPING k->e — CLASSE LIENS D'OS (3 cas)
- Keira : DOIGTS « cassés » en cinématique (joints de doigts non mappés / mal mappés -> repos).
- Samos : le bas de sa BARBE pointe vers l'avant (joints de barbe non mappés -> pose de repos).
- Jak : clipping vêtements (connu M1). => auditer la table k->e par personnage : lister les joints
  0xFF (non mappés) et leur impact visuel ; les chaînes doigts/barbe/cheveux ont besoin d'un mapping
  ou d'un fallback qui suit le parent mappé le plus proche (PAS le repos world).

### E. RENDU FOURRURE — TRANSPARENCE (1 cas)
- Daxter : on voit AU TRAVERS de sa fourrure (alpha/draw-order/backface du merc appendé).

### F. SOURCING KEIRA — À VÉRIFIER
- Le modèle livré a des BOTTINES, pas des sandales. L'owner : « il est possible que dans la première
  cinématique de Jak 2 elle ait déjà des bottines, mais pas sûr ». => vérifier s'il existe une
  variante sandales dans les rips jak2 (autres niveaux/cutscenes) ; si la 1ère ciné a déjà des
  bottines, le dire à l'owner (le modèle actuel est alors le bon) ; sinon sourcer la bonne.

Positif owner : Keira « la moins buggée », Samos « vraiment pas mal » à part verres/barbe.
ORDRE : C-Daxter (mâchoire, cursed) > A (yeux, un fix pour 3) > D (doigts/barbe/mapping) > E (fourrure)
> B (visages/blerc) > F (sourcing Keira). Preuves device par personnage, l'owner juge.

### CORRECTION OWNER 2026-08-04 ~11:05 sur la classe B (visages) — LA BARRE EST : TOUTES LES ANIMS
« Au minimum la mâchoire qui parle... Non faut TOUTES les animations ! »
=> Le fallback mâchoire-seule N'EST PAS la cible, et « documenter la limite » N'EST PAS une sortie
acceptable pour cette classe. La barre : le visage HD reproduit TOUTES les animations faciales du
driver (blerc/blend-targets complets, yeux compris — la classe A eye_id et la classe B convergent ici).
Investiguer à fond le pipeline facial : comment jak1 anime les visages (blerc channels sur le driver),
ce que portent les modèles ciné jak2/jak3 (leurs propres blend-targets, a priori PLUS riches), et le
mapping canal→target par personnage. Si un canal donné n'a réellement AUCUNE contrepartie dans le
modèle HD, le documenter cas par cas avec la preuve — pas d'abandon de classe entière.

## ============================================================
## OWNER 2026-08-04 ~11:30 — LA DÉFINITION DU BACKPORT CHANGE (à encoder dans le pipeline même)
## ============================================================
« Je comprends même pas pourquoi t'as pas fait la correspondance des bones VISAGE d'entrée. Si on
veut backporter des modèles on veut qu'ils soient BIEN SUPPORTÉS, pas juste leur corps. »
=> DÉFINITION OF DONE d'un personnage backporté, désormais NON NÉGOCIABLE et intégrée au pipeline
(pas un « polish » d'après-coup) :
1. Corps : squelette + poids (déjà fait) ;
2. **VISAGE : correspondance COMPLÈTE d'entrée** — os faciaux dans la table k->e (mâchoire, yeux,
   sourcils, joues… tout ce que les deux rigs portent) ET mapping des canaux blerc/blend-targets
   driver->HD ; toutes les animations faciales passent ;
3. Yeux fonctionnels (eye_id) ;
4. Aucune géométrie perdue (draws donor == draws appendés, mâchoire de Daxter incluse) ;
5. Mains/extrémités mappées (doigts de Keira, barbe de Samos — pas de chaînes en pose de repos).
Le générateur de table k->e (retarget_fill_table.py / build de chaque personnage) doit ÉCHOUER
BRUYAMMENT si des os faciaux/doigts du donor restent non mappés sans justification explicite,
au lieu de les laisser silencieusement à 0xFF. Un personnage qui ne satisfait pas TOUT ça n'est
pas « backporté avec des défauts », il n'est PAS backporté. Ceci s'applique au cycle défauts 2
(les 4 personnages actuels) ET à M5 (chaque look bonus arrive complet d'entrée).

## PROTOCOLE DE RAPPORT PAR ATTEMPT (superviseur 2026-08-04 14:55 — évite le faux-STUCK)
Le halt "same fingerprint 3x" venait de rapports jamais rafraîchis : chaque attempt DOIT réécrire
`reports/Grecharged-hd-models4/report.txt` AVANT de se terminer, avec l'état HONNÊTE du cycle 2 :
RESULT: WIP + ce qui est FAIT (avec preuves) + ce qui RESTE. Un rapport frais mais incomplet fera
échouer le validator sur la SUBSTANCE manquante (fingerprint différent à chaque progrès = pas de
faux-stuck) ; un rapport périmé lit comme un attempt mort et 3x = halt du framework. Ne termine pas
un attempt sans ce refresh.

## ============================================================
## VERDICT OWNER 2026-08-04 ~19:00 (build cycle-2 testé sur son Honor) — CYCLE 3
## ============================================================
ACQUIS (owner) : « les personnages sont enfin VIVANTS » — visages animés sur les 4 (Jak animé,
Daxter bien animé, Samos quasi parfait, Keira la mieux des quatre). NE PAS RÉGRESSER LÀ-DESSUS.

### PRIORITÉ 1 — RÉGRESSION : le clignotement des PNJ en cinématique EST REVENU
Disparition/réapparition des PNJ pendant les cinématiques — c'était CORRIGÉ (d4fddfd245, owner-confirmé
défaut 5) et le cycle 2 l'a RÉINTRODUIT. Suspects : le remaniement per-actor de la suppression Merc2
du cycle 2, ou l'épuisement d'un pool par frame avec 4 companions + blerc slots actifs en scène
(buckets/bones/adgifs high-water pendant une cutscene chargée). Bisecter contre le build cycle-1 si
besoin — c'est régression-class, ça bloque tout token.

### Par personnage (cycle 3) :
- **Daxter** : (a) bas du visage toujours absent/transparent ; (b) corps PLEIN DE PETITS TROUS,
  pire à la TÊTE (on voit au travers). Hypothèse owner plausible : la fourrure Jak 3 = astuce de
  rendu (shells/alpha-test/backface) MAL backportée → trous/transparence. Étudier comment jak3
  rend daxter-highres (draw modes/alpha des effets fourrure) et porter le mode de rendu correct
  (alpha-test vs blend, double-face, ordre).
- **Jak** : gap bandeau/cheveux TOUJOURS là (classe C, jamais fixé) + clipping bleu/blanc TOUJOURS
  (classe D). Ces deux-là ont survécu à 2 cycles — les traiter pour de bon.
- **Samos** : la barbe CLIP dans le corps sur certaines anims + le BOUT pointe toujours vers l'avant
  (chaîne de barbe : mapping partiel — le bout non mappé reste en repos → régler par mapping du bout
  sur le parent le plus proche ou ajout des joints manquants à la table).
- **Keira** : quand elle CLIGNE des yeux → yeux NOIRS bizarres (interaction paupière blerc × texture
  d'œil : le blink ferme la paupière mais la texture/UV derrière est mauvaise, ou l'eye-remap pointe
  un slot qui devient noir pendant le blend). La mieux des 4 sinon.
Rappel : preuves device par classe + captures/vidéo, l'owner juge. Livraison jak-builds.

## ============================================================
## OWNER 2026-08-04 ~20:05 (intro cutscene, build cycle-2) — CRASH + 2 précisions yeux
## ============================================================
### PRIORITÉ 0 — CRASH en cinématique d'intro (au-dessus de tout, y compris la régression PNJ)
L'intro CRASHE juste après la réplique de Daxter humain « this place just gives me the creeps » —
hypothèse owner : au moment où le modèle Daxter OTTSEL se charge (la piscine d'éco noire / la
transformation). Suspects : le companion dax-hd qui spawn/attache sur l'acteur ottsel de la cinématique
(un acteur ciné ≠ le sidekick normal — driver inattendu, jgeo différent, index hors bornes ?), ou un
pool par frame qui déborde à ce moment (la scène charge les deux Daxter). NOTE harnais : ta preuve
leg3 (80 s) n'atteint PAS ce moment — étendre la preuve à L'INTRO COMPLÈTE, transformation incluse,
jusqu'au retour gameplay. Récupérer files/gk_crash.txt après repro.
### Yeux (complément aux classes A/blink) :
1. **Les paupières de JAK sont broken comme celles de Keira** (le blink-noir touche Jak aussi —
   la classe « blink » est générale, pas Keira-only).
2. **PUPILLES : l'owner a raison** — l'eye-remap actuel branche les yeux HD sur le renderer d'yeux
   jak1 ⇒ les pupilles rendues sont celles de JAK 1 (d'origine), PAS celles du modèle ciné Jak 2.
   Owner : « si c'est les pupilles de Jak 1, c'est pas bon ! ». FIX : porter les textures d'iris/œil
   du DONOR (jak2/jak3) dans le chemin d'yeux des modèles HD (par personnage), pas juste re-lier le
   slot jak1. La classe A n'est PAS close tant que les pupilles ne sont pas celles du donor.

## ============================================================
## CORRECTION OWNER 2026-08-04 ~22:00 — REDÉFINITION DU DÉFAUT PNJ + INTERDICTION DÉFINITIVE
## ============================================================
### 1. Le défaut PNJ n'est PAS du "flicker" — redéfinition exacte (owner) :
Les PNJ sont visibles au DÉBUT de la cinématique, puis d'un coup DISPARAISSENT de la vue (SANS
changement de caméra), puis RÉAPPARAISSENT plus tard dans la cinématique. Ce sont des FENÊTRES DE
DISPARITION LONGUES (secondes), pas un clignotement rapide. ET : « c'est un problème qu'on a déjà eu
sur la phase des personnages HD et que tu as déjà réglé » — NE PAS réinventer : faire l'archéologie
git de la solution PRÉCÉDENTE (le fix per-actor/TTL de la suppression Merc2 d4fddfd245 et le travail
d'invisibilité merc antérieur), comprendre ce que le cycle 2 a défait, et RE-appliquer/adapter.
### 2. INTERDICTION DÉFINITIVE (owner, "pour toujours") : AUCUNE campagne de preuve VISUELLE
« C'est des preuves visuelles… ça ne marchera jamais ou va irrémédiablement finir en truc qui échoue
constamment, irreproductible ou faux vert comme à chaque fois. J'aimerais que toi, le framework,
workers et autres arrêtiez de faire ça… POUR TOUJOURS. »
=> Le "flicker détecteur" basé captures/vidéo/pixels est ABANDONNÉ. La preuve du défaut PNJ (et de
TOUT défaut de visibilité) = COMPTEURS CÔTÉ RENDERER + state dumps, jamais des pixels :
  - instrumenter par ACTEUR le nombre de soumissions merc par frame (Merc2, par nom de modèle) ;
  - le bug = une fenêtre > N frames où les submits d'un acteur censé être en scène tombent à 0
    pendant la cinématique (sans hidden légitime) ; le fix prouvé = 0 fenêtre de ce type sur la
    cinématique complète (log compteurs, greppable, reproductible) ;
  - les captures/vidéos ne servent QUE d'illustration pour l'owner, JAMAIS d'instrument de
    validation. Le validator ne doit JAMAIS exiger des captures comme preuve.
Ceci s'applique à TOUTES les preuves de cette phase (crash intro = gk_crash.txt + exit-info ;
fourrure/gap = comptage de draws/verts par effet ; yeux = binding/texture id dans les logs).

## ============================================================
## VERDICT OWNER 2026-08-05 ~08:15 (build cumulé menu+cycle-3) — CYCLE 4 (2 items) après M5
## ============================================================
VICTOIRES ACTÉES (à VERROUILLER, zéro régression tolérée) : clipping vêtements Jak DISPARU ·
DAXTER PARFAIT (trous/tête/mâchoire réglés) · barbe Samos réglée · YEUX = les versions HD (iris
donor OK) · PNJ stables en cinématique (« vraiment beaucoup, beaucoup mieux »).

### CYCLE 4 — deux items :
1. **LE CLIGNEMENT A DISPARU** : « ils ne clignent plus vraiment des yeux… ça bouge mais j'ai
   l'impression qu'ils clignent pas, c'est un peu bizarre. » Cause quasi certaine : le fix
   blink-noir (CYCLE3-KEIRA : EyeRenderer SKIPPE le blit de paupière sur les slots HD) a sur-corrigé
   — le blit de paupière ÉTAIT le mécanisme de clignement de jak1 ; le skipper a tué le noir ET le
   blink visible. FIX ATTENDU : un vrai clignement pour les yeux HD — soit un blit de paupière avec
   la TEXTURE de paupière du donor (peau, pas du noir), soit piloter les blend-targets de paupière
   du modèle HD (les modèles ciné en ont probablement) depuis le canal blink du driver. Le blink
   doit redevenir VISIBLE et naturel sur les 4 personnages.
2. **Les bretelles de Keira clippent au travers de l'AVANT de son corps** (nouvelle observation
   owner). Chaîne bretelles : vérifier le mapping (strap chains étaient en mode-3/0.103-scale au
   cycle 3) — probablement des joints de bretelle qui suivent mal le buste -> clip frontal.
Timing : cycle 4 se lance APRÈS la clôture M5 (les looks bonus héritent des mêmes fixes).

## VERDICT OWNER 2026-08-05 ~10:3x sur M5 : « impeccable, ça fonctionne parfaitement ! » — 2 suites
1. **CYCLE-4 item 2 élargi** : le clip des bretelles de Keira touche AUSSI son look alternatif
   keira3-hd (Jak 3) — le fix de la chaîne bretelles doit couvrir LES DEUX looks (keira-hd ET
   keira3-hd ; vérifier les tables k->e des deux).
2. **CYCLE-4 item 3 (nouveau, owner)** : intégrer le look bonus supplémentaire **Jak 3 MASQUE
   BAISSÉ** — il existe un modèle de CINÉMATIQUE de Jak 3 où Jak porte son masque/lunettes baissé
   sur le visage. Sourcing : chercher dans les rips jak3 la variante highres masquée (autour des
   art-groups jakc-*/jak-* des cutscenes ; l'owner confirme qu'elle existe en ciné). L'intégrer
   comme 4e option du carousel JAK LOOK (ORIGINAL / HD / JAK II / JAK 3 / JAK 3 MASQUÉ), complet
   d'entrée (définition-of-done : visage/blerc — noter que le masque peut couvrir une partie des
   canaux faciaux, documenter ce qui s'applique —, yeux si visibles, géométrie complète, extrémités).
   Même mécanisme, même gating menu (grisage master/enhanced).

## CORRECTION OWNER 2026-08-05 ~11:00 — QUIPROQUO sur « masque baissé » (item 3 du cycle 4)
Le look jak3-hd DÉJÀ livré (jakc) porte le masque SUR le visage (nez+bouche couverts) — c'est celui
qu'on A. Ce que l'owner veut en PLUS : la variante cinématique de Jak 3 où le masque est **BAISSÉ
AUTOUR DU COU** — VISAGE ENTIÈREMENT DÉCOUVERT (le masque pend en écharpe). « Masque baissé » =
tiré vers le bas, PAS rabattu sur le visage.
=> Sourcing corrigé : chercher dans les rips jak3 la variante highres VISAGE NU avec le masque au
cou (les cutscenes de Jak 3 alternent les deux états ; suspects : les autres variantes
jakchires-*/jakc-* — precarmor vs autres — comparer les draws visage/écharpe). Le carousel JAK LOOK :
ORIGINAL / HD / JAK II / JAK 3 (masque sur le visage, l'actuel) / JAK 3 MASQUE BAISSÉ (le nouveau).
Bonus : visage découvert => les canaux faciaux complets s'appliquent pleinement à cette variante.
