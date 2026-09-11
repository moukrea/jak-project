> LIS D'ABORD `prompts/item-hdr-output-visible-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La ligne de sortie HDR dit le regime COURANT, pas celui de l'ouverture du menu

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
TROIS SIGNALEMENTS DU CHANTIER C, 12/09 (reports/hdr-output-regime/FINDINGS.txt). Ils y sont explicitement laisses HORS PERIMETRE, et ils pointaient un id qui n'existait dans aucun item : cet item est cet id.
1. Le libelle de la rangee est reformate par `init-game-options`, qui ne tourne qu'a l'OUVERTURE du menu (progress-pc.gc:1769, appelants 12778 et 12908). Si le regime change PENDANT que la page est affichee — le joueur baisse la luminosite systeme, la marge mesuree passe au-dessus de 1,005 et le regime passe de R0 a R1 — la ligne montre encore l'etat de l'ouverture. Elle dirait « pas de marge » alors que la marge vient d'etre accordee.
2. La raison du regime est construite dans un tampo […suite dans le contrat]

## Livrable
`hdr_visible_defects` = 0, somme de termes publies SEPAREMENT.
1. Le libelle suit le regime COURANT pendant que la page est affichee. Publier `hdr_visible_relabel_events` (le nombre de fois ou la ligne a ete recalculee page ouverte) et `hdr_visible_stale_frames` (images ou la ligne affichee contredit le regime courant) : le second est le verdict, le premier est son denominateur. Un zero d'evenements se lit « le regime n'a pas change pendant la mesure », jamais « rien a corriger » : la course doit FAIRE changer le regime et publier qu'elle l'a fait.
2. La raison du regime cesse de sortir par un tampon statique partage, ou bien un temoin publie prouve qu'un seul fil l'appelle — publier le comp […suite dans le contrat]

## Preuve exigee
`hdr_visible_defects == 0` dans `reports/hdr-output-visible/proof.txt`.
Le proof se produit par `lib/proof_run.sh hdr-output-visible device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > Eclairage Recharge : la ligne de sortie HDR, page ouverte, pendant qu'on change la luminosite systeme..

## Hors perimetre
Ne change ni la courbe, ni le choix du regime, ni le transport retenu : c'est le chantier C qui les a tranches. On repare ce que la ligne DIT et ce que le temoin DISTINGUE.
