# Le tronc d'un mini-palmier ne s'ecrase pas comme un brin d'herbe, et ses feuilles restent solidaires — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

PRECISION SUPERVISEUR DU15/09 : actors=0 ne compte PAS Jak (seulement g_tramp_published). La reference rouge contient20616 echantillons Jak SHRUB et61848 TIE, binding_failures0 ; rejeu ancre tick603 et mouvement du clip120..249. Cela ne prouve pas l intersection avec le palmier, mais ne justifie pas de refaire le parcours au motif d absence de Jak. Lire notes/supervisor-contact-inputs-20260915.md ; exiger les captures de contact reel apres reparation. Aucun nouveau budget autorise.

REPRISE APRES ESSAI9 : le temoin instrumente f54ea18c485ca156816824522d2e67ece9bc3992 est prepare dans /home/emeric/code/jak-shrub-reference-602cd. Sa premiere configuration a ete refusee a tort par la garde CMake ; correction harnais 5471f0f7c6 testee (46 tests), commande exacte maintenant acceptee sans contourner la garde. Reprendre la compilation puis notes/attempt-9-protocol.md, avec sources et build propres a chaque bras. Ne pas refaire l audit/preparation termines. Budget appareil inchange 0/3. Diagnostic complet notes/supervisor-cmake-first-configure-20260915.md.

Signale par l'owner le 13/09. FAIT MESURE (investigation du 13/09) : `shrub.vert:20-21` inclut `tie_sway.glsl` et `vegetation_contact.glsl` et applique la loi de contact de l'HERBE (rayon 2,2 m autour de Jak, bande d'altitude -1,5..+2 m, MAX des echantillons) a TOUS les sommets du shrub, tronc compris. Un tronc n'est pas un brin : il ne doit pas se coucher, et les feuilles doivent rester attachees a lui. Il faut une classe par sommet ou par draw (tronc rigide / feuillage souple) — a etablir depuis les donnees (texture, hauteur au-dessus de la racine, prototype), jamais a la main.

## Livrable — le contrat, en entier

`shrub_trunk_squash_defects` = 0, somme de termes publies SEPAREMENT.
1. LE TRONC NE BOUGE PAS : deplacement maximal des sommets classes tronc sous contact, sur les mini-palmiers de Geyser Rock : zero au quantum pres, avec le compte de sommets tronc testes (non nul).
2. LES FEUILLES RESTENT ATTACHEES : ecart de deplacement a la jonction feuille/tronc (sommets partages ou coincidents) = zero ; les feuilles bougent toujours sous contact (deplacement max des sommets feuillage NON NUL — un zero global serait un defaut, pas une reussite).
3. LA CLASSE VIENT DES DONNEES : publier la regle de classement tronc/feuillage et le compte de sommets par classe et par prototype de shrub, sur les niveaux qui en portent ; aucune liste tenue a la main.
4. RIEN D'AUTRE NE CHANGE : le vent des shrubs (valide par l'owner le 13/09) et le contact de l'herbe gardent leurs cles ; OFF bit-identique par binaire-temoin.
PREUVE : `FEATURE shrub-trunk-contact armed=1 hits=<sommets de shrub classes>` + la ligne `shrub_trunk_squash_defects=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne change pas la loi de contact de l'herbe ni le vent. Tout ce qui n'est pas cet item.

Campagne explicitement autorisee par l owner le 2026-09-14 (« bah oui faut que ça avance »), proof_plan du backlog : instrumenter les deplacements reels tronc/feuillage et les paires de jonction ; Geyser Rock / training-warp, trois courses maximum au TOTAL de 130 s chacune, reference anterieure justifiee, ON corrige et OFF corrige. Preparer le parcours comparable et les instruments avant les courses ; conserver feuillage mobile, populations non vides, vent/herbe et OFF bit-identique. Les compteurs de pivots ne remplacent pas ces mesures. Aucune validation owner.

REPRISE SUPERVISEUR DU 15/09 : la preparation du TEMOIN et des entrees comparables est incluse dans l autorisation deja donnee, pas un nouveau chantier a attendre. Lire proof_plan.preparation du backlog. Preparer le binaire temoin 602cd72eb7 neutrement instrumente dans un checkout isole, ses archives par frame logique et leur comparaison au correctif ; traiter aussi horloges/etats du vent et de l herbe dans le seul chemin de preuve. Conserver les transformations/Loader/LUT propres a chaque binaire et comparer leurs sorties ; ne pas alimenter artificiellement le nouveau moteur avec les sorties de l ancien. La clause stop interdit les courses prematurees, PAS les modifications de preparation. Terminer ce travail avant de rendre la main ; ne pas repeter l audit essai8. La reference ne doit pas etre remplacee par le seul vieux shader dans le nouveau moteur. Bancs locaux autorises, aucune course supplementaire. Campagne toujours 0/3, trois bras reference/ON/OFF de130s maximum. Contrat de resultat, populations et acquis inchanges.

## Ou l'owner regardera

Sur Geyser Rock, marcher dans un mini-palmier : les feuilles s'ecartent, le tronc reste droit, rien ne se detache.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-13
> je sais pas pour qu'elle raison les mini palmiers... Les feuilles bougent quand on collisionne avec (ça OK) mais le tronc s'écrase aussi comme si c'était un vulgaire brin d'herbe c'est débile (et en plus les feuilles sont donc desolidarisees du tronc quand ça se produit).

### 2026-09-14
> bah oui faut que ça avance

### 2026-09-15
> Reprise superviseur requise pour : shrub-trunk-contact. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic.

### 2026-09-15
> j'ai testé un build il y a une heure environ ou les mini palmiers etaient bons, l'AOnsur les shrubs etait bon, mais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap eclairemais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap éclairé éclairé est toujours lamais le fait que l'AO est pas exactement aux zones de congact mais laisse un gap éclairé est toujours là à regarde [Image #1] engre le mur de la hutte et le toit... ca va mas. mar xontre plus de damier ounpixelisatiengre le mur de la hutte et le toit... ca va mas. mar xontre plus de damier ou pixelisation  pixelisation

### 2026-09-15
> les mini palmiers j'ai déjà validé t'es relou et tu te fous de moi c'est pas possible ! Ensuite c'est obvious pour l'AO entre mur et toit que l'ombrage est pas pile a la jonction et qu'on voit un peu de blanc non ombré du mur pile entre le mur et le toit ! T'es relou !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

