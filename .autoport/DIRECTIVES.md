# DIRECTIVES — contrat courant, autorité supérieure au prompt de tâche

Ce fichier est **relu à chaque étape** par le manager de phase ET par chaque sous-agent
(`autoport-researcher`, `autoport-implementer`, `autoport-tester`). Il est **plus récent** que le
prompt qui t'a lancé : en cas de conflit, **c'est lui qui gagne**, et tu le signales dans ton
rapport au lieu de suivre une consigne périmée.

Première action obligatoire, avant tout outil de travail : lire ce fichier, puis le contrat de
périmètre qu'il désigne ci-dessous.

---

## PÉRIMÈTRE ACTIF (2026-08-11)

SCOPE-SERIAL: 1
<!-- Bump ce numéro UNIQUEMENT pour un vrai changement de périmètre : il invalide
     immédiatement la tentative en cours (gate SYNC). Corriger une coquille ou
     reformuler ne doit jamais coûter une tentative. -->

* Phase : `Grecharged-secondary-motion` — physique secondaire.
* Contrat de périmètre : **`.autoport/prompts/SPEC-keira-physique.md`** — à lire en entier.
* Périmètre : **KEIRA SEULE**, code et données. Les 59 autres modèles ne sont **pas** touchés.
  Parler d'un autre personnage (barbe de Samos, col de Jak, nœud du maire…) dans le rapport est
  un hors-périmètre, sauf dans la section explicite des dettes différées.
* **ÉTAPE 1 BLOQUANTE** : la salle de test (`SPEC` §11). Facilité `phys-room` dans
  `goal_src/jak1/pc/*.gc` + tableau `.autoport/reports/Grecharged-secondary-motion/keira-room-table.txt`.
  Tant qu'elle n'existe pas, **aucun autre travail n'est autorisé** : ni remplissage de
  paramètres, ni gates existantes, ni réglage de style. Le validateur échoue en première ligne.
* Substrat : **x86 d'abord** (REPL, itération en secondes). Le device Redmi `eae4df44` sert à
  **confirmer**, pas à découvrir.

## RÈGLES QUI NE SE NÉGOCIENT JAMAIS (owner)

1. **Aucun faux vert.** Un chiffre vert dont l'owner voit encore le défaut est une mesure sans
   valeur : elle est retirée, pas défendue. Tout zéro exige un **contrôle positif qui a tiré**
   (injecter le défaut, voir le compteur monter, l'enlever).
2. **Aucune preuve visuelle.** Interdiction permanente des campagnes de captures/verdicts à l'œil.
   La qualité est jugée par l'owner ; toi tu produis des nombres.
3. **Aucun de-scope silencieux.** Si une partie du périmètre est bloquée, tu finis tout le reste
   et tu le dis explicitement — jamais réduire en silence.
4. **Données générées, jamais rustinées.** Les chaînes viennent du rig + des règles de la SPEC.
   Aucun flag de dérogation (`colskip`, filtres de volumes, masques).
5. **Gates gelées.** N'ajoute, ne modifie et n'assouplis **aucune** gate du validateur — c'est un
   verrou dur. Si une gate te semble fausse, tu le rapportes ; c'est le superviseur qui tranche.
6. **Rien ne traverse le mesh de son personnage, quelle qu'en soit la raison.** Une résolution
   pire que le clip est pire que rien.
7. **Une mesure par chaîne doit varier par chaîne.** Constante partagée ou rampe d'index =
   fabriquée, rejetée.
8. Jamais `git push --force`, jamais `rm -rf` sur du code, jamais de kill par motif (auto-match) —
   PID exacts uniquement.

## RAPPORT

Ton rapport doit contenir, en clair, la ligne de synchronisation que le prompt t'a donnée :

```
DIRECTIVES <version>
```

Elle prouve que tu as travaillé sur le contrat courant. Une version périmée fait échouer la
tentative immédiatement, au lieu de gaspiller des heures sur un périmètre abandonné.
