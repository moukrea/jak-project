# Nouvel écart extérieur : filtre TEX1
DIRECTIVES v6fca51fe40
- Capture extérieure candidat24/baseline8 : états enregistrés et LF identiques8/8 ; données/entrées/bootstrap/settings égaux.
- Comparaison indépendante : maxdiff6,diffpx2429,8images,aucune manquante ; bande x192..319,y63..72.
- Rejeu candidat24 exact ; producteur qualification_gate255, baseline-image-diff:origine/village1-out-h00.png ; replay_maxdiff254,aucune adoption.
- Le candidat supprimait les mipmaps demandées par TEX1 sous maîtreOFF ; compteur2276 avant h00,2336 après.
- Baseline : want_mipmap = MXL>0 && MMIN>=2, sans garde maître. Ocean far émet MXL6/MMIN4 (ocean.gc396), flush avant activation mipmaps mid (OceanMidAndFar.cpp77).
- Hypothèse à tester : rétablir exclusivement condition native baseline supprime ce nouvel écart. Aucun shader/océan/shrub/caméra modifié.
- Les cinq rejeux legacy du premier binaire restent archivés ; une nouvelle source/binaire change leur identité de qualification, sans réécriture de leurs reçus.
- Résultat mesuré après seul changement TEX1, binaire e46f852aaeb8c5a1 : extérieur8images maxdiff0/diffpx0, puis legacy8images maxdiff0/diffpx0 ; états8/8 identiques dans chaque bras. Notes tex1-{village1-out,legacy}-independent-*.
