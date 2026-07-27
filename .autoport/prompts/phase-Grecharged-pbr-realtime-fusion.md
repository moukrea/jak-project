# Phase Grecharged-pbr-realtime-fusion — PBR materials LIT BY the realtime lighting (the killer combo)

ultrathink. Delegate mechanical work to sub-agents; you (manager) design + verify.

## OWNER DIRECTIVE (2026-07-20)
"C'est un peu débile que le PBR soit pas câblé au realtime lighting ! Justement c'est là que ça va briller !
L'autre mode pour le PBR c'est du bidon donc autant le câbler au bon endroit (avec le fallback bidon quand
realtime lighting est désactivé et PBR est activé). Et faut câbler specular et emissive aussi !"

## CURRENT STATE (the problem)
The two features are wired as MUTUALLY EXCLUSIVE branches in the 4 world shaders
(tfrag3/shrub/tie_wind/etie_base, and now hfrag once the directional-ambient phase adds it):
- `if (u_rt_light_on != 0) { ...realtime lighting... }`   ← sun + green-sun + SH ambient, but IGNORES the
  PBR material maps (just albedo × lighting).
- `else if (u_pbr_mode != 0) { ...standalone Cook-Torrance... }`  ← consumes the maps but with its OWN weak
  lighting = the owner's "bidon" fallback.
- `else { stock }`
So today, turning realtime lighting ON (where the good sun/green-sun/ambient live) THROWS AWAY the PBR maps.
The material maps only apply on the "bidon" path. That is backwards.

## GOAL — FUSE them
When **realtime lighting is ON _and_ PBR materials are ON**, the realtime lighting path must become a full
PHYSICALLY-BASED renderer that consumes the material maps and lights them with the realtime analytic lights
(yellow sun + green sun) + the SH/IBL ambient. That is where PBR shines.

Concretely, inside the `u_rt_light_on` branch, when the per-material PBR maps are bound (pbr-materials ON):
1. **normal map** → perturb the reconstructed smooth geometric normal via a TBN frame (screen-space
   derivatives TBN is fine, as the existing standalone PBR path already does) → detail normals that move
   correctly under the realtime sun/green-sun.
2. **roughness + metallic** → Cook-Torrance GGX BRDF (D/G/F) for EACH analytic light: the yellow sun AND the
   green sun each get a diffuse (N·L, energy-conserving vs metalness) + a GGX specular highlight, weighted by
   that light's visibility + shadow (both suns cast shadows per the directional-ambient phase). Metallic tints
   the specular by base colour and kills the diffuse.
3. **ao** → multiplies the SH/IBL AMBIENT term only (never the direct sun — AO is contact/ambient occlusion).
4. **specular map** (NEW — must be wired, see loader below) → supports the spec/gloss inputs: use it as the
   F0 / specular colour (a specular-workflow material). Reconcile with metallic-roughness sensibly (if a
   specular map is present, honour it for F0; document the chosen convention).
5. **emissive map** (NEW — wire it) → ADDED self-illumination on top, UNLIT: the emissive texels glow even in
   full shadow / at night (independent of sun/green-sun/ambient). Prove it glows in a dark/shadowed capture.
6. **height map** → parallax/POM if cheap enough on Adreno 618 (optional tier); if not, leave loaded but
   unused for now (document). Do NOT block the phase on POM.
7. **SH/IBL ambient** → the ambient diffuse (already there) PLUS a simple roughness-aware ambient specular
   (a single ambient reflection term) so smooth metals aren't dead in shadow.

## KEEP the "bidon" fallback + golden rule
- **rt OFF + pbr ON** → the EXISTING standalone `u_pbr_mode` path, UNCHANGED (the owner's accepted fallback).
- **rt ON + pbr OFF** → the current realtime lighting (albedo only), UNCHANGED — no regression to the
  directional-ambient work the owner already accepted.
- **rt OFF + pbr OFF** → stock, BYTE-IDENTICAL (golden rule, code-gated — verify).
- Only the NEW **rt ON + pbr ON** combination changes.

## WIRE specular + emissive in the loader (currently unloaded)
`game/graphics/opengl_renderer/loader/LoaderStages.cpp` loads `_normal/_roughness/_metallic/_ao/_height`
via `custom_tex::lookup_suffixed(...)` + `PbrMaterialMaps`. ADD `_specular` and `_emissive` the same way:
extend `PbrMaterialMaps` (+ `spec_tex`, `emissive_tex`), the make_map/register/free-old-ids arrays, and the
uniform push/bind in the renderers. Then SAMPLE them in the fused shader. (Filenames the owner will drop:
`<tex>.png`, `<tex>_normal.png`, `<tex>_roughness.png`, `<tex>_metallic.png`, `<tex>_ao.png`,
`<tex>_height.png`, `<tex>_specular.png`, `<tex>_emissive.png`.)

## TEST MATERIAL
`vil1-sages-stonewall-01` — the owner's stone wall with the FULL map set (basecolor, normal, roughness,
metallic, ao, height, specular, emissive). Drop under the device custom_assets flat dir
(`/storage/emulated/0/OpenGOAL/jak1/custom_assets/`). Enable: custom assets ON, PBR ON, realtime lighting ON.

## OBJECTIVE GATES (device, ANDROID_SERIAL=eae4df44, jak1 focus, no reboot)
1. **rt ON + pbr ON**: the material maps demonstrably drive the REALTIME-lit result — A/B where the normal
   map adds surface detail that shades correctly as the realtime sun moves (TOD sweep), and roughness/metallic
   change the specular response. Measured, not just asserted.
