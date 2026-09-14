> LIS D'ABORD `prompts/item-dead-literals-round-3-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le controle des particules et le nettoyage des shaders verifient des resultats reels

## Defaut cite
- 2026-09-14 : « Reprise superviseur requise pour : dead-literals-round-3. Ce… »

## Cause connue
Diagnostic superviseur 14/09 apres handoff et validator-002 : les deux termes existants sont a zero, mais le contrat demandait empreintes liees avant/apres et miroir POM d un programme deja supprime. Ordre owner 11/09 dans lighting-legacy-purge : « bah non faut supprimer le code ! On en veut plus, ca va etre refait, mieux, donc ca degage pour eviter de polluer ! » ; suppression c65c9a71bd, validee par l owner le 12/09. Ces exigences historiques sont donc remplacees explicitement par la conservat […suite dans le contrat]

## Livrable
`dead_literals_r3_defects` = 0, somme de TROIS termes publies SEPAREMENT et des penalites d infrastructure.
1. ASSERTION REELLE : conserver le banc avant/apres du vrai lecteur hdr_batches, reference cc00f44ca828075acb873078b41b8dd6b6436b13. Un compteur de particules fabrique incoherent est accepte AVANT et refuse APRES ; cadence correcte acceptee, melanges/valeurs manquantes traites explicitement, aucune relaxation des controles existants. Publier populations non vides et t1_defects.
2. NETTOYAG […suite dans le contrat]

## Preuve exigee
`dead_literals_r3_defects == 0` dans `reports/dead-literals-round-3/proof.txt`.
Le proof se produit par `lib/proof_run.sh dead-literals-round-3 x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Controle automatique des particules et de la generation des shaders ; aucun test visuel a demander..

## Hors perimetre
Reprise limitee au harnais (.autoport/lib/census/dead-literals-round-3.sh et bancs associes). Ne pas modifier le moteur, le preprocesseur de production ni la loi des particules. Executer les versions du preprocesseur dans des dossiers isoles hors /tmp. Aucun appareil, aucun build/deploiement reel, aucune campagne supplementaire, aucun changement de generic.sh. Les autres signalements restent hors perimetre.
