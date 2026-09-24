# La lumiere cle n'est pas toujours un soleil — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. pc-set-pbr-sky-sun! est pousse sans garde et ecrase la lumiere cle : dans 16 niveaux sur 20 la clef du monde suit un soleil que le joueur ne voit pas. SPEC 3.2, 3.3 et l'annexe A.

APPRIS PAR lighting-bake (24/09, reports/lighting-bake/FINDINGS.txt) — a lire AVANT de coder :
* SPEC §5.2 : la formule baked = [amb*skyvis + lgt*N.L*vis]*art ne decrit PAS le bake de ND (village1 : mediane de art 3,45, 76 % hors bornes) ; avec l'ambiante PLATE (sans skyvis) mediane 0,954 et 2,5 % hors bornes.
* La palette B est verifiee au chargement puis JETEE : aucun renderer ne la lit (interp_time_of_day reste sur A) ; l'amendement du 09-09 (trois LUT TOD, ping-pong, tod_uploads_per_frame) n'est pas fait.
* swamp : 26,5 % des valeurs hors bornes de art (village1 2,5 %, snow 3,3 %, lavatube 13 %) : les creneaux « dome » (cone de 60 deg) decomposent mal. Hypothese de l'owner (24/09) : le marais est sous ciel couvert, soleil pas directement visible.
* SPEC annexe A ne liste pas le 8e creneau (data[7]) : lavatube data[7] = source basse, village1 data[7] = ambiante.

ROUVERT LE 24/09 AVANT TEST, sur accord de l'owner (« go »), pour deux defauts signales par l'essai precedent (reports/lighting-regimes/FINDINGS.txt) et non corriges :
1. DIRECTION INVERSEE : game/graphics/opengl_renderer/background/background_common.cpp (boucle kLightGroup, `light_dir = -lg_dir`) NEGUE la direction de creneau alors qu'elle pointe deja VERS la lumiere (tools/light_bake/main.cpp:475 la prend telle quelle) ; gfx.h:296 (recharged_pbr_lg_dir) a un commentaire faux « light-travel dirs ». La lumiere vient du mauvais cote.
2. NUIT TROP ECLAIREE : la nuit, sur les niveaux sun-fade=1 (village1), la cle devient le creneau de nuit bleu zenithal classe « cle » avec un poids direct de 1, alors que l'ancien code eteignait le direct par l'elevation du soleil.

## Livrable — le contrat, en entier

Le shader lit le REGIME du creneau au lieu de supposer un soleil ; sun-fade module la part directe. La ou il y a un ciel, sa FORME est capturee et renormalisee sur amb-color : le ciel donne la distribution, la table donne le ton. SPEC 4.10 et 4.11. PREUVE : `FEATURE lighting-regimes armed=1 hits=<images dont le regime a ete lu dans la table>` + la ligne `regime_sun_override_wrong=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-regimes"), jamais armed(), et n'en ecris pas un second.
S'AJOUTE (CORRECTION DU SUPERVISEUR, 12/09, sur question de l'owner « c'est quoi cette ambiante directionnelle legacy qu'on se trimballe ? elle est voulue par la refonte, vraiment ? »).
REPONSE : NON. La SPEC §2.4 est explicite — `rt_sh_ambient()` et `rt_ibl_ambient()` « ne sont pas supprimes comme du code mort : ils sont REMPLACES par l'environnement mesure du §4.10, ce qui est un changement de comportement assume et porte par l'item 5 », c'est-a-dire CET ITEM. Et `u_rt_sh[9]` figure dans le tableau des uniformes a retirer.
CE QUI S'EST PASSE : `rt_sh_ambient()` n'etait atteignable que depuis `pbr_fused.glsl`, donc sur les draws portant des cartes PBR. En supprimant ce fichier, `lighting-legacy-purge` l'aurait rendu naturellement inatteignable — ce qui est LA DIRECTION VOULUE. C'est un verdict que le SUPERVISEUR a pose le 12/09 a 03:15 qui l'a fait reporter dans le composite survivant, par reflexe de ne pas perdre en silence une feature validee. Le reflexe etait bon, la conclusion etait fausse : j'ai transforme un remplacement planifie en legacy qu'on traine.
CE QUE CET ITEM DOIT DONC FAIRE EN PLUS : quand l'environnement mesure atterrit, RETIRER le terme SH reporte et son uniforme. Publier le compte de lecteurs de `u_rt_sh` dans les programmes LIES, qui doit valoir zero APRES, et non nul AVANT — sinon le retrait n'est pas prouve, il est suppose.

AJOUT DU 24/09 (preuve legere : UNE grandeur par defaut, l'oeil c'est l'owner) :
A. Direction : retirer la negation fautive et corriger le commentaire de gfx.h ; grandeur : signe du produit scalaire entre la direction utilisee par le shader et la direction du creneau cuite (doit etre > 0 sur tous les creneaux des 4 niveaux).
B. Nuit : sur un niveau sun-fade=1, le poids du direct suit l'elevation comme avant (0 quand l'astre est couche) ; grandeur : poids direct publie a une heure de nuit = 0.
C. Puis livrer le build et passer en to-test ; pas de campagne multi-scenes.

## Hors perimetre

Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Les modeles d'ambiante analytiques sont deja retires par lighting-unify.

## Ou l'owner regardera

swamp et lavatube : la lumiere ne doit plus venir d'un soleil invisible

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-03
> Il y a aussi des niveaux et/zones ou le ciel n'est pas visible (tunels, overcast) come le lava tube ou le niveau de swamp par example [...] Dans le cas de ciels overcast (ie. Swamp level) la lumiere est diffusee par le ciel, pas le soleil car il n'y est pas vraiment visible

### 2026-09-03
> Pour l'ambiance qui vient du ciel attention avec l'artistic intent [...] faut etre super smart la dessus

### 2026-09-05
> Ça fait une éternité qu'on bosse sur des trucs de merde sans changements majeurs, j'aimerais un truc qui a un vrai effet Waouw next round du worker j'aimerais que ça parte sur le realtime lighting histoire d'avoir un réel sujet vraiment intéressant. Laisse finir le travail en cours et on passe sur l'intégralité du realtime lighting !

### 2026-09-24
> Le marais se décompose moins bien comme tu dis probablement parce que ce dernier est sur un ciel nuageux, temps couvert (il me semble qu'il y pleut ?) et le soleil n'y est pas directement visible (il me semble)…

### 2026-09-24
> Alors tu me demande d'aller vérifier à plein d'endroits… Faudrait que j'ai un moyen simple de me TP dans n'importe quel niveau via un menu qui apparaît sur une combinaison de touches ou un truc du style, parce qu'en l'état c'est un calvaire pour faire ces tests. J'invalide pas, mais je vais avoir du mal à tester sans ça, et vu que ce ticket est toujours in progress… autant le faire là

### 2026-09-24
> go

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

