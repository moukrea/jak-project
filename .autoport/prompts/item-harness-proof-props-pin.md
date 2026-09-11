> LIS D'ABORD `prompts/item-harness-proof-props-pin-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Un worker doit pouvoir epingler le regime de SA course, et le verifier

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
SIGNALEMENT DU 11/09 23:33 (reports/hdr-glow-range/FINDINGS.txt, dernier point). Le worker a ecrit `proof_props: debug.opengoal.recharged=0` sur son item et `proof_run.sh` a relu 1 dans la MEME minute. Il a contourne en posant la propriete depuis l'hote pendant l'amorcage et en VERIFIANT par une cle du proof (`hdr_glow_fmt_latched_float`).
ATTENTION — LE MECANISME QU'IL NOMME N'EST PAS ETABLI. Il accuse l'orchestrateur de reecrire `backlog.yaml` depuis sa copie memoire. La lecture du code ne le soutient PAS : `set_status` (lib/backlog.py:202) prend le verrou, RELIT le disque, ne pose que les champs passes, et reecrit ce document frais ; `load_backlog()` (orchestrator.py:438) relit a chaque t […suite dans le contrat]

## Livrable
`pin_props_defects` = 0, somme de termes publies SEPAREMENT.
1. LA PERTE EST REPRODUITE ET SON ECRIVAIN EST NOMME. Un test ecrit un champ sur un item pendant qu'un tour d'orchestrateur passe, et publie qui l'a efface — ou publie que RIEN ne l'efface, auquel cas la cause est ailleurs et l'item la nomme. Un zero de perte se lit « pas reproduit », jamais « repare ».
2. Le chemin de lecture de `proof_props` est trace de bout en bout : ce que le fichier porte, ce que `proof_run.sh` extrait, ce que l'appareil rend a `getprop`. Publier les trois. L'ecart entre le premier et le troisieme est la grandeur qui compte.
3. Une course publie DESORMAIS le regime OBSERVE, pas le regime demande : au moins un […suite dans le contrat]

## Preuve exigee
`pin_props_defects == 0` dans `reports/harness-proof-props-pin/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-props-pin x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Le harnais : lib/backlog.py, orchestrator.py, lib/proof_run.sh..

## Hors perimetre
Ne touche a aucun code du jeu. Ne change aucun statut d'item existant.
