DIRECTIVES v3909a9767c
Cadrage owner : refonte lumière/HDR uniquement. Aucun travail nouveau HD/cache/allocateur/menu ; le SIGSEGV Swamp reste documenté dans essai43/crash-b3-review.md et invalide ce lot.

Cause mesurée héritée : ablation quatre props43 attribue l'essentiel du déficit pièce/portail à BAKED-MODULATION (modulation-comparison.json). Ne pas rejouer cette ablation.
SPEC-refonte-lumiere §2.3 cause2 : le baked est déjà une réponse d'éclairage ; son assombrissement/sa reteinte supplémentaire introduisent une double dose.
Correction bornée choisie : shade.glsl non-PBR shd_mul=vec3(1), retrait du RT_COOL dans cette seule branche. Lit_mul_y/g, terminateurs, PCF/occlusion, poids astraux et produit des deux facteurs conservés.
Formule : Fi=1+wi*termi*occi*(lit_mul_i-1), color=B*Fy*Fg. Face opposée/occultée revient au baked ; l'occlusion retire le surcroît lumineux, avec amplitude d'ombre réduite.
Aucun gain ou couleur nouveau, aucune correction globale de tone map ; la teinte éclairée existante demeure. Ce n'est pas la décomposition physique complète du baked.
Uniformes C++ et composition PBR inchangés : leurs défauts sont partagés, changer les defaults les aurait touchés silencieusement.
Invariants algébriques avant brouillard/composition : poids nuls ou deux lit_i nuls donnent B ; aux defaults lit_mul≥1.012 par canal, facteur≥1 ; occlusion plus forte ne peut accroître le supplément.
Ces invariants sources ne sont pas une preuve jeu. Compilation et run officiels du candidat requis ; ombres dynamiques perceptibles et qualité owner encore non prouvées.

Sol hutte : owner-regions du premier lot43 conserve unattributed_cases=[sage-hut-ground]. À h00/h12/h18, composition LF2767..2805/2975..3013/3079..3117 couvre ciel et sprites10012/10013/1395, jamais terrain/TIE/décal/ombre séparés.
shadow-geo peut multiplier les canaux du framebuffer (ShadowRenderer.cpp321..329/442..460), B peut les teinter ; aucun témoin existant n'attribue les petites zones owner à l'un d'eux.
La vue extérieure43 reste un repère géométrique jouable, pas une ROI sémantique du défaut. Les réglages owner et REFSET portent grass=false ; aucune interaction avec herbe procédurale activée n'est couverte.
Pas de modification d'herbe ni d'instrument pour obtenir un chiffre. PNG refset fixes320x180 (refset.cpp323..324), compteurs de composition natifs conservés ; détails pleine image au framebuffer non exportés par ce contrat.

Cycle autorisé : build gk Android incrémental unique, repack sans iso/GOAL ; deux campagnes distinctes pièce/portail h12 et extérieur h00/h12/h18, sources/options/hashes conservés.
Portail temporal2/settle660/loadsettle660, purge puis attente≥10s animées par bras ; extérieur temporal2/settle12/loadsettle240. Aucun neutre43, aucun menu/21niveaux/crash replay.
Les anciens lots43 restent diagnostics pour comparer avant/après ; ils ne qualifient pas le nouveau binaire. Absences et défauts restent rouges.

Réglages à distinguer : le fichier owner restauré43 contient recharged-lighting?=#t mais realtime-lighting?=#f (coverage/settings-original.ini66/82, SHA78108670…52fd6).
background_common.cpp2640 compose le sous-drapeau temps réel avec le maître ; refset.cpp1592..1602 force explicitement OG_RT_LIGHT=1 dans le bras RECHARGED.
Donc la preuve de ce candidat porte sur la sous-option temps réel activée, pas sur sa valeur OFF du fichier restauré. Ne pas présenter ce contraste de configuration comme une panne de menu ni modifier silencieusement la préférence.

Résultat portail candidat (proof_run, nouveau binaire) :401s/crash0/4620frames,4samples,21SHA conformes ; waitsON55.171/110.809s,OFF42.753/84.917s.
portal-comparison.json : RGB avant sprites ON/OFF1.004607/1.000086/1.003270 ; image luma91.2986/91.0989, détail20.1914/20.2160. Avant correction41 :64.2231/91.3654, détail15.7675/20.2218.
Rectangle inférieur pièce : luma103.7880/103.8264 et détail19.7274/19.7298 ; auparavant66.9608/103.8264 et12.8139/19.7298. Rectangles diagnostiques, pas qualification du sol extérieur.
Résidu conservé : portail_disc clipped403/329.5 et détail26.7144/27.5428, blancs36.5/33 ; image clipped1627/1370.5. Agrégat qualité_bad1/excess.clipped207, ownerfailed2/missing5/passed0, defects4.
Native portail7020pixels : avant sprites bleuON.457503/OFF.456012 ; après sprites bleuON1.518797/OFF.647979, delta somme7450.282/1347.608. Cela localise un résidu de composition sans attribuer sa cause exacte.
Captures ON/OFF consultées pour orientation ; elles ne remplacent aucun chiffre ni verdict.

Extérieur candidat :164s/crash0/1620frames,3paires h0/12/18,12samples/37SHA conformes, batch_errors0/quality_bad0 mais owner_missing5/passed0, defects4.
ground-comparison.json (ImageMagick existant) : delta luma image ON−OFF h0/12/18 avant −5.147/−9.933/−3.403 ; après +.014/+3.874/+3.648. Delta détail après −.006/+.705/+.961.
Rectangle chemin gauche [0,137,35,152] : delta luma avant −12.137/−51.697/−19.935 ; après −.017/+5.763/+.639. À midi delta détail −7.012→−.910, saturation −.006802→+.003026.
Rectangle entrée basse [82,119,153,148] : delta luma avant −11.433/−4.626/−6.467 ; après −.008/+10.669/+4.353. Éclairage ajouté subsiste : aucune identité ON/OFF revendiquée.
Ces rectangles ne contiennent aucun pixel violet270..330 mesuré avant/après aux trois heures : ils ne peuvent donc prouver la disparition des petites zones violettes de l'owner.
Image entière, fraction violette delta h12 +.003628→−.000139 ; h18 +.000122→+.000825. Le résultat couleur n'est pas uniformément meilleur, aucun verdict owner dérivé de ces moyennes.
