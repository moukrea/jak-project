# Handoff — ao-prepass-tie-alpha (essai 16, 2026-09-16)
DIRECTIVES v775512c234

## ETABLI (mesure)
- Code de l'essai 15 (`295bb10673`) COMMITE et DEPLOYE : md5 local == appareil == `129b167b003c5042df683b21afcbf944`. Aucun rebuild requis pour le remesurer.
- 2 courses appareil NEUVES (eae4df44 USB), 1860 images, crash=0, 430 s. Course 1 -> `notes/attempt16-run1-proof.txt`, course 2 -> `proof.txt`.
- Porte 7 -> 5, EXACTEMENT la valeur predite par `ao_tie_contract.h:187-210` : `7 = !measured + 3 vues x (!on+!off)`, `5 = hut.on enregistre, hut.off absent`. Modele de la porte verifie.
- Vue hut PROPRE, 7 termes mesures : `ao_geom_tie_absent_px=0`, `ao_contact_band_px=0`, `ao_direct_leak_px=0`, `ao_on_alpha_device_px=0`, `ao_pattern_over_ceiling=0`, `ao_high_not_fullres=0`, `ao_static_cam_delta_px=0`, `ao_flatstep_worst_delivered_x1000=7` (plafond 10), `ao_static_defects=0`, `ao_probe_compared=1`, `ao_probe_nondeterminism=0`.
- Le residu n'est PAS un defaut d'image : `village1-out` et `beach` n'ont aucun enregistrement et `proof_props` n'epingle qu'`ao.tie.view=village1-hut`. Plancher d'une course isolee = 4.
- Distance reelle au 0, decodee de `ao-tie-contract-campaign.bin` (campagne attempt5) : hut `color_changed_px=903`/`tie_changed=2` ; village1-out `direct_leak=6459`, `static_defects=260450`, `pattern=1`, `contact_band=6`, `color_changed=90534`, `tie_changed=105` ; beach `on_alpha=10`, `static_defects=832`. ~359 000 unites sur deux vues jamais travaillees.
- Candidat de l'essai 15 REMESURE INDEPENDAMMENT (banc `notes/attempt15-replay.py`, 425 px / 15 contacts, sorties `/tmp/a16-verify-on` et `/tmp/a16-verify-off`) : desarme K=0 -> bande SSAO 12 (max 3) / HBAO 2 (max 1) / GTAO 8 (max 2) ; arme K=0,25 -> 0 / 0 / 0 max 0 ; `flat_step` x1000 7,594 / 4,719 / 5,231 (plafond 10). `pixel_population_identical=true` sur les deux bras.
- `ao_sway_gap_px` BRUYANT : 2 (18:05), 0 (course 1), 4 (course 2), meme binaire et memes props, denominateur 109 965 px. `ao_owner_defects` bascule 0 -> 4 seul.

## TENTE
- Bras couleur (`ao.tie.reference=1` puis `=0`) pour enregistrer `hut.off` : ABANDONNE volontairement — attempt5 donne `color_changed_px=903` sur cette vue, le bras OFF ferait MONTER la porte de 5 a ~909. Deux courses auraient ete brulees pour aggraver le chiffre.
- Aucun changement de code : toucher au shader change le binaire et invalide la campagne ET la reference de la sonde, donc les deux courses du jour.

## RESTE
1. La porte ne peut pas etre fermee par cet item tel qu'il est cadre. A trancher devant l'owner : ramener la porte a la vue qu'il a signalee (hutte), ou ouvrir les chantiers `village1-out` (357 558), `beach` (842) et l'identite couleur (903).
2. Si on garde 3 vues : le 0 exige 9 courses sur un binaire GELE — par vue `--off reference=1`, puis ARME, puis `--off reference=0`, dans CET ordre (la sonde alterne strictement sauvegarde/comparaison ; tout bras ARME doit suivre une course qui sauvegarde).
3. `ao_contact_band_px` reste AVEUGLE au defaut de l'owner (0 sur appareil la ou le lecteur natif mesure 12 px au meme raccord) ; `ao_contact_profile::analyze` n'a aucun site d'appel.
4. Ne pas rejouer : les 4 candidats locaux de l'essai 13, la reconstruction de l'essai 11, les 3 variantes de support reduit.