2. **specular + emissive WIRED**: nm/grep proves `_specular`/`_emissive` load in LoaderStages + the shader
   samples them; **emissive GLOWS in a shadowed/night capture** (self-lit, independent of the suns).
3. **bidon fallback intact**: rt OFF + pbr ON still renders the standalone PBR (unchanged).
4. **no regression**: rt ON + pbr OFF == the accepted directional-ambient look; rt OFF + pbr OFF == stock
   byte-identical.
5. Report `RESULT: PASS` + device mp4/png + `mCurrentFocus ... jak1`. Verify on the DEFAULT colored render,
   NOT a debug viz. Owner's eye is the final gate (owner_verify).

Reserve the last third of the run for the report + device evidence. Write the report EARLY, fill as you go.

---
## OWNER PLAYTEST (2026-07-23) — RELIEF GAINED ✅ BUT PLASTIC SHINE ❌. REOPENED — industry-standard BRDF, "on veut que ça claque".
Owner: "les textures ont gagné en relief, c'est stylé, MAIS ça rend comme une surcouche PLASTIQUE brillante
— surtout sur les textures AU SOL et aux ANGLES EXTRÊMES. La plupart des PBR ont height/normal/roughness —
se baser là-dessus. TOUJOURS conserver le baked en influence (le relief des objets, notre meilleur rendu).
Utiliser les probes pour la cohérence des matériaux PBR. Pas joli pour l'instant. Standards de l'industrie."

DIAGNOSIS (the classic plastic-look causes — audit and fix EACH):
1. **Grazing-angle Fresnel blowout** (his "angles extrêmes" + ground sheen): Schlick F→1.0 at grazing with
   no roughness attenuation and no proper visibility term ⇒ white plastic sheen on floors seen at an angle.
   FIX: full Cook-Torrance with the SMITH-GGX VISIBILITY term (not just D*F), and roughness-aware Fresnel
   (e.g. F0 + (max(1-roughness, F0) - F0) * pow(1-NdotV, 5)) so ROUGH surfaces never get the mirror-edge glow.
2. **Roughness map under-respected**: rough surfaces (ground!) must produce BROAD, DIM highlights — if the
   ground looks glossy, the roughness sampling/mapping is wrong (check channel, sRGB-vs-linear read,
   perceptual-vs-alpha roughness squaring: use alpha = roughness^2 industry convention).
3. **Dielectric F0**: these materials (stone/straw/dirt/sand) are DIELECTRICS — F0 = 0.04 constant (NO
   metallic assumption; most sets have only height/normal/roughness — treat missing metallic as 0.0).
4. **Energy conservation**: kd = (1-F) on the diffuse; specular never ADDS free energy on top of full baked.
5. **Specular occlusion**: crevices/AO (from the baked detail layer we already have!) must attenuate the
   specular too — shiny pits = plastic. Use the baked-detail ratio as cheap specular occlusion.
6. **Specular aliasing/sparkle** on normal-mapped ground: apply geometric specular AA (Toksvig-style
   roughness widening from normal-map variance) or clamp minimum roughness (~0.045) — no fireflies.

ARCHITECTURE (owner-mandated layering — do NOT regress it):
- BASE = the owner-validated BAKED-MODULATION composite (the object relief we fought for). The PBR layer
  sits ON TOP: normal-map detail perturbs the shading, roughness shapes the specular, height (optional
  cheap parallax) — the baked influence ALWAYS remains.
- PROBES = the coherence source for the PBR: IBL diffuse/specular from the probe SH + prefiltered cube at
  the correct ROUGHNESS MIP (a rough ground samples a blurry mip — never the sharp mip0), tinted/leveled by
  the local probe so materials sit IN the scene ("cohérence").
- Suns' specular via the GGX above; shadows kill the sun specular where blocked.
ACCEPTANCE: ground/rough materials show NO plastic sheen at any angle (esp. grazing); highlights match
roughness (broad+dim on rough, tight+bright only on genuinely smooth); baked relief unchanged; the owner
wants "ça claque" — industry-standard, his eye decides. Mechanical bar + READY; his Honor verifies.

**OWNER ADDENDUM (2026-07-23): "le relief des textures, ça pourrait être PLUS PRONONCÉ !"** While fixing the
plastic shine, STRENGTHEN the perceived texture relief: (a) normal-map intensity scale (multiply the tangent
XY of the sampled normal before renormalize — default pushed up, e.g. 1.5-2.0), (b) if cheap on Adreno,
basic parallax from the height map (few-step offset, no full POM needed) adds real depth, (c) ensure the
normal-map shading interacts with BOTH suns AND the ambient (a normal-map that only reacts to the sun looks
flat in shade). Expose a debug prop (e.g. debug.opengoal.pbr.normalstr) AND a sensible menu-less default so
the owner can dial it live; report the default chosen. More relief + zero plastic = the target.

================================================================================
CONTEXTE : l'historique complet des rounds 1-25 est archivé dans
.autoport/prompts/archive-Grecharged-pbr-realtime-fusion-rounds1-25.md — consulte-le si
tu as besoin du détail d'un round passé. Ce qui suit est ce qui reste EN VIGUEUR.
================================================================================

