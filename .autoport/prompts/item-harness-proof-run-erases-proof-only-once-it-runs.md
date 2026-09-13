# Une course qui meurt a la porte ne detruit plus la preuve precedente

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker de hdr-shadow-range (essai 3, 13/09, FINDINGS.txt). `lib/proof_run.sh` efface `proof.txt` AU DEMARRAGE, avant ses gardes. Une course qui meurt sur « build en cours » a DEJA efface la preuve : celle du 12/09 de hdr-shadow-range (34 308 o, porte tenue) a ete detruite par une course qui n'a jamais amorce l'appareil. Seul `proof-prev.txt` a sauve les chiffres.

## Livrable
`proofs_erased_without_run` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE : compte de `proof.txt` effaces par une course sortie sur une garde (rc 3, 4) sans avoir lance le moteur, dans les journaux archives ; non nul.
2. L'EFFACEMENT SUIT L'AMORCAGE : `proof.txt` n'est efface qu'au moment ou le moteur ou l'appareil est effectivement lance ; toute sortie anterieure laisse la preuve intacte. Publier le point d'effacement et le rc de sortie.
3. LE TEMOIN A DEUX BRAS : bac a sable avec une preuve presente ; une course tuee par la garde la laisse (octets identiques), une course qui amorce l'efface. Les deux verdicts cote a cote.
4. `proof-prev.txt` RESTE : le filet actuel n'est pas retire ; publier qu'il est toujours ecrit.
PREUVE : `FEATURE harness-proof-run-erases-proof-only-once-it-runs armed=1 hits=<courses ayant amorce l appareil ou le moteur>` + la ligne `proofs_erased_without_run=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`proofs_erased_without_run == 0` dans `reports/harness-proof-run-erases-proof-only-once-it-runs/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-proof-run-erases-proof-only-once-it-runs x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais qui ne meurent plus pour cette cause..

## Hors perimetre
Ne change pas ce qui est mesure ni comment ; seulement QUAND l'ancienne preuve disparait. Tout ce qui n'est pas cet item.
