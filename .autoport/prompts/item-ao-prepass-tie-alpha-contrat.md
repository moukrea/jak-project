# La prepasse d'AO garde les memes fragments que la couleur sur le TIE statique : plus d'ombre calculee a cote de la geometrie — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

16/09 ARBITRAGE OWNER : « 1 a » = 3 essais, STRATEGIE NOUVELLE, pas une repetition. Lire d'abord handoff.md, FINDINGS.txt, notes/attempt12-summary.md, attempt12-comparison.json. Acquis : essai 10 (flou centre, adafa03109) a reduit la bande claire mur/toit de 7 a 2 px en GTAO sur le Redmi ; residus SSAO2/HBAO1/GTAO2 ; essai 11 (reconstruction) REJETE et retire ; les 3 variantes de support reduit sont REJETEES, ne pas les rejouer. Strategie imposee : (1) preuve USB NEUVE du residu de l'essai 10 avec attempt12-analyze.py sur profils entiers (pics/plateaux apres le premier pixel sombre), publiee terme par terme dans les 7 termes de ao_owner_defects ; (2) SEULEMENT ensuite, corriger le pic clair a +1 px du raccord par une voie qui n'elargit ni ne reduit le support du flou (ex. poids nul des echantillons qui traversent le pli, detecte sur la profondeur/normale), mesuree sur les memes 15 contacts et 425 px identifies ; (3) aucun pixel hors raccord ne change (controle bit-identique des 36 sorties locales). Un essai sans preuve appareil est un echec.

REPRISE APRES ESSAI11 : candidat17b659564c encore insuffisant. Le premier pixel devient sombre mais le pic clair se deplace a+1 : SSAO[133,138,135,133,131,130]. Le lecteur prefixe rend0 a tort pour ce defaut ; analyser tout le profil physique, sans changer les populations/seuils precedents. Modifications globales11666/10877/11220pixels et assombrissement61/50/51octets non qualifies. Reprendre attempt11-summary.md et bancs existants : cette information change le diagnostic, ne pas refaire le meme candidat.

REPRISE APRES ESSAI10 : cause locale etablie, pas de nouvel audit. Le flou decale et dilue le contact ; centrage adafa03109 reduit GTAO7px a2px, reste SSAO2/HBAO1/GTAO2. notes/attempt10-residual-ssao.md montre une bande creee des blur1 et un profil monotone ignore par ridge. Reprendre ces archives, pas la preparation de capture terminee.

REPRISE OWNER15/09 : le defaut visible est etabli par son test et sa capture : bande de mur claire exactement entre mur et toit. Corriger ce raccord, ne pas redemander de prouver son existence. Le diagnostic des instruments est deja fait (attempt7-contact-diagnostic.md) : reprendre la preparation puis la correction, pas un nouvel audit documentaire.

RETOUR OWNER 15/09 : bande claire persistante au CONTACT ENTRE MUR DE HUTTE ET TOIT, capture owner-feedback/2026-09-15-ao-hut-contact.png. Plus de damier/pixelisation et AO shrubs bonne sur le build teste. Le zero historique ao_contact_band_px NE COUVRE PAS ce defaut observe ; ne pas le defendre comme validation de cette jonction. Revision testee non identifiee. Diagnostic causal a etablir, la capture nest pas une mesure moteur.

MISE A JOUR SUPERVISEUR 14/09, essais 2-3 : la table de diagnostic contredit l hypothese de sur-decoupage du rendu. Le correctif porte sur l alpha ecrit par la MESURE (shade.glsl), et la course 3 rend zero trou sur village1-hut avec 86866 pixels TIE observes. La stabilite et les cinq acquis sont a zero ; les deux autres vues et l identite couleur restent non prouves. Ne pas forcer une modification de prepasse sur cette seule hypothese.

