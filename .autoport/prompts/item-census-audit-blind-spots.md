> LIS D'ABORD `prompts/item-census-audit-blind-spots-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'audit du recensement voit aussi les drapeaux d'hote et les tables de surveillance

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
QUATRE SIGNALEMENTS DU 12/09 (reports/census-false-reds/FINDINGS.txt). L'audit qui vient de retirer trois cles infalsifiables garde quatre angles morts.
1. `hdr.cpp:296` : `RT_KNEE` est le dernier jeton de `kCompressionTokens` et n'a plus AUCUNE occurrence dans le CODE des shaders, une seule en commentaire. `tonemap_sites_shader` ne peut monter que si quelqu'un REMET l'identifiant : c'est une table de SURVEILLANCE, pas une mesure de l'etat courant, et un relecteur lit son zero comme « aucun shader ne compresse ».
2. L'audit juge les PORTES (uniformes) et les JETONS (tables de texte), pas les DRAPEAUX D'HOTE. `s_host_legacy` et `s_host_shade` selectionnent les seaux C et E : un seau rendu ina […suite dans le contrat]

## Livrable
`census_blind_spot_defects` = 0, somme de termes publies SEPAREMENT.
1. Une table de SURVEILLANCE est nommee comme telle et ne se lit plus comme une mesure : publier separement « jetons surveilles » et « jetons observes dans le code », et dire quand les deux divergent.
2. Les drapeaux d'hote entrent dans l'audit : publier le compte de seaux rendus inatteignables par un drapeau fige. Semer un drapeau fige et verifier que le compte monte.
3. Le detecteur de site d'appel cesse de raisonner a la ligne : publier le compte de sites trouves et le compte d'arguments illisibles, separement. Un argument illisible ne tombe plus vers le vert.
4. Un temoin ne peut plus etre un uniforme qu'un autre item d […suite dans le contrat]

## Preuve exigee
`census_blind_spot_defects == 0` dans `reports/census-audit-blind-spots/proof.txt`.
Le proof se produit par `lib/proof_run.sh census-audit-blind-spots x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Invisible. C'est l'instrument qui juge les instruments d'eclairage..

## Hors perimetre
Ne change aucun critere d'item. Priorite 34 volontaire : les chantiers d'eclairage passent AVANT.
