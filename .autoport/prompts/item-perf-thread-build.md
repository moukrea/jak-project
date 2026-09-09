# Le fil GOAL tourne sur un gros coeur, dans un binaire release

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Aucun thread n'a de priorite ni d'affinite (grep vide sur android/, game/system/, game/kernel/ ; SystemThread.cpp:120 = std::thread nu) ; seul le fil GL recoit THREAD_PRIORITY_DISPLAY par Java (SDLActivity.java:2158). Sur 2xA76 + 6xA55, EAS peut laisser opengoal-rt sur un A55. Manifeste sans appCategory=game ni profileable (AndroidManifest.xml:47-59). APK variante debug seule (build.gradle.kts:177-182), C++ en RelWithDebInfo -O2 -g (CMakeCache) contre -O3 sur desktop. Les traceurs codegen sont bien absents des CGO livres (verifie).

## Livrable
Affinite GOAL et GL sur les coeurs 6-7 et priorite relevee (posees dans android_goal_main.cpp:110 et android_renderer.cpp:59), nice negatif sur EE/GL cote PC (SystemThread), appCategory=game + profileable, variante release -O3 sans -g avec un build symbolise conserve a cote pour GK-DIAG. Le moteur publie cpu_core_goal_pct_big (part des images ou GOAL a tourne sur 6-7), sched_defects = (pct_big < 95) + (thermal throttling detecte sur 600 s) + (refset_replay_maxdiff != 0 apres recapture declaree). Les references refset sont recapturees UNE fois (le codegen flottant change avec -O3) et la cause de tout ecart nommee.

## Preuve exigee
`sched_defects == 0` dans `reports/perf-thread-build/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-thread-build device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la cadence en jeu, et la chauffe de l'appareil sur 10 minutes.

## Hors perimetre
Aucun changement de flags qui casse la parite x86 (pas de -ffast-math). Jamais la config systeme de l'appareil. Ne touche a aucune feature validee.