HISTORIQUE A CONSERVER, CAUSALITE DE SUR-DECOUPAGE REFUTEE PAR LES ESSAIS 2-3 :
Ne du blocage de lighting-ao-indirect (13 essais). Handoff de l'essai 13, mesure : `ao_geom_tie_absent_px=1646` et `ao_geom_tie_absent_nocut_match_px=1646`, `_nocut_off_px=0` : a 100 % la prepasse DESSINE la geometrie TIE statique A LA PROFONDEUR DE LA SCENE et c'est SON ALPHA-TEST qui la jette pendant que la couleur garde le fragment — un SUR-DECOUPAGE, pas un dessin manquant ; 1096 px sur 1646 sont des trous INTERIEURS (>= 3x3). Shrub et tfrag rendent 0 ; ce n'est PAS le vent (`ao_sway_gap_px` le comptait a tort). ECARTE PAR LA MESURE, ne le refais pas : la categorie NORMAL_ENVMAP_SECOND_DRAW (`ao_geom_tie_env2_absent_px=0`) ; les quatre `glTexParameteri` non poses par la prepasse (defaut REEL corrige a l'essai 13, `ao_pre_texstate_bad` 12570/25449, mais le compte n'a pas bouge) ; le seuil `alpha_min*255/512` (LUT saturee a 128, idem arm64) ; la texture (`m_textures->at(draw.tree_tex_id)` des deux cotes, Tie3.cpp:1377/:1718) ; `alpha_min` de la couleur ; `shade()` ne touche jamais `color.a` (shade.glsl:197, :226) ; le FBO de prepasse a `render_fb_w/h` ; l'UV ; la plage d'EBO. Reste a chercher : ce qui, dans le fragment de PREPASSE, differe du fragment de COULEUR pour le meme TIE statique (etat de blend/alpha-to-coverage, mipmap/LOD de la texture au moment du test, precision, ordre des draws). ACQUIS DE lighting-ao-indirect A NE PAS ROUVRIR NI CASSER (essai 13, appareil eae4df44) : Eleve en pleine resolution (`ao_high_not_fullres=0`), damier sous plafond (`ao_pattern_over_ceiling=0`), alpha respecte sur l'appareil vent allume (`ao_on_alpha_device_px=0`), fuite du direct nulle (`ao_direct_leak_px=0`), bande de contact nulle (`ao_contact_band_px=0`), prepasse qui suit le vent des SHRUBS (26,7 % -> 0,31 %). Ces cinq cles entrent dans la porte de cet item et doivent rester a zero.

## Livrable — le contrat, en entier

