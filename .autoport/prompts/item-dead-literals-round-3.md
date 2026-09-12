# Deux litteraux de plus rendent leur consommateur creux

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
DEUX SIGNALEMENTS DU 12/09 (reports/dead-published-keys-round-2/FINDINGS.txt). Le worker les a nommes chacun comme un item ; ils tiennent dans un seul, c'est la meme classe.
1. `lib/hdr_batches.py:709` : `options.get('particle_step_const') != 'once-per-logic-frame'` est une ASSERTION VIDE. La valeur qu'elle verifie est une chaine litterale posee par le code lui-meme : la condition ne peut donc jamais etre vraie, et le protocole qu'elle est censee garantir n'est verifie par personne.
2. `shaders/pbr_fused.glsl:165-171` : `float tess_w = 0.0;` est un LITTERAL depuis le retrait de l'etage de tessellation. Tout ce qui en decoule — `tess_displaced` et sa branche — est du code mort dans un shader fige dans les chunks cote Android. Le prochain qui lira ces lignes croira toucher un deplacement qui n'existe plus.
Meme classe que les cinq clés que le chantier precedent vient de retirer : une valeur decidee a l'ecriture rend creux tout ce qui la consomme.

## Livrable
`dead_literals_r3_defects` = 0, somme de DEUX termes publies SEPAREMENT.
1. L'assertion cesse d'etre vide : soit elle verifie une valeur qui peut varier, soit elle disparait avec ce qu'elle pretendait garantir. Publier, sur le commit d'AVANT, la preuve qu'elle ne pouvait pas echouer — une valeur fabriquee qui aurait du la declencher et ne la declenche pas — et sur celui d'APRES, qu'elle se declenche.
2. La branche morte du shader part avec son litteral. Publier le compte de lignes de GLSL retirees et l'empreinte du programme lie AVANT et APRES : elle doit changer, sinon le compilateur les avait deja jetees et l'item doit le DIRE au lieu de revendiquer un gain.
3. Aucun rendu ne change : reprendre les cles de couverture du chantier precedent et montrer qu'elles gardent leurs valeurs, le miroir CPU du POM compris.

## Preuve exigee
`dead_literals_r3_defects == 0` dans `reports/dead-literals-round-3/proof.txt`.
Le proof se produit par `lib/proof_run.sh dead-literals-round-3 x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. Aucun pixel ne bouge..

## Hors perimetre
Ne touche pas au reste du shader ni aux protocoles voisins. Priorite 36 : tout le reste du jeu passe avant.
