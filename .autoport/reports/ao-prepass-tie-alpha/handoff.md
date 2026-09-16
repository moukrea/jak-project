# Handoff — ao-prepass-tie-alpha (essai 17, 2026-09-16)
DIRECTIVES v775512c234
## ETABLI (3 courses appareil eae4df44, 2 binaires, 1860 images, crash=0)
- Le bras TEMOIN du recensement d'AO etait MORT sur appareil : `PrePass.cpp:1605` tirait `st` de
  `g_static_probe.state`, et `kStates` vaut 6, donc `st / 6 == 0` toujours. REPARE (fenetre
  temoin au tick 1380, apres la sonde). Avant `ao_contact_pop_legacy_*=0` ; apres, `=17763`.
- `ao_contact_band_px=0` n'etait pas propre, il etait AVEUGLE : le temoin repare rend
  `ao_contact_band_legacy_px=225` contre 0 livre, et `ao_flatstep_worst_legacy_x1000=41` (plafond
  10) contre 7 livre — identique sur les 3 courses.
- `contact_band()` (`AmbientOcclusion.cpp:1319`) cherche un maximum local a 3 taps AU PLI ; le
  defaut est une rampe A COTE — banc : 0 sur un tampon APPAREIL qui PORTE le defaut. Instrument
  neuf publie A COTE (`ao_ramp_*`, `ao_plane_*`), l'ancien INCHANGE.
- Le plan est un zero d'instrument EXACT sur appareil : `ao_plane_lift_up_milli == _down_milli`
  (2077=2077 livre, 3230=3230 temoin). Exces de contact clair : 70 -> 27 milli, n=183036 cotes.
- Porte = 5, COMPTABLES : hut `missing_measurements=1` (bras OFF absent), out 2, beach 2 ; les 8
  termes de defaut de hut sont a ZERO, `ao_static_defects=0`, `ao_probe_compared=1`.
- Tout rebuild remet la campagne a zero (`ao_tie_contract.h:128`) ET la sonde a sa jambe de
  SAUVEGARDE : apres un rebuild, DEUX courses (sauvegarde puis comparaison).
## TENTE, insuffisant
- Comptages de rampe par seuil (C2/C3) : NOYES dans le bruit — plancher sur un VRAI PLAN 1,2435
  et 0,2071 par cote (~44000 et ~7300 transposes aux 35379 cotes) quand le correctif ne les
  deplace que de 3,7 % et 16 % : une porte `== 0` dessus est condamnee, ne les rejoue pas.
- La moyenne signee est non biaisee (0,002 erreur-type, plan confine) mais NEGATIVE des deux
  cotes sur la population globale : elle ne peut pas isoler le raccord, 22 cotes sur 35379.
## RESTE
1. LE CHANTIER : un detecteur d'aretes QUALIFIEES cote moteur. La population qui separe le defaut
   (15 aretes / 425 px ; 7 cotes clairs -> 0, Fisher p=0,0045) sort de deux triangles TFRAG
   choisis A LA MAIN parmi 75 (`notes/attempt10-contact-patches.json`) : sans detecteur, aucune
   porte de bande ne sera sensible ET atteignable.
2. Porte a 0 : 9 courses sur binaire GELE, et les termes couleur la feraient MONTER (hut
   `color_changed_px=903`). 3. NE PAS REJOUER : les 4 candidats de l'essai 13, la reconstruction
   de l'essai 11, les 3 variantes de support reduit, les comptages par seuil.
