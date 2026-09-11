# Le recensement d'eclairage ne publie plus de mesures fabriquees

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Quatre signalements du worker lighting-legacy-purge (11/09), non corriges a dessein : `kGateNames[2]`/`kGateTokens[2]` listent `u_rt_probe_on`, jeton qui n'existe plus que dans des COMMENTAIRES du blob livre — glGetUniformLocation rend -1 partout et `light_census_rb_bad_2` est EPINGLE a 0 par construction. `gate_probe(int)` n'a plus aucun appelant : le composite D est INATTEIGNABLE et le 3e terme du composite A est une TAUTOLOGIE. `shade_proof.cpp:128` pose `reads_a_gate` AVANT le test de commentaire : faux rouge latent, deja vrai pour 9 des 11 noms herites. `hdr.cpp:212` garde des jetons d'un shader SUPPRIME.

## Livrable
`census_unfalsifiable_gates` = 0 : aucune cle publiee par le recensement ne peut valoir sa valeur par construction. Pour chaque cle : nommer sa source, prouver qu'un changement du monde la fait bouger. Retirer les jetons morts des tables, et les commentaires qui les portent encore dans les shaders livres. ATTENTION : reduire une table RENOMME des cles publiees que d'autres portes lisent — publier la correspondance avant/apres.

## Preuve exigee
`census_unfalsifiable_gates == 0` dans `reports/census-false-reds/proof.txt`.
Le proof se produit par `lib/proof_run.sh census-false-reds x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : instrument ; owner_test=false.

## Hors perimetre
Ne pas toucher au rendu. On corrige ce que l'instrument affirme, pas ce qu'il regarde.
