## ONE TASK. MANAGER verifies personally: the acceptance is VISIBLE sway in a video, not a metric.

# Phase Grecharged-foliage-wind2 — ROUND 2. Round 1 shipped an invisible effect.

## Owner verdict (2026-07-14, verbatim): "on voit aucune feuille qui bouge, aucun palmier, nada !"
Supervisor reproduced it PERSONALLY on the Redmi with the PUBLISHED APK via the owner flow:
- The code path activates (toggle -> ON, TIE shear ACTIVE mult=3, shrub sway ACTIVE) — delivery is fine.
- BUT the measured palm-crown motion is OFF=3.51 vs ON=3.82 (+9%) — VISUALLY NOTHING. Round 1's
  "doubled cells" metric was cherry-zoned; the global effect is negligible.
- Census: some trees have ZERO wind draws (village1 tree=0 wind_draws=0) — coverage holes.

## Mandate (single defect: make the breeze VISIBLE)
1. COVERAGE: census every palm/shrub/tree instance at beach + village1 — why do some trees carry no
   wind draws (tree=0)? Every palm crown and shrub must be in the wind set (or named exception).
2. AMPLITUDE: the shear mult=3 is far too weak. Find the lever that produces CLEARLY VISIBLE, natural
   sway (leaves/fronds visibly waving in a 10s video at the beach vantage) without looking like a storm:
   tune mult (prop exists), and if shear alone can't reach visible-but-natural, add a slow position/
   vertex wave for fronds. "Légère brise" = the owner's bar: obvious when you look at a palm, subtle
   enough to be believable.
3. ACCEPTANCE (hard): same-pose OFF/ON videos at beach; the ON video must show sway a human sees at a
   glance. Quantified floor: palm-crown top-half inter-frame motion ratio ON/OFF >= 2.0 measured by the
   supervisor's own script (not grid cells). fps cost still <= 0.5. OFF == stock.
4. Real install flow (published-APK-equivalent build), force-stop after runs. Report RESULT + honest
   numbers. Max: max_turns 2400, max_retries 5.

## REJET + PRÉCISION OWNER 2026-08-08 08:30 — PAS VALIDÉ
« Je ne savais pas que certains palmiers avaient une animation de base quand j'ai spécifié cette
tâche. »  => la demande se reformule en TROIS points :
  1. **Ceux qui avaient déjà une animation doivent l'avoir VRAIMENT et FONCTIONNELLE, telle que
     prévue par le jeu d'origine.** Ce n'est pas « amplifier » : c'est restituer l'intention ND.
  2. **Ceux qui n'en ont pas doivent en recevoir une, PLUS LÉGÈRE que celle des arbres déjà animés
     dans le jeu d'origine.** Donc la hiérarchie est explicite : stock-animé > ajouté.
     (Ça répond aussi à l'arbitrage que j'avais posé : oui, on couvre les 27 palmiers gelés de
     village1 et la jungle — mais en dessous du niveau des arbres déjà animés.)
  3. **Ce n'est pas que l'arbre entier qui doit osciller.** « Ça serait cool si les FEUILLES
     bougeaient aussi comme si elles étaient balayées par le vent, et pas que sur les palmiers mais
     TOUTES LES PLANTES ET LES SHRUBS. Ça doit être SUBTIL et CRÉDIBLE pour un vent naturel. »
     => deux échelles de mouvement à distinguer : le balancement du tronc/couronne, et le
     frémissement des feuilles/frondes qui doit exister sur toute la végétation, pas seulement les
     palmiers.
