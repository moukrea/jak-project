# Reprise ciblée — essai 31
DIRECTIVES v6fca51fe40
Lecture seule par deux researchers gpt-6-astra/high ; implémentation gpt-6-astra/medium.

Cause lue : target-death.gc suspend target-continue avant de recopier lev0/disp0/lev1/disp1
dans *load-state*. Réappliquer juste après start serait écrasé. Le dispatcher exécute
le listener avant les processus ; restauration proposée après dispatch à ancre+2.
Le caractère suffisant de ce délai reste à vérifier par la trace d'exécution.

Témoins existants conservés : bootstrap17 scellé (pas de nouveau checkpoint ajouté),
manifestes18 des buffers consommés, snapshots après dispatch de l'essai30 et trace
OG_PAD_REPLAY_TRACE (CAM : 80 octets caméra, 12 octets position Jak).
Les champs de la trace pad sont indexés relativement à son ancre ; ne pas les confondre
avec la frame absolue de la chaîne DMA.

Limites lues : les snapshots loaded-state attestent target présent, spawn/sweep,
noms/statuts de niveaux ; ils ne comparent pas PID/états des autres acteurs ni RNG.
Les checkpoints détaillés acteurs/RNG du bootstrap finissent au scellement.
Les sidecars v2 identifient case/config/bin/flavour/png/capture_lf/data/input mais
ne restaurent pas l'état postload. Aucun nouveau champ de preuve ne doit déclarer
ces faits acquis en se fondant sur la présence d'un sidecar.
La qualification v2 reste refusée ; aucun cinq-rejeux vide, aucune adoption historique.

Les fichiers de réglages portables (debug/display/input/settings.ini) peuvent être
hashés avant/après chaque bras ; cela ne constitue pas le snapshot de toutes les
valeurs effectives dans pc-settings/g_global_settings au moment du rendu.
