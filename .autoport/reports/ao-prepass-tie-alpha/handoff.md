# Handoff — ao-prepass-tie-alpha (essai 17, 2026-09-16)
DIRECTIVES v775512c234
## ETABLI (mesure, 3 courses appareil eae4df44 aujourd'hui, 2 binaires, 1860 images, crash=0)
- Le bras TEMOIN du recensement d'AO etait MORT sur appareil : `PrePass.cpp:1605` tirait `st` de
  `g_static_probe.state` et `kStates` vaut 6, donc `st / 6 == 0` toujours. REPARE (fenetre temoin
  au tick 1380, apres la sonde). Avant : `ao_contact_pop_legacy_*=0`. Apres : `=17763`.
- `ao_contact_band_px=0` n'etait pas propre, il etait AVEUGLE : le temoin repare rend
  `ao_contact_band_legacy_px=225` contre 0 livre, et `ao_flatstep_worst_legacy_x1000=41`
  (plafond 10) contre 7 livre. Reproduit a l'identique sur les 3 courses.
- Le critere de `contact_band()` (`AmbientOcclusion.cpp:1319`) cherche un maximum local a 3 taps
  AU PLI ; le defaut est une rampe A COTE. Banc : il rend 0 sur un tampon APPAREIL qui porte le
  defaut. Instrument neuf publie A COTE (`ao_ramp_*` / `ao_plane_*`), l'ancien INCHANGE.
- Le plan est un zero d'instrument EXACT sur appareil : `ao_plane_lift_up_milli == _down_milli`
  (2077 = 2077 livre, 3230 = 3230 temoin) — moyenne de levee nulle au milli pres.
- Exces de contact clair au-dessus de ce zero : 70 (temoin) -> 27 (livre), milli, n=183036 cotes.
- La porte vaut 5, et les 5 sont COMPTABLES : hut `missing_measurements=1` (bras OFF absent),
  `village1-out` 2, `beach` 2 ; les 8 termes de defaut de hut sont a ZERO. `ao_static_defects=0`,
  `ao_probe_compared=1`, `ao_probe_nondeterminism=0`. Tout changement de binaire remet le fichier
  de campagne a zero (`ao_tie_contract.h:128`) et la sonde a sa jambe de SAUVEGARDE : apres un
  rebuild il faut DEUX courses (sauvegarde puis comparaison) pour revenir a 5.
## TENTE, et pourquoi ca n'a pas suffi
- Deux regles de comptage de rampe (seuil par pixel, C2/C3) chiffrees localement : NOYEES dans le
  bruit. Plancher sur un VRAI PLAN 1,2435 et 0,2071 par cote, soit ~44000 et ~7300 transposes aux
  35379 cotes de plis ; le correctif ne deplace ces chiffres que de 3,7 % et 16 %. Une porte
  `== 0` sur ces regles est condamnee par le bruit — ne les rejoue pas telles quelles.
- La moyenne signee, elle, est non biaisee (0,002 erreur-type sur un plan confine) — mais sur la
  population GLOBALE de plis elle est negative des DEUX cotes : l'agregat ne peut pas isoler le
  raccord de l'owner, qui ne pese que 22 cotes sur 35379.
## RESTE
1. LE CHANTIER : une population d'aretes QUALIFIEES cote moteur. Celle qui separe le defaut
   (15 aretes / 425 px ; 7 cotes clairs -> 0, Fisher p=0,0045) sort de deux triangles TFRAG
   choisis A LA MAIN parmi 75 (`notes/attempt10-contact-patches.json`). Sans detecteur, aucune
   porte de bande ne sera a la fois sensible et atteignable.
2. Porte a 0 : exige 9 courses sur binaire GELE, et les termes couleur la feraient MONTER
   (hut `color_changed_px=903` a la campagne attempt5). A trancher devant l'owner.
3. Ne pas rejouer : les 4 candidats locaux de l'essai 13, la reconstruction de l'essai 11, les 3
   variantes de support reduit, et les regles de comptage par seuil ci-dessus.
