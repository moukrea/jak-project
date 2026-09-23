# harness-prompt-fingerprints-absolute-path — essai 1

DIRECTIVES vaf9b78bf58

**Verdict** : l'empreinte des consignes est ancree sur `backlog.py` et plus sur le cwd ; `prompt_fingerprints_misplaced=0`, controles semes vivants.

## Ce qui a change
- `lib/backlog.py` : `_FINGERPRINTS = os.path.join(AP, ...)` ; `_fp_path(ap_dir)` : l'empreinte suit l'`ap_dir` de la consigne (test/migration dans leur propre magasin, plus dans le vrai) ; un echec d'ecriture de l'empreinte s'ecrit sur stderr au lieu d'etre avale.
- `lib/prompt_origin.py` (neuf) : rejeu git — une consigne « a-la-main » egale a l'octet au rendu d'un commit passe (backlog.py + backlog.yaml DE ce commit) est prouvee notre fabrication.
- `lib/census/harness-prompt-fingerprints-absolute-path.sh` : P (sonde depuis 6 cwd + ap_dir etranger, copie jetable), F (magasins hors d'un ap_dir, 8 arbres + /tmp + $TMPDIR), T (consignes a tort), L (constante relative, AST sur 147 fichiers).
- Reparation : 24 consignes « a-la-main » prouvees etre nos rendus ont retrouve leur empreinte (`notes/adopt.log`, sauvegarde `notes/prompt_fingerprints.before.json`) ; les 9 ouvertes refabriquees (water-* x6, lighting-shadows, perf-stock-60, recharged-secondary-motion), les 15 validated/archived restent « perime ».

## Preuve (proof.txt)
    proof_census_rc=0
    prompt_fingerprints_probe_total=7
    prompt_fingerprints_probe_failed=0
    prompt_fingerprints_ctl_cwd_failed=11
    prompt_fingerprints_stray_stores=0
    prompt_hand_written_wrongly=0
    prompt_fingerprints_dead_controls=0
    prompt_fingerprints_misplaced=0
Denominateurs : 7 sondes, 4 magasins trouves, 381 items (6 « a-la-main » rejoues), 147 sources.
Controle positif C+cwd (ancienne ligne relative) : 11 defauts NOMMES (autoport/lib/prompts/ailleurs/leurre geles + magasin egare du leurre) ; C+tort nomme sa consigne ; C+disk nomme le magasin seme. Negatifs : code livre P=0, texte manuel non adopte, magasin d'ap_dir non accuse. Mutation du predicat F -> C+disk mort (verifie a la main).

## Ce que l'owner doit regarder
Rien dans le jeu. Les 9 consignes ouvertes refabriquees portent maintenant leur contrat a jour.

## Non prouve
- non prouve : absence de course entre deux ecrivains simultanes du magasin (pas de verrou) -> FINDINGS.
- non prouve : origine des 6 consignes restees « a-la-main » au-dela des 6 derniers commits de chacune.
- Tests : `tests/harness/test_backlog.py` + `test_state.py` 71/71.
