# Handoff — ao-prepass-tie-alpha (essai 18, 2026-09-17)
DIRECTIVES vb025076084
## ETABLI (6 courses appareil eae4df44, md5 a2509c362a6699f3, 1920 img, crash=0)
- VERDICT H TENU. Le moteur trouve seul les aretes de contact : deprojection monde par la MEME
  fonction que les shaders, normales a +-4 px du pli, diedre >= 25 deg ; le SIGNE du repli se lit
  sur la corde de la profondeur (affine en ecran sur un plan : exact, sans matrice).
  `ao_hutedge_ref_overlap_x1000=933` — 14 des 15 aretes de l'essai 10, le contrat en veut 12.
  `ao_hutedge_ref_depth_px=425/425` : la camera du tick 1380 EST celle du tick 600, pas suppose.
- LE RACCORD DE SA CAPTURE A SA PROPRE MESURE, 708 cotes, 0 ecarte : livre
  `ao_hutedge_ref_ramp_bright_rate_x1000=11`, temoin `_legacy=175`, plan 160. Le regime d'AVANT
  est AU NIVEAU DU PLAN (aucune ombre de contact) ; le livre est 15x dessous. Plein ecran 55
  contre 178. Controle convexe 318 contre 317 — inchange, comme un controle doit l'etre.
- PORTE = 862, ET LES 862 SONT LA CLAUSE COULEUR. Les HUIT termes de defaut d'image de la hutte
  sont a ZERO et `missing_measurements=0` : les DEUX bras de la vue sont enregistres pour la
  premiere fois de l'item. Reste `color_changed_px=861` + `color_tie_changed_px=1`.
- LA PORTE NE SOMME PLUS QUE LA HUTTE (`view_scope=hut`, `ao_other_views_measured=0`) : les 4
  unites de village1-out et beach etaient un residu COMPTABLE.
- `debug.opengoal.ao.tie.reference` N'EST PAS UN INTERRUPTEUR DE FICHIER : il PATCHE quatre
  shaders (ao_tie_alpha_probe.cpp:421). La comparaison couleur oppose donc alpha-legacy a
  alpha-corrige, elle n'est pas vacuous. Mais l'image n'est pas reproductible : deux courses
  --off reference=0, meme binaire, rendent deux `ao_tie_color_image_hash` differents.
## TENTE, insuffisant
- Aucun changement de RENDU, et c'est un CHOIX : sur la population de sa capture le livre est
  deja 15x sous le bruit de plan. Retordre le flou la-dessus risquait l'acquis « plus de damier »
  (`ao_flatstep_worst_delivered_x1000=7`, plafond 10, contre 41 au temoin) pour rien. La revision
  qu'il a testee le 15/09 n'est pas identifiee : qu'il regarde CE build d'abord.
## RESTE
1. LES 861 PX : mesurer le PLANCHER d'abord — reference et comparaison au MEME variant de shader
   donnent le bruit seul, ce qui depasse est l'effet alpha. 2. Les 2 123 AUTRES aretes qualifiees
   n'ont aucun verdict de residu. 3. NE PAS REJOUER : candidats essai 13, reconstruction 11, supports reduits.
