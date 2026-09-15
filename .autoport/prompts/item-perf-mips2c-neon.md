> LIS D'ABORD `prompts/item-perf-mips2c-neon-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Les calculs d animation et de particules coutent moins sans changer leurs resultats

## Defaut cite
- 2026-09-15 : « Reprise superviseur requise pour : perf-mips2c-neon. Ces pri… »

## Cause connue
Essai7 candidat3D retire :343 divergences/6048 x86 et163 ARM GCC. Banc Clang repare par choix explicite des CRT ARM :330/6048, cause de premiere operation encore non attribuee. Les trois compilateurs rejettent le candidat ; aucun gain ni resultat appareil. Essais5/6 : absence de troisieme cible et references phase1 incompletes provoquaient un arret avant toute experimentation locale. Reprise bornee a un candidat, sans appareil ; criteres finaux conserves. DIAGNOSTIC DE REPRISE : l hypothese de b […suite dans le contrat]

## Livrable
REPRISE LOCALE APRES LE REJET MESURE DE L ESSAI7 (15/09). Un candidat3D a effectivement ete compile et rejete pour divergence NaN, puis retire. Ne pas refaire la selection2D/3D ni relancer ce candidat inchange. Le banc Clang a ete repare par le superviseur : -B/usr/aarch64-linux-gnu/lib/ selectionne les CRT ARM au lieu des CRT x86 ; compilation0, 330 divergences/6048 cas sous Clang ARM Linux/QEMU. Corpus notes/supervisor-clang-20260915 (commande reproductible dans manifest.json). Ce banc ne vaut […suite dans le contrat]

## Preuve exigee
`mips2c_parity_defects == 0` dans `reports/perf-mips2c-neon/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-mips2c-neon device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse.

## Hors perimetre
Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.