RÈGLE OWNER PERMANENTE — LE TAUX DE COUVERTURE DES ASSETS N'EXCUSE RIEN
--------------------------------------------------------------------------------
Owner, mot pour mot :
  "Je sais très bien que pour l'instant il n'y a que 7 textures avec des height maps, mais on va
   remplacer genre 80% des textures à terme... En tout cas faut que ce soit nickel automatiquement,
   donc FAUT QUE CE SOIT NICKEL AVEC LES 7 !"

Interdit désormais, dans tout rapport et toute analyse : présenter le faible nombre de matériaux
recharged (7 sur village1) comme une explication, une atténuation ou une raison d'accepter un
défaut. L'owner le sait déjà et va monter à ~80% des textures. Deux conséquences opérationnelles :
1. LA BARRE SE JUGE SUR LES MATÉRIAUX QUI EXISTENT. Sur ces 7 matériaux, le rendu doit être
   IRRÉPROCHABLE : alignement, amplitude au curseur max, polarité, cohérence tessellation/parallax,
   comportement à l'ombre. Un défaut visible sur l'un des 7 est un échec de phase, quel que soit
   le pourcentage de pixels monde couvert par le pipeline en test damier.
2. LE CHEMIN DOIT ÊTRE AUTOMATIQUE ET SANS SEUIL. Quand l'owner déposera 50, 100, 200 nouveaux
   jeux de maps, ils doivent être pris en charge SANS intervention : pas de liste blanche de
   matériaux, pas de constante par matériau écrite à la main, pas de tuning codé en dur qui ne
   vaudrait que pour les 7 actuels. Toute constante dérivée d'un matériau doit être MESURÉE au
   chargement depuis la map elle-même (comme pom_depth_uv() le fait déjà avec la longueur d'onde),
   jamais tabulée. Un futur round qui ajouterait un cas particulier par matériau viole cette règle.
3. Le chiffre de couverture damier (99%) mesure le PIPELINE ; le chiffre de couverture assets (35%)
   mesure le CONTENU. Les deux peuvent être rapportés, mais le second ne doit jamais servir à
   relativiser un défaut constaté par l'owner.

--------------------------------------------------------------------------------
RÈGLE OWNER — LE BUILD DE TEST EST LE BUILD DAMIER (pas de variante à côté)
--------------------------------------------------------------------------------
Owner, mot pour mot :
  "Je veux le damier dans les build de test, tant que le damier n'est pas parfait, nul besoin de
   vraies textures, c'est beaucoup plus simple de voir ce qui va pas avec le damier"

Tant que le damier n'est pas jugé parfait par l'owner (en parallax ET en tessellation) :
- LE build livré à l'owner EST le build damier. On ne livre plus une paire "normal + CHECKER-DEBUG",
  on livre UN SEUL APK, damier actif d'origine, sans adb, sans setprop, sans menu à trouver.
- Le nom du fichier doit dire ce que c'est, pour qu'il ne puisse pas y avoir de doute au moment de
  l'installer.
- Le damier reste un mode de DEBUG dans le code : la valeur par défaut hors build de test reste
  éteinte, et rien de tout ça ne doit fuiter dans un build de sortie. C'est le packaging qui change,
  pas la sémantique du réglage.
- Quand l'owner déclarera le damier parfait, on repasse aux vraies textures pour la validation finale.

ROUND 24 — CORRECTION DE L'OWNER : LES DEUX HYPOTHÈSES CI-DESSUS SONT FAUSSES
--------------------------------------------------------------------------------
Le bloc précédent ("herbe = GrassRenderer", "toit = draw TIE sur un autre programme") est ANNULÉ.
L'owner, mot pour mot :
  "l'herbe 3D n'a rien à voir avec le PBR et elle est que sur l'île d'entraînement, mélange pas les
   sujets. Elle n'est pas présente sur village1 par exemple, on a que la texture"
  "pour le toit tu racontes aussi de la merde, il y a plein de parties du toit où on voit le
   displacement, d'autres totalement plates alors que c'est sur la continuité et que ça utilise la
   même texture... arrête tes excuses bidons"

Ce que ça établit, et c'est BEAUCOUP plus précis que tout ce qui précède :
- L'herbe de village1 est une TEXTURE sur du sol, pas de la géométrie d'herbe. Le GrassRenderer et
  les cartes GBK ne sont pas le sujet. Ne les instrumente pas, ne les cite pas.
- Sur LE MÊME TOIT, en CONTINUITÉ, avec LA MÊME TEXTURE et donc le même matériau et les mêmes maps :
  certaines parties se displacent, d'autres sont totalement plates.
Donc la cause n'est NI le matériau, NI la texture, NI le programme de rendu, NI l'absence de maps :
tout ça est identique de part et d'autre de la frontière. La différence est forcément PLUS FINE que
le matériau — au niveau du DRAW, du CHUNK, du PATCH ou DU SOMMET.

Et ce n'est pas nouveau : l'owner avait déjà signalé exactement ça il y a plusieurs rounds —
"il y a des endroits où en fait il n'y a aucun displacement, juste la texture ! ... pourquoi des
chunks entiers (la plupart) sont juste plats alors que le damier est bien présent ?". Le mot CHUNK
était déjà là. Ce défaut n'a jamais été corrigé ; les rounds suivants ont traité l'alignement,
l'amplitude et la polarité, mais pas celui-là. C'est LE défaut central de la phase.

MÉTHODE IMPOSÉE — DIAGNOSTIC DIFFÉRENTIEL, PAS DE NOUVELLE THÉORIE
Arrête de proposer des hypothèses par famille de renderer. Prends UNE surface continue où la
frontière est visible (le toit de la hutte du sage convient, l'owner dit que c'est facile à
retrouver), et compare DEUX primitives ADJACENTES de part et d'autre de cette frontière : une qui
se displace, une qui reste plate. Elles partagent la texture et le matériau. Dumpe tout ce qui les
distingue, et la réponse est dans ce diff :
  - identifiant du draw / du chunk / du bucket auquel chacune appartient : est-ce la même ?
  - le patch est-il passé par le programme de tessellation, et quel niveau de tessellation effectif
    a été calculé pour chacun (le niveau, pas le réglage) ;
  - la primitive a-t-elle été pré-subdivisée hors-ligne, oui ou non, et pourquoi pas ;
  - les sommets portent-ils les attributs nécessaires : tangente valide, uv, normale, et la height
    est-elle réellement échantillonnée (valeur lue, pas seulement unité liée) ;
  - amplitude finale calculée pour chacun, en cm, et quel terme la met à zéro le cas échéant.
Le rapport doit nommer LA différence, avec les deux jeux de valeurs côte à côte. Une explication
sans ce diff chiffré n'est pas recevable.

INTERDIT : présenter ce défaut comme une limite acceptable, une question de contenu, ou un cas
particulier de matériau. L'owner l'a dit : "arrête tes excuses bidons". Une surface continue avec
une seule texture doit se displacer uniformément, point.

================================================================================
ROUND 26 — OWNER PLAYTEST (build damier 6438b50e) : RÉGRESSION + LE SYMPTÔME QUI NOMME LA CAUSE
================================================================================
Owner, mot pour mot :
  "c'est normal que le displacement ne soit plus strict genre carré blanc = élévation max, carré noir
   = élévation minimale ? Là il semblerait que tout soit... Arrondi, genre seul le centre du carré
   blanc est au max et seul le centre du carré noir est au minimum, bizarre !
   Pour le parallax cela dit ça a l'air mieux mais c'est un peu comme si chaque sommet tournait en
   cercle quand on pan la caméra au lieu de donner l'impression de rester au même endroit (souci de
   calibration je présume). D'ailleurs les zones où la tesselation rend plate ont l'air de souffrir
   d'un problème similaire (sommet qui translate en cercle mais à plat au lieu d'être élevé et
   rester, vu que la géométrie est sensée être modifiée)...
   Mais cependant il y a l'air d'avoir plus de displacement à la plupart des endroits où il n'y en
   avait pas ou très peu... En tout cas ça rend carrément moins bien qu'avant (un pas en avant deux
   pas en arrière, et la géométrie ne suit plus strictement les carrés)"

