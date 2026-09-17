> LIS D'ABORD `prompts/item-ao-prepass-tie-alpha-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La prepasse d'AO garde les memes fragments que la couleur sur le TIE statique : plus d'ombre calculee a cote de la geometrie

## Defaut cite
- 2026-09-17 : « Pour l'AO, bah démerdes toi et fait le meilleur choix. »

## Cause connue
17/09 DECISION SUPERVISEUR (mandat owner) : HUTTE SEULE, 2 essais. Ordre : (1) armer le recensement sur la vue hutte (PrePass.cpp:1568 jamais atteint, `ao_tie_prepass_defects=` present, 7 termes mesures sur la hutte) ; (2) detecteur d'aretes qualifiees automatique (verdict H) ; (3) SEULEMENT ensuite la correction du raccord, par une des deux voies […suite dans le contrat]

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
