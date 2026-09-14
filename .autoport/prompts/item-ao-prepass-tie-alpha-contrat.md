# La prepasse d'AO garde les memes fragments que la couleur sur le TIE statique : plus d'ombre calculee a cote de la geometrie — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Ne du blocage de lighting-ao-indirect (13 essais). Handoff de l'essai 13, mesure : `ao_geom_tie_absent_px=1646` et `ao_geom_tie_absent_nocut_match_px=1646`, `_nocut_off_px=0` : a 100 % la prepasse DESSINE la geometrie TIE statique A LA PROFONDEUR DE LA SCENE et c'est SON ALPHA-TEST qui la jette pendant que la couleur garde le fragment — un SUR-DECOUPAGE, pas un dessin manquant ; 1096 px sur 1646 sont des trous INTERIEURS (>= 3x3). Shrub et tfrag rendent 0 ; ce n'est PAS le vent (`ao_sway_gap_px` le comptait a tort). ECARTE PAR LA MESURE, ne le refais pas : la categorie NORMAL_ENVMAP_SECOND_DRAW (`ao_geom_tie_env2_absent_px=0`) ; les quatre `glTexParameteri` non poses par la prepasse (defaut REEL corrige a l'essai 13, `ao_pre_texstate_bad` 12570/25449, mais le compte n'a pas bouge) ; le seuil `alpha_min*255/512` (LUT saturee a 128, idem arm64) ; la texture (`m_textures->at(draw.tree_tex_id)` des deux cotes, Tie3.cpp:1377/:1718) ; `alpha_min` de la couleur ; `shade()` ne touche jamais `color.a` (shade.glsl:197, :226) ; le FBO de prepasse a `render_fb_w/h` ; l'UV ; la plage d'EBO. Reste a chercher : ce qui, dans le fragment de PREPASSE, differe du fragment de COULEUR pour le meme TIE statique (etat de blend/alpha-to-coverage, mipmap/LOD de la texture au moment du test, precision, ordre des draws). ACQUIS DE lighting-ao-indirect A NE PAS ROUVRIR NI CASSER (essai 13, appareil eae4df44) : Eleve en pleine resolution (`ao_high_not_fullres=0`), damier sous plafond (`ao_pattern_over_ceiling=0`), alpha respecte sur l'appareil vent allume (`ao_on_alpha_device_px=0`), fuite du direct nulle (`ao_direct_leak_px=0`), bande de contact nulle (`ao_contact_band_px=0`), prepasse qui suit le vent des SHRUBS (26,7 % -> 0,31 %). Ces cinq cles entrent dans la porte de cet item et doivent rester a zero.

## Livrable — le contrat, en entier

`ao_tie_prepass_defects` = 0, somme de termes publies SEPAREMENT.
1. LA CAUSE EST NOMMEE AVANT LE CORRECTIF : publier, pour un echantillon de fragments TIE jetes par la prepasse et gardes par la couleur, la valeur d'alpha vue par chaque passe et l'etat qui differe (compte par cause). Un correctif sans cette table est un essai a l'aveugle.
2. PLUS DE TROU : `ao_geom_tie_absent_px` = 0 sur le vantage de l'essai 13 et sur deux autres nommes, avec `ao_geom_cover_px` a cote ; les trous interieurs (>= 3x3) comptes separement, zero.
3. LA COULEUR NE CHANGE PAS : le correctif vit dans la PREPASSE ; image couleur bit-identique AO eteinte, et compte de fragments TIE changes dans la passe couleur = zero.
4. LES ACQUIS TIENNENT ET L'OWNER PEUT JUGER : les cinq cles acquises et `ao_static_defects` restent a zero dans la MEME preuve ; `where` decrit exactement ce que l'owner regarde.
PREUVE : `FEATURE ao-prepass-tie-alpha armed=1 hits=<fragments de TIE statique juges dans la prepasse>` + la ligne `ao_tie_prepass_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne rouvre aucun des cinq acquis. Ne touche pas a la sonde de stabilite (ao-static-probe-deterministic). Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Options > Recharged > Recharged Lighting > Ambient Occlusion, sur le HONOR : chaque palier et chaque mode (SSAO, HBAO, GTAO), force au maximum. Aucun damier ni pixelisation, meme en Eleve ; aucune bande claire aux contacts ; sur les shrubs qui balancent, l'ombre suit le feuillage et rien ne flotte hors des textures ; camera immobile, rien ne bouge.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

