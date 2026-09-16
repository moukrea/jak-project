DIRECTIVES v775512c234
## ÉTABLI (essai 13, mesuré)
Course USB NEUVE eae4df44, 840 images, crash=0, 158 s, sha c0072ca1b597bb50, arbre PROPRE.
Les 7 termes owner valent 1 par ABSENCE d'instrument (ao_owner_terms_measured=0), pas par défaut.
pattern_census() jamais appelé : ao_flat_dbg_visited=0, ao_census_frames_*=0 (12 états), q0..2=0.
Amont : wind_on_acquisition_mask=0 _missing=6, samples=0, compared=0, cam_pairs=0 ; et
ao_probe_wind_on_acquisition_frames ABSENT — PrePass.cpp:1570 jamais atteint. Identique au 15/09
avec un AUTRE binaire : structurel, pas un aléa de course.
ao_tie_prepass_defects ABSENT : campagne jamais armée (props manquantes) ET want.display attendu
"beach,display" en dur (ao_tie_contract.h:93) contre "village1,display" posé : identity_mismatch.
CAUSE DU DÉFAUT, CHIFFRÉE : au raccord (100,550) le tap qui tombe sur le TOIT garde 96,7 % de son
poids (rz=1,498e-4 ; zsig=5,81e-4). Contact 25 brut -> 52 après les deux passes de pas 1 -> 85
après celles de pas 2 -> 141 final, intérieur du mur 130 : ce sont les boîtes LARGES qui l'effacent.
Géométrie : creux de contact 3 px, support composite 29 texels, plis 35..41 % de l'écran au pas 5.
## TENTÉ — quatre candidats locaux, tous REFUSÉS par la mesure (sources dans notes/)
relocate (voie imposée 16/09, taps déplacés de 4 pas, phases exactement conservées) : bande 17/7/10
contre 12/2/7 livré — PIRE — et flat_step 54/39/41, plafond 10.
foldbound (borne au pli, pas 2..5) : bande 8/0/1, flat_step 30/25/25. creasebound (pli au TEXEL) :
bande 5/3/4, 16 témoins changed=0, FOLD_PHASE R8 max_range=0 (R32F 2,37e-5 = 0,006 quantum) — mais flat_step 33/31/30.
bound2 / bound23 (pas 2 seul / pas 2 et 3) : flat_step 8/5/6 et 10/7/8, SOUS le plafond, mais bande
9/2/7 et 13/8/11 : ils ne corrigent rien. Aucun réglage ne tient les deux à la fois.
Mécanisme : la borne est BINAIRE par pixel ; deux voisins qui la prennent différemment reçoivent des quantités de flou différentes, et flat_step compte les marches des pixels PLANS qui BORDENT un pli.
## RESTE
1. Armer le recensement AVANT toute correction : sinon aucune preuve de cet item ne mesure rien.
   Départ : pourquoi PrePass.cpp:1568 n'est pas atteint (color_frame ? effective_mode ?).
2. Faire trancher l'owner : ombre pile au contact CONTRE plafond flat_step 10, ils se combattent.
3. Ne pas rejouer : déplacement/annulation des taps traversants ; borne de sortie des boîtes larges
   à tout sous-ensemble de pas. Déjà exclus : enveloppe concave, réflexion, rayon réduit, pli local.
4. Non testé : restauration APRÈS le flou au profil CONTINU, ou estimateur au creux plus large que 3 px — les deux hors clause « ni élargir ni réduire le support » : arbitrage avant de coder.
5. Recette : notes/attempt13-{commands.md,flatstep.py,summary.md}.
