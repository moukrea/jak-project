# Le bas de la plage : du detail dans les ombres, pas seulement dans les hautes lumieres — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

RETOUR DE L'OWNER DU 12/09, teste sur le HONOR, mot pour mot : « scRGB display HDR c'est ce que ca dit pour le HDR on/off sur HONOR, en effet toggled on on a plus de details/pop dans les hauts blanc/zones brillantes, peut-etre un chouille plus de saturation globale (vraiment un chouilla) et pas plus de detail dans les ombres.... peut etre que c'est vraiment le max de ce qu'on peut esperer en l'etat ? je sais pas »
LA REPONSE EST NON, ET ELLE EST MESUREE. Les ombres ne bougent pas PAR CONTRAT : le livrable de `hdr-output-regime` exige « aucun pixel ne passe sous le niveau SDR » et « aucun pixel sous le seuil declare n'est modifie ». Sa preuve rend `hdr_regime_below_sdr_px` = 0. Le chantier a donc fait exactement ce qu'on lui demandait : il a travaille le HAUT de la plage et interdit de toucher au bas. Personne n'a encore travaille le bas.
LA MATIERE EST LA. La meme preuve rend `hdr_regime_scene_fmt` = RGBA16F avec `chain_active` = 1 : la scene est calculee en flottant 16 bits quand la chaine d'eclairage recharge est allumee. La precision pres du noir existe donc ; ce qui manque, c'est ce qui en fait quelque chose.
ET LE HONOR CHANGE TOUT. Il annonce « scRGB display HDR », donc un regime AVEC marge, la ou le Redmi n'en accorde aucune. C'est le premier appareil du projet ou ce sujet est jugeable a l'oeil.

## Livrable — le contrat, en entier

`hdr_shadow_defects` = 0, somme de termes publies SEPAREMENT.
1. LE BAS DE LA PLAGE EST MESURE AVANT D'ETRE TOUCHE : publier, sur une scene sombre nommee, le nombre de paliers distincts rendus entre le noir et le premier dixieme de la plage, en sortie SDR et en sortie HDR. L'ecart est la grandeur qui compte. Si le compte est deja identique, l'item le DIT et s'arrete la : le defaut serait ailleurs.
2. LE GAIN EST DANS LE RENDU, PAS DANS LE CONTENEUR : publier separement les paliers que le conteneur PEUT porter et ceux que l'image porte REELLEMENT. Un conteneur plus large avec le meme nombre de paliers utilises n'est pas un gain.
3. RIEN NE S'ASSOMBRIT GLOBALEMENT. C'est le retour de l'owner du 11/09, il tient toujours : publier la luminosite moyenne de l'image, HDR eteint puis allume, sur la meme scene. Elle ne baisse pas.
4. LES HAUTES LUMIERES NE REGRESSENT PAS : reprendre les cles de `hdr-output-regime` et montrer qu'elles gardent leurs valeurs. Ce que l'owner voit deja ne doit pas etre echange contre ce qu'il ne voit pas encore.
5. LE REGIME EST EPINGLE ET PUBLIE : `chain_active`, `scene_fmt` et le regime de sortie a cote du verdict. Une mesure faite chaine eteinte, en 8 bits, ne dit rien de ce sujet.

## Hors perimetre

Ne touche pas au placement du blanc ni au choix du regime : `hdr-output-regime` les a tranches. Ne fabrique aucune difference sur un ecran qui n'accorde pas de marge.

## Ou l'owner regardera

Sur le HONOR, sortie HDR allumee : une scene sombre — interieur, grotte, nuit — et les zones d'ombre. Il doit y avoir plus de detail qu'en SDR, sans que l'image s'assombrisse globalement.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

