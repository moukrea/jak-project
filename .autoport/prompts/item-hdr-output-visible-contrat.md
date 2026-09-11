# La ligne de sortie HDR dit le regime COURANT, pas celui de l'ouverture du menu — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

TROIS SIGNALEMENTS DU CHANTIER C, 12/09 (reports/hdr-output-regime/FINDINGS.txt). Ils y sont explicitement laisses HORS PERIMETRE, et ils pointaient un id qui n'existait dans aucun item : cet item est cet id.
1. Le libelle de la rangee est reformate par `init-game-options`, qui ne tourne qu'a l'OUVERTURE du menu (progress-pc.gc:1769, appelants 12778 et 12908). Si le regime change PENDANT que la page est affichee — le joueur baisse la luminosite systeme, la marge mesuree passe au-dessus de 1,005 et le regime passe de R0 a R1 — la ligne montre encore l'etat de l'ouverture. Elle dirait « pas de marge » alors que la marge vient d'etre accordee.
2. La raison du regime est construite dans un tampon `char` STATIQUE unique dont `regime_now()` rend l'ADRESSE. Le code voisin `s_presents_reason` a le meme motif. Tous les appels connus sont sur le fil GL, mais rien ne prouve qu'aucun autre fil n'appelle `sdr_white_source()` : une chaine melangee se lirait comme une valeur, pas comme une course.
3. Le bras SIMULE du temoin prend `peak_nits() / kGraphicsWhiteNits` comme plafond, c'est-a-dire la marge que l'ecran accorderait S'IL PRESENTAIT. Sur un ecran qui presente REELLEMENT (regime R2) ce bras devient egal au bras livre et le temoin cesse de distinguer les deux. Aucun ecran R2 n'est disponible ici : c'est l'item qui jugera R1 et R2 qui doit donner au bras simule un plafond DIFFERENT de celui du bras livre.

## Livrable — le contrat, en entier

`hdr_visible_defects` = 0, somme de termes publies SEPAREMENT.
1. Le libelle suit le regime COURANT pendant que la page est affichee. Publier `hdr_visible_relabel_events` (le nombre de fois ou la ligne a ete recalculee page ouverte) et `hdr_visible_stale_frames` (images ou la ligne affichee contredit le regime courant) : le second est le verdict, le premier est son denominateur. Un zero d'evenements se lit « le regime n'a pas change pendant la mesure », jamais « rien a corriger » : la course doit FAIRE changer le regime et publier qu'elle l'a fait.
2. La raison du regime cesse de sortir par un tampon statique partage, ou bien un temoin publie prouve qu'un seul fil l'appelle — publier le compte d'appels par fil, pas une affirmation.
3. Le bras simule du temoin prend un plafond DIFFERENT de celui du bras livre, et la preuve publie les deux plafonds cote a cote. Sans ecran R2 disponible, publier que le cas R2 n'est pas mesure ici plutot que de le declarer tenu.
4. Rien de ce que le chantier C a livre ne regresse : reprendre ses cles de regime et montrer qu'elles gardent leurs valeurs.

## Hors perimetre

Ne change ni la courbe, ni le choix du regime, ni le transport retenu : c'est le chantier C qui les a tranches. On repare ce que la ligne DIT et ce que le temoin DISTINGUE.

## Ou l'owner regardera

Options > Recharged > Eclairage Recharge : la ligne de sortie HDR, page ouverte, pendant qu'on change la luminosite systeme.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

