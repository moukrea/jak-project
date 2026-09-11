# Le halo mesure pour de vrai : la sonde du chantier A n'a jamais tourne, et le cout en cadence n'est pas chiffre — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

RELEVE DU 11/09 SUR LA PREUVE DE `hdr-source-range` (reports/hdr-source-range/proof.txt). La porte du chantier A a tenu sur `hdr_src_clamped_stages` = 0 / 16 sources vues, mais la MOITIE HALO de son propre livrable n'a jamais ete mesuree : `hdr_src_glow_state` = 2, ce que hdr.cpp:695 traduit par « JAMAIS TENTE » ; `hdr_src_glow_frames` = 0, `hdr_src_glow_px` = 0, `hdr_src_glow_overbright_px` = 0. Ce zero-la ne dit pas « pas de depassement », il dit « pas de mesure ». Le site d'appel existe (sprite/GlowRenderer.cpp:667, dernier etage de la chaine de reduction) : il n'est atteint que si le halo DESSINE. La course de preuve n'est donc pas passee par un endroit qui en porte. Owner 11/09 : « c'est pas le portail de la jungle, c'est la hutte du Sage vert a Sandover Village ! et cet effet est visible sur tous les feux et portails de teleportation anyway ». Le ciel, lui, a bien ete mesure : 30 820 607 pixels sur 151 123 968 different du chemin 8 bits, mais `hdr_src_sky_max_x1000` = 996 et `hdr_src_sky_overbright_px` = 0 — le ciel a gagne de la PRECISION, pas de l'AMPLITUDE. AVERTISSEMENT DU WORKER DE `hdr-curve-input` (reports/hdr-curve-input/FINDINGS.txt) : `ref_peak_now` (hdr_output.cpp) et `probe_scene` (hdr.cpp) font des relectures SYNCHRONES pendant qu'on mesure. Toute cadence relevee sous instrument est fausse par construction.

## Livrable — le contrat, en entier

`hdr_glow_range_defects` = 0, somme de termes publies SEPAREMENT.
1. `hdr_glow_state` dit que la sonde A TOURNE. Les quatre raisons du retour anticipe de `probe_glow` (mesure eteinte, largeur nulle, hauteur nulle, cible trop grande) deviennent quatre valeurs publiees DISTINCTES : un zero ne doit plus jamais pouvoir se lire comme un « pas de depassement ».
2. `hdr_glow_frames` > 0 et `hdr_glow_px` > 0, avec le lieu de la course publie. La preuve passe par un endroit ou le halo dessine vraiment : un feu ou un portail de teleportation (hutte du Sage vert, Sandover Village).
3. `hdr_glow_overbright_px` et `hdr_glow_max_x1000` publies tous les deux. Un halo qui ne depasse jamais 1,0 est un RESULTAT, pas un echec — mais il doit etre MESURE et dit comme tel, jamais suppose. Publier le denominateur a cote.
4. Le cout en cadence sur le Redmi, AVANT et APRES, mesure HORS course de mesure : les sondes font des relectures synchrones, une cadence relevee sous instrument ne vaut rien. Publier les deux cadences, le nombre d'images de chaque releve, et le meme lieu pour les deux. La memoire est deja chiffree par le chantier A (6 904 320 o d'etages flottants, 196 608 o restes en 8 bits, 7 100 928 o au total) : la reprendre, ne pas la refaire.

## Hors perimetre

Ne change ni la courbe ni son ancre : c'est le chantier B. Le format du tampon de scene (`hdr_src_scene_fmt` = RGBA8) n'est pas de ce chantier. Aucun appareil code en dur.

## Ou l'owner regardera

Le halo : les feux et les portails de teleportation — hutte du Sage vert, Sandover Village.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