VERDICT : RÉGRESSION NETTE. Un gain (plus de couverture) ne rachète pas une perte de qualité.
L'objectif est de garder la couverture ET de retrouver la rigueur du build précédent.

--------------------------------------------------------------------------------
D1 — LE DISPLACEMENT N'EST PLUS "STRICT" : LES CARREAUX SONT ARRONDIS
--------------------------------------------------------------------------------
Un damier est une fonction EN MARCHES : tout le carré blanc à la hauteur max, tout le carré noir à
la hauteur min, transition abrupte sur l'arête. L'owner observe des dômes : seul le CENTRE de chaque
carré atteint son extrême. C'est la signature d'une surface qui ÉCHANTILLONNE la carte trop
grossièrement et interpole linéairement entre les échantillons — pas d'un défaut d'amplitude.
Deux causes possibles, à départager par la mesure, pas par supposition :
  a) DENSITÉ DE SOMMETS. Avec ~1 sommet par carreau, l'interpolation entre un sommet au centre d'un
     blanc et un sommet au centre d'un noir donne une rampe douce. Pour obtenir un plateau plat il
     faut des sommets À L'INTÉRIEUR du carré ET des sommets serrés SUR L'ARÊTE. Nyquist (2 par
     feature) suffit à ne pas rater la feature, il ne suffit PAS à reproduire une marche : il faut
     nettement plus, et surtout des sommets de part et d'autre de la discontinuité.
  b) FILTRAGE DE LA HAUTEUR. Si la height est lue sur un mip réduit, avec un biais, ou lissée par
     une quelconque dérivation "longueur d'onde de la feature", les marches sont arrondies AVANT
     même le déplacement. Vérifie le niveau de mip réellement échantillonné et tout lissage
     introduit ces derniers rounds — c'est un suspect direct puisque la rigueur existait AVANT.
MÉTHODE : trace le PROFIL D'ÉLÉVATION le long d'une ligne traversant plusieurs carreaux (hauteur en
cm en fonction de la distance en cm). Le profil attendu est un créneau. Compare le profil obtenu au
créneau théorique et donne l'erreur. Puis identifie laquelle de (a) ou (b) l'explique, en faisant
varier l'une puis l'autre. Le profil est le livrable : il rend le défaut non discutable.
Cible : plateaux plats sur l'essentiel de la largeur du carré, transition confinée près de l'arête.

