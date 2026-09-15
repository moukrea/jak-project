# Audit des instruments — essai 1
DIRECTIVES v07b292c21f

Lecture seule du manager et du researcher natif Codex gpt-6-astra, effort high.
Contrat lu : .autoport/prompts/SPEC-refonte-herbe.md, sections 1 et 14.
Aucune modification du moteur, des shaders, des réglages, du backlog ou du harnais.
La clause « Ne change RIEN » est appliquée littéralement ; aucune instrumentation neuve.
Le périmètre demande dix observations mais le moteur ne possède pas leur instrument.

## Inventaire statique (pas des mesures sur appareil)
- grass_density_presets.h:30 : very-low/low/medium/high/very-high, 50/100/150/200/250 %.
- GrassRenderer.cpp:1084 : GRASSPRESET distingue le palier demandé du palier servi.
- GrassRenderer.cpp:1393 : PLACE-TIME donne source, expand+logs, upload+light, instances.
- GrassRenderer.cpp:1322 : DIAG-COUT ; en asynchrone, la fenêtre inclut le délai de consommation du futur.
- OpenGLRenderer.cpp:1954 et android/android_opengl_renderer.cpp:2053 : grass-draw enveloppe tout render().
- Profiler.cpp:22 : temps mural ; pas de séparation CPU préparation / GPU dessin.
- GrassRenderer.cpp:1814,1866 : grass_gpusync active R19SYNC avec glFinish et perturbe le pipeline.
- GrassRenderer.cpp:1832,2161 : draw_n et card_n existent mais ne sont pas publiés comme relevés du contrat.
- GrassRenderer.cpp:2203 : drawn est incrémenté avec in_lod ; aucun frustum d'instances dans ce compteur.
- GrassRenderer.cpp:1211 : GOVERHANG expand donne les bornes de la queue ; pas sa mesure isolée par palier.
- GrassRenderer.cpp:1369,1515,1532 : tailles déductibles 64*N et 4*N, pas relevées comme allocations GPU.
- android/android_renderer.cpp:689 : AOPERF fournit un FPS lissé, sans effectif ni identité du palier.
- game/system/perf_baseline.cpp : campagne scènes/résolutions différente du contrat herbe.
- kmachine.cpp:5906,5976 : level.warp et level.warp.pos disponibles pour préparer une scène fixe.
- Recherche rg de grass-baseline-cost et grass_baseline_gaps dans game/common/scripts : aucun résultat.

## Course diagnostique unique
Commande : AUTOPORT_BACKEND=codex bash .autoport/lib/proof_run.sh grass-baseline-cost device --timeout 90
Sortie du producteur : notes/proof-attempt1.log ; sortie moteur : proof-engine.log.
Ce démarrage vérifie le binaire livré et l'absence du site instrumental ; il ne vaut aucun des dix relevés.
Aucune campagne cinq paliers engagée, aucune ablation engagée, aucun ancien résultat réutilisé.
La valeur globale FEATURE hits ne doit jamais être publiée comme nombre de relevés herbe.
Le validateur est laissé à l'orchestrateur conformément au prompt.
