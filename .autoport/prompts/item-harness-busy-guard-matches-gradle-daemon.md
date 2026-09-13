# La garde « build en cours » ne prend plus le demon Gradle pour un build

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signalement du worker de hdr-shadow-range (essai 3, 13/09, FINDINGS.txt). `lib/proof_run.sh:~640` (`busy_procs`) teste ninja, goalc et cc1plus par `pgrep -x` sur le NOM du processus — ils meurent avec le build — mais Gradle par correspondance de LIGNE DE COMMANDE (`[g]radle`) : le demon Gradle porte la sienne en permanence et survit 3 h a l'inactivite. Batir un APK puis lancer une preuve donne un rc=3 DETERMINISTE tant que le demon vit, sur un build qui est fini depuis longtemps.

## Livrable
`busy_guard_false_positives` = 0, somme de termes publies SEPAREMENT.
1. LE COUT D'AVANT EST CHIFFRE : compte de sorties rc=3 « build en cours » dans les journaux archives de proof_run dont la seule cause etait un demon Gradle inactif (aucun ninja/goalc/cc1plus vivant, aucune ecriture d'APK dans la minute), publie par item ; non nul.
2. LA GARDE MESURE UN BUILD, PAS UN DEMON : Gradle n'est « en cours » que si une tache de build tourne (verrou de build, ecriture recente de l'APK ou processus fils de compilation), jamais par la seule presence du demon. Publier ce que la garde a lu et sa decision.
3. LE TEMOIN A DEUX BRAS : dans un bac a sable, un vrai build simule (APK en cours d'ecriture) est refuse ; un demon Gradle seul, inactif, est laisse passer. Les deux verdicts publies cote a cote.
4. AUCUN FAUX rc=3 APRES : sur les courses qui suivent la livraison, compte de refus « build en cours » sans build reel = zero, avec le compte de courses observees a cote (un zero sur zero est un defaut).
PREUVE : `FEATURE harness-busy-guard-matches-gradle-daemon armed=1 hits=<courses ayant passe la garde de build>` + la ligne `busy_guard_false_positives=` seule sur sa ligne ; `--off` rend `armed=0 hits=0`.

## Preuve exigee
`busy_guard_false_positives == 0` dans `reports/harness-busy-guard-matches-gradle-daemon/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-busy-guard-matches-gradle-daemon x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien a voir dans le jeu : c'est du harnais. L'effet se lit sur les essais qui ne meurent plus pour cette cause..

## Hors perimetre
Ne touche pas aux autres gardes de proof_run ni au validateur. Tout ce qui n'est pas cet item.
