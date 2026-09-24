# La lumiere cle n'est pas toujours un soleil — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. pc-set-pbr-sky-sun! est pousse sans garde et ecrase la lumiere cle : dans 16 niveaux sur 20 la clef du monde suit un soleil que le joueur ne voit pas. SPEC 3.2, 3.3 et l'annexe A.

## Livrable — le contrat, en entier

Le shader lit le REGIME du creneau au lieu de supposer un soleil ; sun-fade module la part directe. La ou il y a un ciel, sa FORME est capturee et renormalisee sur amb-color : le ciel donne la distribution, la table donne le ton. SPEC 4.10 et 4.11. PREUVE : `FEATURE lighting-regimes armed=1 hits=<images dont le regime a ete lu dans la table>` + la ligne `regime_sun_override_wrong=` seule sur sa ligne ; `--off` doit rendre `armed=0 hits=0` dans la MEME scene. Le publicateur EXISTE : game/system/autoport_proof.{h,cpp} — appelle armed_for("lighting-regimes"), jamais armed(), et n'en ecris pas un second.
S'AJOUTE (CORRECTION DU SUPERVISEUR, 12/09, sur question de l'owner « c'est quoi cette ambiante directionnelle legacy qu'on se trimballe ? elle est voulue par la refonte, vraiment ? »).
REPONSE : NON. La SPEC §2.4 est explicite — `rt_sh_ambient()` et `rt_ibl_ambient()` « ne sont pas supprimes comme du code mort : ils sont REMPLACES par l'environnement mesure du §4.10, ce qui est un changement de comportement assume et porte par l'item 5 », c'est-a-dire CET ITEM. Et `u_rt_sh[9]` figure dans le tableau des uniformes a retirer.
CE QUI S'EST PASSE : `rt_sh_ambient()` n'etait atteignable que depuis `pbr_fused.glsl`, donc sur les draws portant des cartes PBR. En supprimant ce fichier, `lighting-legacy-purge` l'aurait rendu naturellement inatteignable — ce qui est LA DIRECTION VOULUE. C'est un verdict que le SUPERVISEUR a pose le 12/09 a 03:15 qui l'a fait reporter dans le composite survivant, par reflexe de ne pas perdre en silence une feature validee. Le reflexe etait bon, la conclusion etait fausse : j'ai transforme un remplacement planifie en legacy qu'on traine.
CE QUE CET ITEM DOIT DONC FAIRE EN PLUS : quand l'environnement mesure atterrit, RETIRER le terme SH reporte et son uniforme. Publier le compte de lecteurs de `u_rt_sh` dans les programmes LIES, qui doit valoir zero APRES, et non nul AVANT — sinon le retrait n'est pas prouve, il est suppose.

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

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

