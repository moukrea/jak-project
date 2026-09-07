# Reprise ciblée — essai 32
DIRECTIVES v6fca51fe40
Recherche native gpt-6-astra/high (acteurs/RNG et configuration), implémentation/test medium.
Le bootstrap termine ses checkpoints avant scellement ; toute écriture après finish est refusée.
Les lecteurs acteurs/RNG ont maintenant une destination paramétrable, bootstrap par défaut.
Le second usage passe dans la trace pad déjà ouverte, après dispatch, aux LF capture-1/capture.
Les marqueurs POSTLOAD-BEGIN/END portent la LF absolue ; frame= reste la frame relative pad.
La sélection ignore g_cap : le renderer peut avoir consommé la demande avant fin du dispatch.
Les gardes de chargement, le flux bootstrap, les shaders et la qualification v2 sont inchangés.
Le relevé graphique utilise RenderOptions après overrides screenshot et clamp GL_MAX_SAMPLES.
Champs C++/options communs et 11 champs GOAL ciblés ; aucun pointeur/padding de structure.
Le helper master_active existant met à jour son cache ; override OG_RECHARGED fixe pendant le bras.
L’observation n’impose aucune valeur au jeu et ne restaure/tire aucun RNG.
Les offsets pc-settings viennent de pckernel-h.gc et TypeSystem, relatifs au BASIC déjà -4.
Ils exigent la même ISO ; scalaires précis, symboles par nom, bornes mémoire contrôlées.
Premier build : display_fps_cap absent de la structure historique, retiré du relevé commun.
Aucun run n’avait commencé ; erreur conservée dans baseline/build-gk-first-error.log.
Limites : état CPU après dispatch, pas copie des octets consommés lors de la construction DMA.
Les lecteurs acteurs couvrent identités, états, entity-trans, pas tous contrôles/poses/états privés.
Les réglages couvrent champs communs ciblés, pas tous overrides locaux des shaders ou du renderer.
L’égalité éventuelle ne doit pas être promue automatiquement en qualification complète.