`ao_tie_prepass_defects` = 0, somme de termes publies SEPAREMENT.
1. LA CAUSE EST NOMMEE AVANT LE CORRECTIF : publier, pour un echantillon de fragments TIE jetes par la prepasse et gardes par la couleur, la valeur d'alpha vue par chaque passe et l'etat qui differe (compte par cause). Un correctif sans cette table est un essai a l'aveugle.
2. PLUS DE TROU : `ao_geom_tie_absent_px` = 0 sur le vantage de l'essai 13 et sur deux autres nommes, avec `ao_geom_cover_px` a cote ; les trous interieurs (>= 3x3) comptes separement, zero.
3. LA COULEUR NE CHANGE PAS : le correctif porte sur la cause etablie, y compris l instrument de mesure si le diagnostic accuse celui-ci ; aucune modification du rendu ne doit etre faite pour satisfaire une hypothese refutee ; image couleur bit-identique AO eteinte, et compte de fragments TIE changes dans la passe couleur = zero.
4. LES ACQUIS TIENNENT ET L'OWNER PEUT JUGER : les cinq cles acquises et `ao_static_defects` restent a zero dans la MEME preuve ; `where` decrit exactement ce que l'owner regarde.
PREUVE : `FEATURE ao-prepass-tie-alpha armed=1 hits=<fragments de TIE statique juges dans la prepasse>` + la ligne `ao_tie_prepass_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.
RETOUR OWNER 15/09 : la bande claire mur/toit de la hutte reste NON CORRIGEE. La clause contact inclut explicitement cette jonction, avec population geometrique identifiee et diagnostic du decalage avant correction. Ne pas conclure depuis une autre vue ou ao_contact_band_px=0 hors de cette population. Preserver les ameliorations confirmees par l owner : AO suivant les shrubs, absence de damier et de pixelisation. Aucun seuil assoupli pour faire disparaitre le signalement.

## Hors perimetre

Ne rouvre aucun des cinq acquis. Ne change ni l ordonnanceur, ni les populations, ni les criteres de la sonde de stabilite ao-static-probe-deterministic. Son raccordement a cet item est autorise pour produire ao_static_defects dans la preuve exigee : activer et reutiliser la MEME sonde et son lecteur, sans dupliquer leur logique ni reutiliser une valeur archivee comme mesure courante. Conserver les temoins, le regime et les controles de non-vacuite. Tout autre changement de la sonde reste hors perimetre.

Campagne explicitement autorisee par l owner le 2026-09-14 (« bah oui faut que ça avance »), proof_plan du backlog : village1-hut, village1-out et beach, neuf courses maximum au TOTAL de 150 s maximum chacune ; par vue reference ON, comparaison ON, controle OFF. Instrumentation couleur manquante autorisee dans ce seul plan. Preparer les populations et positions avant les courses, garder les criteres et cinq acquis. L autorisation couvre ces mesures supplementaires, aucune validation owner.
EXCEPTION EXPLICITE AU GEL DU CONTACT : le retour owner du15/09 rouvre la bande claire mur/toit ; les autres ameliorations restent protegees. Le plan trois vues a epuise9/9 courses : ce retour est une non-validation de contact, pas un budget de campagne augmente. Commencer par diagnostic des sources/archives et correspondance avec la jonction signalee, sans relancer ce plan epuise.
REPRISE15/09 APRES REPONSE OWNER : le plan historique9/9 reste clos. Le proof_plan courant borne la correction demandee au raccord hutte, six mesures maximum150s, instrumentation necessaire comprise. Ce nouveau perimetre remplace l attente d arbitrage precedente ; ne pas refaire la campagne trois vues ni toucher aux mini-palmiers valides. Preserver tous les criteres finaux ; aucune validation acquise par cette reprise.
REPRISE LOCALE APRES6/6 : preparer une correction de la dilution residuelle sur les archives deja acquises, avec rejeu local du shader et profils fixes425pixels/15contacts. Pas de nouvel appel proof_run appareil ni de recapture : campagne6/6 close. Traiter aussi les phases du damier pour ne pas le reintroduire. Comparer reference/candidat sur le meme pilote local ; les ecarts connus Intel/Redmi1..2quantums interdisent de presenter le resultat local comme validation appareil. Livrer candidat compile, tests et limites ; ne pas rendre la main en repetant uniquement budget epuise. Aucune baisse de seuil, aucun cote manquant efface, aucune cloture de resultat.
SUITE LOCALE ESSAI11 : commencer par un controle complementaire du profil entier incluant pics secondaires et plateaux apres le premier pixel sombre, sans supprimer les anciens verdicts ni censurer les echecs. Reprendre explicitement le cas133,138,135 qui doit rester rouge. Qualifier la propagation hors raccord sur les archives completes (surfaces/concavite), conserver temoins plans/ciel/silhouettes/phases4 ; revoir ou retirer la reconstruction partielle si sa portee ne se justifie pas. Corriger la dilution a sa cause et qualifier tout effet hors contact ; aucun elargissement arbitraire de masque. Aucune nouvelle mesure appareil, aucun verdict machine courant tire de proof.txt historique. Le prochain resultat est candidat local compile et ses limites, pas fermeture globale.

## Ou l'owner regardera

Options > Recharged > Recharged Lighting > Ambient Occlusion, sur le HONOR : chaque palier et chaque mode (SSAO, HBAO, GTAO), force au maximum. Aucun damier ni pixelisation, meme en Eleve ; aucune bande claire aux contacts ; sur les shrubs qui balancent, l'ombre suit le feuillage et rien ne flotte hors des textures ; camera immobile, rien ne bouge.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-14
> bah oui faut que ça avance

### 2026-09-15
> j'ai testé un build il y a une heure environ ou les mini palmiers etaient bons, l'AOnsur les shrubs etait bon, mais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap eclairemais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap éclairé éclairé est toujours lamais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap éclairé est toujours là à regarde [Image #1] engre le mur de la hutte et le toit... ca va mas. mar xontre plus de damier ounpixelisatiengre le mur de la hutte et le toit... ca va mas. mar xontre plus de damier ou pixelisation  pixelisation

### 2026-09-15
> les mini palmiers j'ai déjà validé t'es relou et tu te fous de moi c'est pas possible ! Ensuite c'est obvious pour l'AO entre mur et toit que l'ombrage est pas pile a la jonction et qu'on voit un peu de blanc non ombré du mur pile entre le mur et le toit ! T'es relou !

### 2026-09-15
> c'est peut-être Lié à un flou "inconditionnel" qui va flouter l'AOnde contact au point de contact tout autant qu'à tout le reste ?

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

