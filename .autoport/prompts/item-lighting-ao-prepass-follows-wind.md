> LIS D'ABORD `prompts/item-lighting-ao-prepass-follows-wind-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# L'ombre d'occlusion suit le feuillage qui balance, au lieu de rester au sol

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md sections 4.1, 4.2, 4.6. ACQUIS DE lighting-ao-indirect (essais 6 a 11, preuves Redmi du 14/09) A NE PAS ROUVRIR : fuite du direct = 0 ; damier des facades sous le plafond (0) ; alpha respecte sur l'appareil vent allume (0) ; palier Eleve en pleine resolution (0). Decision de l'owner du 14/09 15:30 : « ok, si ca bloque decoupe en trois comme tu proposes ». LE SEUL TERME ENCORE ROUGE a l'essai 11 : ecart prepasse/scene sous vent de TIE = 1 826 px (Redmi, […suite dans le contrat]

## Livrable
`ao_prepass_sway_px` = 0, somme de termes publies SEPAREMENT.
1. L'ECART EST NUL SUR L'APPAREIL : pixels de TIE au vent dont la profondeur de prepasse differe de la profondeur de scene de plus d'un quantum = zero, sur une course Redmi vent allume d'au moins 2 000 images, avec le compte de pixels compares (non nul).
2. LA CAUSE EST FERMEE, PAS CONTOURNEE : compte de draws TIE presents dans la passe couleur et absents de la prepasse = zero ; publier les deux populations et l'etat d'echantillonnage […suite dans le contrat]

## Preuve exigee
`ao_prepass_sway_px == 0` dans `reports/lighting-ao-prepass-follows-wind/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-ao-prepass-follows-wind device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur le Honor, en exterieur, pendant que les buissons et les arbres balancent : l'ombre au sol et l'assombrissement du feuillage SUIVENT la plante ; plus d'ombre qui reste a la place initiale. Puis chaque palier de qualite : pas de damier (acquis)..

## Hors perimetre
Ne change ni le filtre du damier, ni la bande de contact, ni la stabilite camera fixe. Ne rouvre AUCUN des quatre acquis. Tout ce qui n'est pas cet item.