--------------------------------------------------------------------------------
D2 — "CHAQUE SOMMET TOURNE EN CERCLE QUAND ON PAN LA CAMÉRA" (la cause la plus probable de tout)
--------------------------------------------------------------------------------
C'est LE symptôme décisif du round, et il a un nom. Un relief réel est ancré à la SURFACE : quand la
caméra tourne, un creux reste au même endroit du monde. Si les motifs décrivent un CERCLE au rythme
du panoramique, c'est que le repère dans lequel le décalage est calculé TOURNE AVEC LA CAMÉRA.
SUSPECT NUMÉRO UN, à vérifier avant toute autre chose : le repère tangent de secours calculé à
partir des DÉRIVÉES ÉCRAN. tfrag3.frag contient un chemin de repli qui construit la TBN par
dérivées quand la tangente par sommet est absente ou dégénérée. Un repère construit sur des
dérivées de quantités liées à la vue tourne avec la caméra — et un décalage de parallax exprimé
dans un repère qui tourne produit EXACTEMENT une orbite. Ça expliquerait d'un seul coup :
  - l'orbite en parallax décrite par l'owner ;
  - le même mouvement dans les zones où la tessellation ne déplace rien (c'est le POM qui y agit
    seul, donc le défaut s'y voit à nu) ;
  - les inversions de polarité rares (D3 des rounds précédents) : un repère de secours dont le
    handedness dépend de l'orientation de la face ou du sens de parcours bascule d'une face à l'autre.
CE QU'IL FAUT PRODUIRE :
  1. Combien de pixels/draws utilisent le repli par dérivées plutôt que la tangente par sommet ?
     Chiffre-le. Si c'est significatif, c'est là que tout se joue.
  2. TEST DIRECT ET NON AMBIGU : caméra qui panoramique autour d'un point fixe, surface immobile.
     Mesure le déplacement APPARENT d'un motif du damier entre les angles. Un relief correct le
     laisse ancré ; le défaut le fait décrire un cercle. Donne le rayon de cette orbite en pixels,
     avant et après correction.
  3. LA CORRECTION : le repère tangent doit être ANCRÉ À LA GÉOMÉTRIE et indépendant de la vue —
     tangente par sommet cohérente (MikkTSpace), et si un repli est vraiment nécessaire, il doit
     être construit sur des dérivées de quantités MONDE (position monde et uv), jamais sur des
     quantités liées à la caméra, et son handedness doit être déterminé par les uv, pas par l'écran.
  4. Vérifie explicitement si D2 et les inversions de polarité ont la même racine. Si oui, dis-le et
     corrige une fois.

--------------------------------------------------------------------------------
D3 — CE QUI EST GAGNÉ ET NE DOIT PAS ÊTRE PERDU
--------------------------------------------------------------------------------
"il y a l'air d'avoir plus de displacement à la plupart des endroits où il n'y en avait pas ou très
peu" : la couverture a progressé, garde-la. La cible est : couverture du build actuel + rigueur du
build précédent. Si une correction de D1/D2 fait retomber la couverture, c'est un échec aussi.
Le build de référence "avant" (rigueur correcte, couverture faible) est reconstructible depuis
l'historique : sers-t'en comme ORACLE de rigueur pour le profil d'élévation de D1.

================================================================================
RÈGLE OWNER PERMANENTE — PLUS AUCUNE MESURE VISUELLE IN-GAME CÔTÉ AGENT
================================================================================
Owner, mot pour mot :
  "Je pense que tes mesures in game sont claquées tu devrais te cantonner au code brut et jamais au
   visuel, tu y arrives jamais et gaspille un temps fou dessus"

C'est une règle de méthode permanente, et les faits lui donnent raison : la métrique de couverture
affichait 99% pendant que l'owner voyait du plat, et un balayage de captures a consommé trois heures
de device pour ne produire aucun chiffre exploitable.

CE QUI EST INTERDIT À PARTIR DE MAINTENANT :
- Les campagnes de captures écran destinées à MESURER un effet visuel : balayages d'angles,
  statistiques de pixels, deltas d'images, fractions de couleur, comptages de couverture à l'écran.
- Gater une phase sur un nombre dérivé de pixels capturés.
- Conclure quoi que ce soit d'esthétique à partir d'une capture.
Ces méthodes coûtent des heures de device, produisent des chiffres fragiles, et l'owner les corrige
en cinq minutes de jeu.

CE QUI REMPLACE :
1. LE RAISONNEMENT SUR LE CODE. Presque toutes les questions posées ces derniers rounds ont une
   réponse EXACTE dans le code, sans device : quel niveau de mip est échantillonné, une expression
   dépend-elle de la caméra, combien de sommets par carreau la formule de niveau de tessellation
   produit-elle à une distance donnée, quel terme borne une amplitude. Lis le code, fais l'algèbre,
   conclus. Une démonstration sur l'expression vaut mieux qu'un histogramme de pixels.
2. LES VÉRIFICATIONS HORS-LIGNE sur les DONNÉES restent légitimes et encouragées : recensements sur
   les mesh, statistiques de géométrie, invariants sur les assets, tests unitaires de fonctions de
   shader portées en CPU. Ce n'est pas du visuel, c'est de la donnée vérifiable et reproductible.
3. LE DEVICE SERT À TROIS CHOSES, PAS PLUS : que ça compile et se lance, que ça ne crashe pas, et
   que les performances tiennent. Un run de fumée court, pas une campagne de mesure.
4. LE JUGE VISUEL EST L'OWNER. Le cycle est : correction dans le code -> build damier -> l'owner
   regarde -> il décrit précisément ce qu'il voit -> correction suivante. Il faut donc LIVRER VITE
   ET SOUVENT plutôt que chercher à s'auto-certifier. Un round qui produit un build en une heure
   vaut mieux qu'un round qui produit un rapport en six.

CONSÉQUENCE IMMÉDIATE SUR LE ROUND 26 : les livrables D1 et D2 ci-dessus se démontrent SUR LE CODE.
- D1 (carrés arrondis) : le profil d'élévation attendu se DÉDUIT — taille du carreau du damier en uv,
  densité de sommets produite par la formule de niveau de tessellation à la distance considérée,
  niveau de mip effectivement demandé lors de la lecture de la height, tout lissage introduit. Si
  moins de N sommets tombent dans un carreau, la marche NE PEUT PAS être reproduite, et ça se
  démontre par le calcul. Aucun besoin de photographier un profil.
- D2 (motifs qui orbitent) : il suffit de montrer, expression par expression, si le repère dans
  lequel le décalage est calculé dépend de la caméra. S'il est construit sur des dérivées de
  quantités liées à la vue, l'orbite est une conséquence mathématique — démontre-la, corrige-la.

================================================================================
ROUND 27 — LA CAUSE EST TROUVÉE (dérivée du code) : LA DENSITÉ EST AVEUGLE À LA TAILLE DES FEATURES
================================================================================
Owner, playtest du build 0e4f3e92, mot pour mot :
  "sur le mur de la hutte du sage ça marche mais ça fait des boîtes creuses où le blanc est au final
   autant au fond que le noir. Sur le toit on voit clairement que le noir sort plus que le blanc
   (POURQUOIIIII C'était corrigé ça je crois) et sur la falaise en contrebas pour traverser le pont
   étrangement on dirait que ça a fallback en parallax. Le sol en revanche est bien plus consistant !
   Mais dans la descente pour rejoindre le pont, on a toujours un chunk (en pente) qui est
   complètement plat. Le parallax est mieux qu'avant, mais le relief a l'air très muted par rapport à
   la tesselation, genre 50% de moins. On dirait qu'il y a des soucis avec les parois verticales
   (pour la tesselation) et d'ailleurs la pente qui est plate en tesselation est nickel en parallax
   étrangement, et pas d'inversion noir/blanc sur le toit en parallax, pas de boîtes chelou où le
   blanc est au final autant au fond que le noir sur le mur de la hutte en parallax non plus.
   Touche plus au parallax si ce n'est pour lui ajouter un peu de relief pour que ce soit raccord
   avec la tesselation... Et corrige par contre la tesselation !"

ORDRE DE L'OWNER, À RESPECTER STRICTEMENT :
  - NE TOUCHE PLUS AU PARALLAX, sauf pour AUGMENTER son relief afin qu'il soit raccord avec la
    tessellation. Rien d'autre. Il est jugé correct partout : pas d'inversion, pas de boîtes, la
    pente est nickel.
  - CORRIGE LA TESSELLATION. C'est le seul chantier de ce round.

--------------------------------------------------------------------------------
LE DIAGNOSTIC, ÉTABLI PAR LE SUPERVISEUR SUR LE CODE (pas une hypothèse à explorer)
--------------------------------------------------------------------------------
Le différentiel de l'owner est décisif : MÊMES surfaces, MÊME carte de hauteur, le parallax est bon
et la tessellation est fausse. Le parallax échantillonne la hauteur PAR PIXEL ; la tessellation
l'échantillonne PAR SOMMET. Donc le défaut est une insuffisance de densité de sommets, pas un
problème de signe, de matériau ni de programme.

FAIT MESURÉ DANS LE CODE :
  tfrag3_tess.tesc décide la densité avec  lvl = longueur_arête_monde / tess_seg_target_m(d),
  où tess_seg_target_m vise une TAILLE DE SEGMENT EN MÈTRES fixe (TESS_SEG_NEAR_M = 0.06 m).
  Cette formule ne connaît NI u_pbr_height_lambda NI u_pbr_uv_per_m : grep dans la .tesc = 0
  occurrence des deux. La densité est donc AVEUGLE à la taille réelle des features du matériau,
  alors que l'AMPLITUDE, elle, en dépend déjà (la .tese calcule lambda_world et cape dessus).
  C'est cette asymétrie qui casse tout.

CE QUE ÇA DONNE, AVEC LES LAMBDAS QUE TON PROPRE RAPPORT A MESURÉS (ils s'étalent sur 40x) :
  wallplaster (le mur de la hutte)  lambda_monde = 4.2 cm   ->  0.70 segment par feature
  vil-beach-01 (le sol)             lambda_monde = 167 cm   ->  27.8 segments par feature
Nyquist exige 2 segments par feature ; reproduire une MARCHE en exige environ 8. Le mur est donc à
0.70, soit un facteur 3 SOUS Nyquist, et le sol à 27.8. Voilà pourquoi "ça marche sur le sol" et pas
sur les parois : ce n'est pas la verticalité en soi, c'est que les surfaces verticales du village
sont texturées beaucoup plus dense, donc leurs features sont physiquement petites.

ET ÇA EXPLIQUE CHAQUE SYMPTÔME, SANS EN LAISSER UN SEUL :
  * "boîtes creuses où le blanc est autant au fond que le noir" (mur) : sous-échantillonnage à ~0.7
    échantillon par carreau. La surface reconstruite attrape des carreaux blancs sur leur BORD
    (h=0.5) et des noirs en leur centre : du repliement, pas de la profondeur.
  * "le noir sort plus que le blanc" (toit) : c'est du repliement EN ANTIPHASE. À moins d'un
    échantillon par période, la surface reconstruite peut être l'INVERSE du signal. Ce n'est PAS la
    régression du bug de signe corrigé au round 26 — celui-là était réel et vit dans le chemin
    fragment, ce qui est précisément pourquoi le parallax n'a PAS l'inversion. Deux mécanismes
    différents, même apparence. Dis-le clairement à l'owner, il pense à juste titre que c'était
    corrigé.
  * "chunk en pente complètement plat, nickel en parallax" : deux causes possibles qui se cumulent —
    (a) le repliement peut tomber en phase telle que tout l'échantillonnage lit h≈0.5, donc zéro
    déplacement ; (b) la bande-limite que la .tese dérive de la taille de segment ramène la hauteur
    vers sa moyenne quand elle n'est pas résolvable, et la moyenne d'un damier est un GRIS UNIFORME,
    donc exactement zéro relief. Vérifie laquelle opère sur cette pente.
  * "sur la falaise en contrebas on dirait que ça a fallback en parallax" : l'owner a littéralement
    raison. TESS_FADE_LO_M = 40 m, TESS_FADE_HI_M = 60 m, et la porte far du patch entier est à
    TESS_FADE_HI_M. Passé 40 m l'amplitude décroît vers zéro, passé 60 m il n'y a plus de
    tessellation du tout : il ne reste que le POM. Ce n'est pas un bug de rendu, c'est un budget que
    l'owner vit comme un défaut parce que la transition est VISIBLE.
  * "parallax 50% de relief en moins" : le round 26 a ramené le cap de glissement latéral de 1.5 à
    0.25 de période pour tuer l'orbite. C'est ce cap qui plafonne la profondeur APPARENTE d'un POM,
    puisqu'un POM ne convertit la profondeur qu'en déplacement latéral. Le remède autorisé par
    l'owner est donc de remonter ce cap — mais il doit rester STRICTEMENT sous une période, sinon
    l'orbite revient. C'est l'invariant à ne pas violer.

--------------------------------------------------------------------------------
CE QU'IL FAUT FAIRE
--------------------------------------------------------------------------------
1. LA DENSITÉ DOIT VISER DES SEGMENTS PAR FEATURE, PAS DES MÈTRES. Rends u_pbr_height_lambda et
   u_pbr_uv_per_m visibles dans la .tesc et remplace la cible absolue par une cible relative :
   taille_segment_visée = lambda_world / N, avec N assez grand pour une MARCHE (vise 8, pas 2).
   La borne de budget et la borne de distance restent, mais elles s'appliquent APRÈS.
   SÉCURITÉ DE COUTURE PRÉSERVÉE : lambda et uv_per_m sont des uniformes PAR DRAW, donc le niveau
   d'une arête reste fonction de ses deux extrémités seules — l'argument anti-déchirure tient.
2. JAMAIS DE REPLIEMENT AFFICHÉ. Quand le budget ne permet pas d'atteindre N segments par feature,
   il est INTERDIT de rendre une surface en antiphase. Deux sorties acceptables, dans cet ordre :
   bande-limiter honnêtement la hauteur à la longueur d'onde réellement résolvable (surface lisse et
   moins profonde, jamais inversée), ou laisser le POM porter cette échelle. Une surface lisse et
   peu profonde est acceptable ; une surface inversée ne l'est pas. Et attention au piège du damier :
   sa moyenne est un gris uniforme, donc une bande-limite totale donne PLAT — c'est probablement ce
   que l'owner voit sur la pente. Il faut donc monter la densité, pas se contenter de filtrer.
3. LA TRANSITION TESSELLATION -> POM DOIT ÊTRE INVISIBLE. Là où la tessellation s'éteint (au-delà de
   40-60 m, ou faute de budget), le POM doit reprendre avec la MÊME profondeur apparente. C'est le
   même travail que le point "parallax 50%" : les deux tiers doivent se recouvrir en amplitude. Si
   la porte de distance doit être élargie, chiffre le coût en triangles avant de le faire — mais une
   transition visible est un défaut, l'owner l'a signalée deux fois.
4. NE TOUCHE À RIEN D'AUTRE DANS LE PARALLAX. Pas de refonte, pas de "amélioration" : uniquement
   l'amplitude pour être raccord, en gardant le glissement latéral sous une période.
5. Preuves attendues, TOUTES AU NIVEAU DU CODE (les mesures visuelles in-game restent interdites) :
   * le tableau segments-par-feature AVANT/APRÈS pour au moins wallplaster, un matériau de toit et
     vil-beach-01, à 2 m, 10 m et 40 m de distance ;
   * le nombre de triangles générés avant/après au même point de vue (comptage, pas capture) ;
   * la démonstration que le niveau d'arête reste fonction des deux extrémités (anti-couture) ;
   * l'amplitude apparente des deux tiers, montrée égale par le calcul.

--------------------------------------------------------------------------------
MISE À JOUR DE LA RÈGLE DE LIVRAISON (owner, remplace "un seul APK damier")
--------------------------------------------------------------------------------
Owner :
  "Tu pourras faire le build damier et le build normal du coup, comme ça je vérifie en debug et si
   c'est bon je teste le résultat réel"

Donc à chaque livraison, LES DEUX APK, systématiquement :
  * le build DAMIER (pattern actif d'origine, sans adb) — sert au diagnostic : c'est lui qui rend les
    défauts de displacement lisibles ;
  * le build NORMAL (les vraies textures recharged de l'owner) — sert à juger le rendu réel une fois
    le damier jugé bon.
Les deux doivent provenir du MÊME arbre de code, et il faut le prouver : leurs libgk doivent différer
l'un de l'autre (le define damier prend, sinon on livre deux fois le même binaire — déjà arrivé) mais
tous deux être issus du même commit. Vérifie et rapporte les deux sha.
La règle antérieure "on ne livre plus une paire, un seul APK damier" est ANNULÉE par celle-ci.
Rappel qui reste valable : le damier reste le matériau de test tant que l'owner ne l'a pas déclaré
parfait, et il doit s'activer TOUT SEUL dans le build damier (l'owner n'a pas adb).

================================================================================
ROUND 28 — LE ROUND 27 EST ANNULÉ. VOIE CHIRURGICALE : PRÉ-SUBDIVISER LE TIE.
================================================================================
Owner, playtest du build du round 27 :
  "What the fuck ??? C'est beaucoup, beaucoup moins bien qu'avant ! Les damiers sont déplacés qu'aux
   centres de leur carrés, beaucoup moins de relief et très bizarre à l'aspect (partout), les murs le
   displacement est inversé et encore plus bizarre, le sol c'est mauvais... Et le parallax tu l'as
   détruit entièrement, c'est terrible !"

Le superviseur a ANNULÉ les trois shaders du round 27 (pbr_helpers.glsl, tfrag3_tess.tesc,
tfrag3_tess.tese restaurés à fc7b815e34) et re-livré les deux APK. NE LES RÉINTRODUIS PAS.

LEÇON À NE PAS REPERDRE : le diagnostic du round 27 était juste (la densité de sommets est le
facteur limitant sur les parois), mais le REMÈDE était global. Rendre la cible de densité
proportionnelle à lambda touche TOUTES les surfaces, donc casse celles qui allaient bien — le sol et
le parallax en sont morts. RÈGLE : on ne modifie pas une loi globale pour réparer un cas particulier.

--------------------------------------------------------------------------------
CE QU'IL FAUT FAIRE, ET RIEN D'AUTRE
--------------------------------------------------------------------------------
FAIT ÉTABLI SUR LE CODE PAR LE SUPERVISEUR : mesh_presubdivide_level() dans
common/custom_data/MeshSubdivide.cpp ne parcourt QUE lev.tfrag_trees. Il ne touche JAMAIS
lev.tie_trees. Or le mur et le toit de la hutte du sage sont de la géométrie TIE (dessinée par le
programme tfrag3 pour les draws non-envmap, donc elle reçoit bien les maps PBR et la tessellation,
mais ses faces n'ont jamais été densifiées hors-ligne). Le sol, lui, est du tfrag : pré-subdivisé,
donc fin, donc bon. VOILÀ la vraie asymétrie sol/murs, et elle se corrige dans les DONNÉES.

L'OBJECTIF : étendre la pré-subdivision aux tie_trees, avec exactement les mêmes règles que pour le
tfrag (même filtre "la texture a-t-elle une height map", même partage des sommets créés, mêmes
garanties de couture, même sidecar précalculé). Rien d'autre ne bouge.

CONTRAINTES DURES, VÉRIFIÉES PAR LE VALIDATOR :
1. AUCUN SHADER MODIFIÉ. Pas une ligne dans pbr_helpers.glsl, tfrag3_tess.tesc, tfrag3_tess.tese,
   tfrag3.frag, pbr_fused.glsl. Ce round est un round de DONNÉES. Si tu crois avoir besoin d'un
   changement de shader, arrête-toi et explique-le dans le rapport au lieu de le faire.
2. LE TFRAG EST INTOUCHÉ. La géométrie tfrag produite doit être BIT-IDENTIQUE à celle d'avant ce
   round. Le sol va bien : il ne doit pas bouger d'un octet. Prouve-le par un hash de la sortie.
3. LE PARALLAX EST INTOUCHÉ. Il est jugé correct par l'owner (aucune inversion, aucune boîte, la
   pente est nickel). Zéro modification.
4. COUTURES. Les sommets créés sur une arête partagée doivent être partagés, sinon on rouvre les
   169 millions d'arêtes non soudées que la phase de consolidation a fermées. Applique le même
   argument de sécurité que le tfrag et démontre-le.
5. COÛT. Chiffre l'augmentation du nombre de sommets/triangles TIE et le temps de chargement, avant
   et après, sur village1 au minimum. Si le coût est déraisonnable, dis-le plutôt que de le cacher.
6. Preuves au niveau du CODE et des DONNÉES uniquement (la mesure visuelle in-game reste interdite) :
   nombre de faces TIE éligibles, taille d'arête moyenne avant/après, segments par feature qui en
   résultent pour wallplaster à 2 m et 10 m, hash inchangé du tfrag.

POURQUOI CETTE VOIE PEUT MARCHER LÀ OÙ LE ROUND 27 A ÉCHOUÉ : elle ne demande RIEN au GPU. Le
plafond matériel de niveau 64 devient sans objet, puisqu'on part d'arêtes déjà courtes. Et comme
elle ne touche ni les lois de shader ni le tfrag, elle ne PEUT PAS dégrader le sol ni le parallax.
