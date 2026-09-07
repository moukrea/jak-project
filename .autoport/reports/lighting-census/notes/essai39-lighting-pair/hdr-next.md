DIRECTIVES v6fca51fe40
Suite HDR — audit de lecture seule, aucun verdict qualité.
- refset.cpp measure_step est appelé uniquement pour vantage.id vide, pas village1-out.
- StepStats est local à chaque processus ; les deux racines mono-phase ne produisent donc
  pas ensemble hdr_refset_hours_paired. Ne pas interpréter leurs zéros comme qualité mesurée.
- Instruments acquis : canaux255, RGB255, dénominateur, gradient du décile lumineux.
  Ils mesurent écrêtage/détail, pas teinte ni saturation colorimétrique.
- hdr_chain_frames, tonemap_draws, format et cfg_bad attestent la chaîne seulement.
- hdr.cpp demande encore trois configurations pour son contrôle de sites ; cette exigence
  ne doit pas réintroduire masterOFF comme prérequis de cette priorité.
- Le verdict de baseline indépendante est déjà exclu de hdr_tonemap_defects ; ne pas le relancer.
- Aucun nouveau script de mesure, aucune campagne visuelle, aucun changement tonemap fait.
- Prochain travail : réutiliser measure_step sur les pièces ON/OFF déjà appariées, avec
  dénominateurs par vue/heure ; cibler hdr.cpp et tonemap.frag selon données établies.
- Non prouvé : correction des blancs, teintes/saturation et conservation des hautes lumières.
