# Ce que dit le web sur le dosage des modèles — consulté le 19/09/2026

17 sources, toutes datées et liées. Aucun tarif de mémoire : tout vient d'une page
officielle du fournisseur. Le détail chiffré est dans `sources.json`.

## 1. Les prix (4 sources)
Page officielle Anthropic — https://platform.claude.com/docs/en/about-claude/pricing
(19/09/2026). Par million de mots-jetons : entrée / sortie / relecture du cache.
* **Fable 5.1** — 10 $ / 50 $ / **0,25 $**  ·  **Opus 5** — 5 $ / 25 $ / 0,50 $
* **Sonnet 5** — 2 $ / 10 $ / 0,20 $  ·  **Haiku 4.5** — 1 $ / 5 $ / 0,10 $
Écrire dans le cache coûte 1,25× l'entrée pour 5 minutes, 2× pour une heure. La relecture
vaut un dixième de l'entrée — **sauf Fable 5.1, à un quarantième**. C'est le fait le plus
important de cette recherche : Fable 5.1 relit le cache **deux fois moins cher qu'Opus 5**
alors qu'il coûte deux fois plus cher partout ailleurs. Nos essais lisant des dizaines de
millions de jetons de cache, ce poste pèse plus que le prix affiché.
**Le suffixe `[1m]` ne coûte rien de plus.** La page l'écrit : depuis la génération 4.6, la
fenêtre d'un million est au tarif standard, « une requête de 900 000 jetons est facturée au
même tarif qu'une requête de 9 000 ». Aucune majoration contexte long chez Anthropic.
Côté Codex — https://developers.openai.com/api/docs/pricing (19/09/2026) : **GPT-6 Astra**
à 10 $ / 50 $, cache relu 1 $, et **le contexte long double l'entrée à 20 $ et porte la
sortie à 75 $**. Le petit modèle de code, gpt-5.3-codex, est à 1,75 $ / 14 $.
## 2. Les niveaux d'effort (2 sources)
https://platform.claude.com/docs/en/build-with-claude/effort (19/09/2026) donne le cas
d'usage du niveau le plus bas en toutes lettres : « tâches simples qui demandent la
meilleure vitesse et le coût le plus bas, **comme les sous-agents** ». C'est notre montage.
https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence
(19/09/2026) en chiffre le prix en qualité : effort bas = 33 à 50 % d'économie sur la
recherche pour 1 à 3 points perdus, et **~75 % d'économie sur le code pour 2 à 8 points
perdus** ; effort moyen = 13 à 31 % d'économie sans perte mesurable. Même page, une recette :
tout lancer en effort bas puis rejouer seulement les échecs en effort haut donne le même
taux de réussite **pour la moitié du prix**. Deux pièges nommés par la doc : changer
l'effort en cours de conversation **jette le cache** (3 546 jetons relus deviennent 3 546
jetons réécrits) ; et les jetons de réflexion sont facturés **en sortie**, au tarif le plus
cher, même quand on ne les affiche pas.
## 3. Les classements publics (5 sources)
Chiffres d'Anthropic au lancement de Fable 5.1 —
https://www.anthropic.com/claude-fable-and-mythos-5-1 (01/09/2026) : Terminal-Bench 4.0,
**Fable 5.1 : 55,8 %, Opus 5 : 52,3 %**, Fable 5 : 42,0 % ; CursorBench 73,4 % contre
70,0 %. Sur les tâches longues en terminal, l'écart est de 3,5 points **pour le double du
prix**. SWE-bench Verified — https://llm-stats.com/benchmarks/swe-bench-verified
(19/09/2026) : Fable 5 à 95,0 %, **Sonnet 5 à 85,2 %**, **Haiku 4.5 à 73,3 %**. Ce site
déclare lui-même « 0 résultat vérifié, 116 auto-déclarés » : les fournisseurs notent leur
propre copie. **Ni Opus 5, ni Fable 5.1, ni GPT-6 Astra n'y figurent.**
## 4. Le dosage fort / pas cher (3 sources)
Anthropic a mesuré un montage exactement comme le nôtre : un coordinateur Fable 5.1 avec
25 ouvriers Sonnet 5 sur un corpus de 21,6 millions de jetons. **47 à 55 % moins cher** que
le gros modèle seul, **2,3 heures au lieu de 15 à 20**, mais **10 à 12 points de précision
en moins**. Le gain est réel, le prix aussi. Le garde-fou de la même page, à retenir : avant
tout montage à plusieurs modèles, il faut battre **le modèle fort seul en effort bas** —
c'est la référence. Et le montage ne paie pas quand le travail est une seule chaîne de
dépendances ou tient dans une seule fenêtre : sur un test, le gros modèle seul a fait aussi
bien **22 à 30 % moins cher**. Le billet d'ingénierie —
https://www.anthropic.com/engineering/multi-agent-research-system (13/06/2025) — donne le
gain historique de la formule (chef Opus + ouvriers Sonnet, +90,2 %) et l'avertissement :
**un système multi-agents consomme ~15 fois plus de jetons qu'une simple conversation**. Il
ajoute que le code se prête moins bien au découpage que la recherche, « moins de tâches
vraiment parallélisables ».
## 5. Retours d'utilisateurs — ANECDOTIQUES (3 sources)
Télémétrie sur 24 h — https://mirin.pro/blog/claude-code-subagents-haiku-telemetry/
(25/02/2026) : sur 7 222 appels, Haiku en fait 36,5 % mais pèse **8 $ sur 354 $**. Un appel
Haiku coûte 0,003 $, un appel Opus 0,077 $ — rapport de 26. Le même relevé montre
**451 millions de jetons relus en cache** contre 2,5 millions en entrée : le cache EST le
volume. Un seul utilisateur, non reproduit. Ticket ouvert —
https://github.com/anthropics/claude-code/issues/43869 (05/04/2026) : **les cinq façons
documentées d'envoyer un sous-agent sur un autre modèle seraient ignorées en silence**, tout
retombant sur le modèle du parent. Non confirmé par Anthropic. Si c'est vrai chez nous, tout
dosage théorique est sans effet — à vérifier sur notre installation avant de décider.
## CE QUI RESTE INTROUVABLE
* **SWE-bench Verified d'Opus 5 et de Fable 5.1** : Anthropic n'en publie aucun, les
  classements publics ne les listent pas. Inscrits à `null`.
* **Scores de GPT-6 Astra et de gpt-5.3-codex** sur SWE-bench, Terminal-Bench ou
  SWE-Lancer : page officielle OpenAI inaccessible (403), agrégateurs muets. `null`.
* **Seuil du « contexte long » chez OpenAI** : deux colonnes facturées, aucun seuil donné.
  Un blog tiers avance 272 000 jetons ; non confirmé officiellement, donc écarté.
* **Aucun banc indépendant** : tous les scores viennent des fournisseurs, sauf ARC-AGI 3
  (mesuré par la ARC Prize Foundation).
* **Dates de publication des pages de doc** Anthropic et OpenAI : elles n'en affichent
  aucune. Inscrites à `null`, avec la date de consultation.
* **Rien de public sur les profils `[1m]`** : c'est notre vocabulaire interne, pas un
  produit. La seule donnée utile est qu'il n'a pas de surcoût.
