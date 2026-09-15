# Lecture des producteurs existants

DIRECTIVES vf72d3bd470

`android/android_gfx.cpp:239-258` : maximum des parcours, total, frames rendues,
tentatives, diagnostics, rejets. Sans rejet ni diagnostic : tentatives = frames,
total = 2 * frames. Ne pas egaler ces populations au compteur global de frames.
`game/system/perf_instruments.cpp:629,812` : octets copies moyens par appel dans
la fenetre, non cumulatif ; copy_mode indique le chemin Android.
`game/system/perf_instruments.cpp:145-158` : activation par perf.buckets=1.

Reference historique relue (pas une preuve de cet essai) :
`reports/perf-dma-chain-copies/proof-engine.log:718507-718514` :
attempts=15060, frames=15060, total=30120, maximum=2, rejet=0,
diagnostics=0, bytes=1507328, copy_mode=1.
La ligne 818 contient l'information « doesn't SIGILL » : le mot SIGILL
isole ne permet pas de declarer un crash.

La selection USB par `bash .autoport/lib/pick_device.sh` a rendu `eae4df44`.
La preuve de cet essai doit etre acquise par proof_run apres toutes les editions.
