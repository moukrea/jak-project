> LIS D'ABORD `prompts/item-ao-prepass-tie-alpha-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La prepasse d'AO garde les memes fragments que la couleur sur le TIE statique : plus d'ombre calculee a cote de la geometrie

## Defaut cite
- 2026-09-15 : « j'ai testé un build il y a une heure environ ou les mini pal… »

## Cause connue
RETOUR OWNER 15/09 : bande claire persistante au CONTACT ENTRE MUR DE HUTTE ET TOIT, capture owner-feedback/2026-09-15-ao-hut-contact.png. Plus de damier/pixelisation et AO shrubs bonne sur le build teste. Le zero historique ao_contact_band_px NE COUVRE PAS ce defaut observe ; ne pas le defendre comme validation de cette jonction. Revision testee n […suite dans le contrat]

## Livrable
`ao_tie_prepass_defects` = 0, somme de termes publies SEPAREMENT.
1. LA CAUSE EST NOMMEE AVANT LE CORRECTIF : publier, pour un echantillon de fragments TIE jetes par la prepasse et gardes par la couleur, la valeur d'alpha vue par chaque passe et l'etat qui differe (compte par cause). Un correctif sans cette table est un essai a l'aveugle.
2. PLUS D […suite dans le contrat]

## Preuve exigee
`ao_tie_prepass_defects == 0` dans `reports/ao-prepass-tie-alpha/proof.txt`.
Le proof se produit par `lib/proof_run.sh ao-prepass-tie-alpha device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Recharged Lighting > Ambient Occlusion, sur le HONOR : chaque palier et chaque mode (SSAO, HBAO, GTAO), force au maximum. Aucun damier ni pixelisation, meme en Eleve ; aucune bande claire aux contacts ; sur les shrubs qui balancent, l'ombre suit le feuillage et rien ne flotte hors des textures ; camera immobile, rien ne bouge..

## Hors perimetre
Ne rouvre aucun des cinq acquis. Ne change ni l ordonnanceur, ni les populations, ni les criteres de la sonde de stabilite ao-static-probe-deterministic. Son raccordement a cet item est autorise pour produire ao_static_defects dans la preuve exigee : activer et reutiliser la MEME sonde et son lecteur, sans dupliquer leur logique ni reutiliser une v […suite dans le contrat]
