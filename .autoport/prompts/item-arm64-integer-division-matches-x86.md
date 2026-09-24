# Sur le telephone, la division entiere donne exactement le meme resultat que sur PC (semantique 32 bits du jeu d'origine)

## Defaut cite
- 2026-09-25 : « Heuuuuu si ça induit des différences de comportement oui, si ça fait gagner de la perf en 64 c'est mieux et limite le pc devrait en bénéficier… donc ça dépend de ta réponse ! »

## Cause connue
Signale par le worker de perf-codegen-arm64-scalar (reports/.../FINDINGS.txt) : goalc/compiler/IR.cpp IR_IntegerMath::do_codegen_arm64 (IDIV/IMOD/UDIV/UMOD) divise sur 64 bits, alors que x86 fait idiv/div 32 bits + movsx (et la PS2 d'origine divise en 32 bits). Des que le dividende ou le diviseur sort du domaine int32 (bits hauts poses, valeur non signee), PC et telephone rendent des resultats DIFFERENTS : comportement du jeu propre au telephone. Aussi : goalc/compiler/compilation/Math.cpp compile_division garde le dividende contraint a RAX (X0) et RDX tenu pour ecrase sur arm64 (heritage x86) ; idiv_spill_*/imod_msub_gpr de IGenARM64.cpp ne sont plus appeles que par les tests (code mort).
COUT : aligner sur 32 bits ne coute rien en vitesse : sur arm64, SDIV/UDIV en registres W (32 bits) est aussi rapide ou plus rapide que la version X (64 bits) ; le PC utilise deja la division 32 bits, la plus rapide des deux sur x86.

## Livrable
1. arm64 : IDIV/IMOD/UDIV/UMOD en registres W avec la meme extension de signe que x86 (SDIV/UDIV Wd + SXTW), resultat identique a x86 pour TOUTE paire d'entrees.
2. Banc differentiel : memes paires (int32 extremes, INT_MIN/-1, valeurs 64 bits avec bits hauts, non signees) passees au code genere x86 et arm64 ; `int_div_arm64_x86_mismatch` = paires qui different ; doit valoir 0. Publier le nombre de paires testees.
3. Ne rien ralentir : publier le nombre d'instructions par division avant/apres (doit rester <= au lot perf-codegen-arm64-scalar).
4. Retirer le code mort (idiv_spill_*, imod_msub_gpr) s'il n'a plus d'appelant hors tests.

## Preuve exigee
`int_div_arm64_x86_mismatch == 0` dans `reports/arm64-integer-division-matches-x86/proof.txt`.
Le proof se produit par `lib/proof_run.sh arm64-integer-division-matches-x86 x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
