# L'ombre d'occlusion suit le feuillage qui balance, au lieu de rester au sol — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD prompts/SPEC-refonte-lumiere.md sections 4.1, 4.2, 4.6. ACQUIS DE lighting-ao-indirect (essais 6 a 11, preuves Redmi du 14/09) A NE PAS ROUVRIR : fuite du direct = 0 ; damier des facades sous le plafond (0) ; alpha respecte sur l'appareil vent allume (0) ; palier Eleve en pleine resolution (0). Decision de l'owner du 14/09 15:30 : « ok, si ca bloque decoupe en trois comme tu proposes ». LE SEUL TERME ENCORE ROUGE a l'essai 11 : ecart prepasse/scene sous vent de TIE = 1 826 px (Redmi, 2 280 images, 15:53 ; 3 335 sur PC le matin). Cause NOMMEE par le worker (commits 15:39 et 15:55, deja dans l'arbre) : la prepasse SUR-DECOUPE — 100 % du TIE absent est de la geometrie que la passe couleur dessine et que la prepasse ecarte ; elle heritait son etat d'echantillonnage au lieu de le poser (12 570 liaisons). Fait mesure le 13/09 : `prepass_world.vert:29-38` lisait la position brute quand `tfrag3.vert:66` applique `tie_sway_apply` ; le vent des shrubs est deja suivi (26,7 % -> 0,31 %), pas celui des TIE. Piege : trois essais de cet item sont morts pour un fichier edite APRES la preuve — mesure PUIS rends la main, jamais l'inverse.

## Livrable — le contrat, en entier

`ao_prepass_sway_px` = 0, somme de termes publies SEPAREMENT.
1. L'ECART EST NUL SUR L'APPAREIL : pixels de TIE au vent dont la profondeur de prepasse differe de la profondeur de scene de plus d'un quantum = zero, sur une course Redmi vent allume d'au moins 2 000 images, avec le compte de pixels compares (non nul).
2. LA CAUSE EST FERMEE, PAS CONTOURNEE : compte de draws TIE presents dans la passe couleur et absents de la prepasse = zero ; publier les deux populations et l'etat d'echantillonnage POSE par la prepasse.
3. LES QUATRE ACQUIS TIENNENT : reprendre `ao_owner_term1_direct_leak`, `term2_pattern`, `term4_alpha_device`, `term7_high_res` et montrer qu'ils valent encore zero dans la MEME preuve.
4. LE COUT EST PUBLIE : total GPU par image sur le Redmi avant/apres, et le compte de draws ajoutes a la prepasse.
PREUVE : `FEATURE lighting-ao-prepass-follows-wind armed=1 hits=<pixels de TIE au vent compares entre prepasse et scene>` + la ligne `ao_prepass_sway_px=` seule sur sa ligne ; `--off` rend `armed=0 hits=0` dans la MEME scene.

## Hors perimetre

Ne change ni le filtre du damier, ni la bande de contact, ni la stabilite camera fixe. Ne rouvre AUCUN des quatre acquis. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur le Honor, en exterieur, pendant que les buissons et les arbres balancent : l'ombre au sol et l'assombrissement du feuillage SUIVENT la plante ; plus d'ombre qui reste a la place initiale. Puis chaque palier de qualite : pas de damier (acquis).

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

