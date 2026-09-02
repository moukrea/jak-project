# Gpbr-props-reach-draw — les proprietes PBR n'arrivent PAS au rendu

Refus de l'owner, 2026-08-31 :
  « j'ai l'impression que ça prend pas en compte les propriétés individuelles de Recharged
    assets et que ça applique le PBR uniquement aux 7 textures PBR qui étaient dans le
    projet depuis un bail et que ça ignore les autres »

## MESURE DEJA FAITE PAR LE SUPERVISEUR — ne pas la re-deriver
- `managed_assets/jak1/surfaces.json` contient bien **172 matieres**, 40 familles, avec de
  vraies valeurs (clearcoat, aniso, reflectance, metallic, normal_y).
- Ce fichier EST sur l'appareil, dans `files/managed_assets/jak1/surfaces.json`, **au md5
  pres identique** au notre. Ce n'est donc PAS un probleme de livraison.
- MAIS sur une course reelle du Redmi : **37 matieres distinctes enregistrees**, pas 172.
- Et surtout : **ZERO ligne** contenant `clearcoat`, `aniso`, `reflectance` ou `metallic`
  dans tout le journal de la course. Les FAMILLES sont lues, les proprietes fines
  n'apparaissent nulle part au moment du dessin.

=> La table est livree, la table est lue, et ce qu'elle contient ne semble pas atteindre
   le rendu. C'est exactement le defaut deja rencontre ici : des matieres qui lient leurs
   cartes sans qu'un seul jeu de reglages atteigne un draw (voir PITFALLS,
   « defaut IDENTITE = enregistrement non applique invisible »).

## Ce qu'il faut prouver
Pour CHAQUE matiere, publier la resolution complete jusqu'au draw : quelle entree de
surfaces.json a ete trouvee, quelles valeurs ont ete DEPOSEES dans les parametres du
shader, et si un draw les a consommees. Une matiere non authoree doit rendre EXACTEMENT
le defaut et le dire (`NO RECORD`), pas disparaitre du recensement.

## Format des marqueurs
    PBRREACH plateforme=<x86|redmi> matieres_dans_table=<n> matieres_rencontrees=<n> avec_record=<n> params_deposes=<n> draws_consommes=<n>
    PBRVAL matiere=<tpage/nom> famille=<f> clearcoat=<f> aniso=<f> reflectance=<f> metallic=<f> atteint_draw=<0|1>
Verifie : PBRREACH avec `params_deposes == matieres_rencontrees` et `draws_consommes >= 1` ;
au moins 20 lignes PBRVAL dont au moins 5 avec des valeurs NON par defaut et
`atteint_draw=1` ; et au moins une ligne sur l'appareil.
