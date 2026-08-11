# À TESTER — build intermédiaire, PAS validé (publié sur ta consigne du 2026-08-11)

Branche `physics-keira-clean` — départ propre : moteur de physique réécrit (6000 → ~1276 lignes),
**Keira seule**, 22 chaînes générées depuis son rig.

## Ce qui a changé
* Nouveau moteur, aucun suppresseur par défaut (c'est leur empilement qui avait tué le mouvement).
* Chaînes : oreilles, cheveux (racine ancrée), mèches, seins, lunettes, bretelles, pans, sangles.
* Salle de test interne : le joueur n'est plus spawné du tout (prouvé par le log).
* **Les 59 autres personnages n'ont plus de physique** — c'est voulu, on ne les régénère qu'après
  ta validation de Keira.

## Ce que JE sais déjà rouge (ne perds pas de temps dessus, sauf si tu vois autre chose)
* 18 animations mesurées sur 31 — la couverture n'est pas complète.
* Priorité à l'animation d'auteur : 8 chaînes concernées, **1 seule** respecte l'animation.
* `pantflapL` inerte (0,0137) alors que `pantflapR` bouge (0,77) — asymétrie.
* Contrôle de pénétration incohérent : je ne conclus rien sur les collisions pour l'instant.

## Ce sur quoi ton œil est utile
1. Keira : ses **mèches** et ses **oreilles** bougent-elles visiblement ? (mesuré 0,69–0,88)
2. Sa **poitrine** : ferme et vivante, ou molle / écrasée ? (mesuré 0,66–1,04)
3. Ses **lunettes** : elles pendent et restent pendues ? traversent-elles encore ?
4. Au repos, elle retrouve bien sa silhouette normale ? (mesuré : écart 0,0003 au modèle)
5. Le clipping : où, sur quoi, et est-ce pire ou moins pire qu'avant ?
