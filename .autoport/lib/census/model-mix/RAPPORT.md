# Quel dosage de modèles pour le harnais — deuxième version, après ton retour

*20 septembre 2026. Tout ce qui suit est compté dans nos 1 078 journaux d'essai, sauf les
tarifs et les bancs publics, qui viennent des pages officielles citées à la fin.*

## D'abord : tu avais raison, et voilà de combien

Tu as écrit : « comment ça se fait que fable ne soit pas réellement envisagé ? T'as fait une
évaluation de merde sur notre historique, c'est éclaté. » La première version comparait
« Fable 5.1 : 46 essais, 46,1 % de réussite » à « Opus 5 : 278 essais, 55,8 % », et en
concluait qu'on pouvait écarter Fable.

Ces deux chiffres ne parlent pas de la même chose. En reprenant les journaux un par un :

> **Sur les 51 essais de Fable 5.1, 34 n'ont jamais eu lieu.** 31 ont été refusés par l'API
> — plus de crédits, erreur 429, « You're out of usage credits » — et 3 ont été tués avant
> de rendre quoi que ce soit. Trois essais de `Gcine-cut` sont morts après 7 appels d'outil,
> sans un seul jeton facturé. **Ils comptaient tous comme des échecs de Fable.**

67 % de la population Fable était morte, contre 17 % chez Opus 5. Le « 46,1 % » ne mesurait
pas un modèle, il mesurait une panne de crédit. C'est le défaut, il est corrigé, et la
correction change la réponse.

## Fable contre Opus 5, à égalité de chances

Deux règles, appliquées **des deux côtés** :

1. **Mêmes tâches.** On ne garde que les tâches sur lesquelles les deux modèles ont
   réellement travaillé. La difficulté cesse d'être confondue avec le modèle.
2. **On jette les essais qui n'ont pas eu lieu**, et le motif est lu sur un champ que
   l'outil ou le serveur écrit lui-même (`terminal_reason=api_error`, refus de quota),
   jamais deviné. Opus 5 en perd 70, Fable 5.1 en perd 34 : la règle ne vise personne.

| | Fable 5.1 | Opus 5 | Fable 5 | Opus 5 |
|---|---|---|---|---|
| tâches communes | 8 | 8 | 4 | 4 |
| essais qui ont eu lieu | 15 | 34 | 12 | 19 |
| portes tenues | **66,7 %** | 50,0 % | 33,3 % | **52,6 %** |
| *l'intervalle, pas le point* | *41,7 – 84,8* | *34,1 – 65,9* | *13,8 – 60,9* | *31,7 – 72,7* |
| essais qui se butent en boucle | **0** | 7 | 0 | 3 |
| coût par porte tenue | **41,85 $** | 43,31 $ | 104,25 $ | **63,29 $** |

Et le verdict, qui sort de l'intervalle et non de l'écart des points :

Fable 5.1 est indiscernable d'Opus 5 sur les 8 tâches que les deux ont réellement traitées : 10 portes tenues sur 15 (66,7 %, intervalle 41,7 à 84,8 %) contre 17 sur 34 (50,0 %, intervalle 34,1 à 65,9 %).

Fable 5 est indiscernable d'Opus 5 sur les 4 tâches que les deux ont réellement traitées : 4 portes tenues sur 12 (33,3 %, intervalle 13,8 à 60,9 %) contre 10 sur 19 (52,6 %, intervalle 31,7 à 72,7 %).

**Indiscernable** veut dire ce qu'il dit : avec 15 essais contre 34, un écart de 17 points
ne prouve rien. Mais il faut le lire dans les deux sens — **rien dans nos journaux ne permet
de dire que Fable 5.1 est moins bon qu'Opus 5**, et sur les trois mesures du tableau il est
devant ou à égalité. La phrase « écarté » de la première version n'avait aucune mesure
derrière elle.

Un contrôle, pour que tu n'aies pas à me croire sur l'exclusion : **si on ne jette rien du
tout**, le verdict reste `indiscernable` (Fable 47,6 % sur 45 essais contre Opus 43,9 % sur
97). Ce n'est donc pas le tri qui fabrique le résultat.

### Tâche par tâche

| tâche | Fable 5.1 | Opus 5 |
|---|---|---|
| `Gcutscene-npc-flicker-2` | 1 essai, 1 vert, 44,55 $ | 1 essai, 1 vert, 142,18 $ |
| `Gcutscene-skip-polish-2` | 1 essai, 1 vert, 10,60 $ | 1 essai, 1 vert, 43,87 $ |
| `Ghd-skin-origin-stretch` | 3 essais, 2 verts, 61,38 $ | 1 essai, 1 vert, 11,41 $ |
| `cutscene-npc-flicker` | 1 essai, 1 vert, 26,35 $ | 6 essais, 2 verts, 17,16 $ |
| `foliage-wind` | 1 essai, 1 vert, 11,12 $ | 2 essais, 2 verts, 7,81 $ |
| `hdr-display-output` | 4 essais, 2 verts, 18,27 $ | 10 essais, 5 verts, 14,21 $ |
| `lighting-ao-indirect` | 2 essais, 1 vert, 21,61 $ | 12 essais, 4 verts, 22,36 $ |
| `recharged-hud-toggle` | 2 essais, 1 vert, 12,71 $ | 1 essai, 1 vert, 9,78 $ |

Au passage, la justification qu'on t'avait donnée était fausse elle aussi : on t'a dit que
Fable avait tourné « presque uniquement sur l'AO ». Il y a fait **3 essais sur 51**.

### Ce que disent les bancs publics

Ils ne sont pas de notre fabrication, et ils vont dans le même sens. Au 1er septembre 2026,
Anthropic publie Fable 5.1 **devant** Opus 5 sur les cinq suites agentiques : Terminal-Bench
55,8 contre 52,3 ; Terminal-Bench-Science 52,6 contre 29,0 ; CursorBench 73,4 contre 70,0 ;
AutomationBench 31,4 contre 26,9 ; OSWorld 41,7 contre 39,6. Ce sont des chiffres de
l'éditeur, pas d'un tiers — mais ce serait malhonnête de les taire quand ils contredisent ce
qu'on a écrit en septembre.

## Ce que ça coûte, des deux côtés

Sur la lecture de cache — 99 % de notre volume — Fable 5.1 est **deux fois moins cher**
qu'Opus 5 (0,25 $ le million contre 0,50 $). Sur l'entrée et la sortie, il est deux fois
plus cher. Les deux effets s'annulent presque exactement :

| profil | coût projeté par essai |
|---|---|
| aujourd'hui (tout Opus 5) | 16,42 $ |
| `panel-sobre` — manager Opus 5 | **14,44 $** |
| `panel-fable` — manager Fable 5.1 | **14,53 $** |

Neuf centimes d'écart. **Le choix entre Opus 5 et Fable 5.1 n'est pas une question
d'argent** : c'est une question de qualité, et c'est précisément celle que nos journaux ne
savent pas trancher.

## Où part vraiment l'argent

| étage | part des jetons | messages / essai |
|---|---|---|
| **agent principal** | **86,5 %** | 91,9 |
| sous-agent « chercheur » | 10,7 % | 29,8 |
| sous-agent « implémenteur » | 2,5 % | 6,7 |
| sous-agent « testeur » | 0,2 % | 1,6 |

C'est ce tableau qui condamne l'idée intuitive « manager coûteux, sous-agents bon marché » :
chez nous les sous-agents ne pèsent presque rien, donc changer leur modèle fait gagner 8 à
11 %, pas 60 %. Et il reste deux gisements que personne ne regarde :

- **les 17,7 millions de jetons de cache que l'agent principal relit à chaque essai** ;
- **le superviseur** — la session qui pilote — a lu **15,1 milliards de jetons de cache**
  depuis le début du projet, de l'ordre de **9 700 $** au tarif public. Il n'apparaît dans
  aucun compteur d'essai.

Les deux méritent leur propre chantier, et pèsent plus lourd que tout le débat de modèles.

## Deux choses vérifiées plutôt que crues

- **Les tarifs publiés collent à nos factures**, à la quatrième décimale près, une fois
  distinguée l'écriture de cache 5 minutes de celle d'1 heure. Nos chiffres et les leurs
  parlent de la même chose.
- **Le routage des sous-agents marche vraiment ici.** Un ticket public affirme qu'il est
  ignoré en silence. Sur nos traces, **148 étages sur 148** ont été facturés au modèle
  configuré, 0 ignoré. Sans ça, toute la recommandation serait sans objet.

## Ce que je propose

Deux profils écrits dans `model-profiles.json`, **aucun des deux activé** — c'est ton geste,
pas le mien :

| | `panel-sobre` | `panel-fable` |
|---|---|---|
| agent principal | Opus 5, effort élevé | **Fable 5.1**, effort élevé |
| sous-agents | Sonnet 5 / Haiku 4.5 | Sonnet 5 / Haiku 4.5 |
| coût attendu | 14,44 $ | 14,53 $ |

Je ne tranche pas entre les deux, parce que la mesure ne tranche pas. **Ce qui tranche,
c'est six essais faits exprès** : le protocole est écrit, prêt à lancer, dans
`notes/protocole-essai-croise.md`. Trois tâches — `harness-pack-manifest-is-a-build-artefact`,
`grass-bake-invalidation`, `soft-bake-format` — chacune une fois sous `opus5-sobre` et une
fois sous `fable51-sobre`, mêmes budgets, en alternant. Elles sont choisies pour une raison :
leur verdict est une mesure automatique, sans téléphone et sans toi dans la boucle. Compte
100 à 170 $ et une demi-journée. Un mot suffit pour que je le lance.

**Une condition, sinon c'est perdu d'avance : vérifier le crédit avant.** Six essais refusés
par l'API reproduiraient exactement le faux verdict de septembre.

## Les biais — à lire avant de me croire

- **BIAIS — le tri des essais peut flatter un modèle qui plante souvent.** Jeter les essais
  interrompus avantage mécaniquement celui qui est le plus souvent coupé. C'est pour ça que
  le résultat **sans aucun tri** est publié juste à côté : il donne le même verdict.
- **BIAIS — 15 essais contre 34, c'est peu.** Les intervalles font 40 points de large. Ce
  rapport dit `indiscernable` parce que c'est la seule chose vraie, pas par prudence.
- **BIAIS — Fable 5.1 a presque toujours tourné en contexte long ici.** Son coût mesuré
  (27,90 $ par essai) est celui de ce réglage-là, pas celui du profil que je propose, qui
  tourne sans. Les deux ne sont pas comparables, et je ne les compare pas.
- **BIAIS — un essai tué par la plomberie n'est pas un échec du modèle.** Sur nos échecs,
  **172 viennent de la plomberie de preuve** et 265 du fond. Le tri se fait par mots-clés
  sur les lignes d'erreur : c'est une approximation, et elle favorise les profils qui ont
  tourné quand la plomberie allait mal.
- **BIAIS — la moitié de notre histoire tourne sur des modèles qui n'existent plus.** Opus
  4.7, Opus 4.8 et Fable 5 représentent 428 essais. Ils éclairent la méthode, ils ne peuvent
  pas fonder un choix pour demain.
- **BIAIS — la sortie n'est pas attribuable à un étage.** Le flux ne publie qu'un acompte
  par message ; seul le total de session est juste. Les parts par étage portent donc sur
  l'entrée et le cache, soit 98,7 % des jetons. Les 1,3 % restants sont publiés, pas cachés.
- **BIAIS — Sonnet 5 en sous-agent n'a jamais tourné ici.** Le gain de 8 à 11 % tient les
  jetons constants ; l'effet sur la qualité est une promesse de banc public, pas une mesure
  maison. C'est le seul pari des deux profils.
- **BIAIS — les bancs publics cités sont ceux de l'éditeur.** Ils ne sont pas indépendants.
  Ils ne servent ici qu'à dire qu'écarter Fable n'avait aucun appui, ni chez nous ni dehors.

## Ce que je n'ai pas prouvé

Qu'un des deux profils réussira aussi souvent que celui d'aujourd'hui. Personne ne peut le
savoir avant de l'avoir fait tourner — c'est pour ça qu'ils sont écrits et **pas activés**,
et que le protocole existe. Si tu veux les départager, la bonne mesure n'est pas le coût par
essai mais le **coût par essai réussi** : un profil 10 % moins cher qui rate 10 % plus
souvent est une perte.

## Sources externes

17 sources, consultées le 19/09/2026, détaillées dans `sources.json` et résumées en français
dans `notes/recherche-externe.md` : pages de tarifs officielles Anthropic et OpenAI,
documentation des niveaux d'effort, bancs publics (Terminal-Bench 4.0, Terminal-Bench-Science,
CursorBench, AutomationBench, OSWorld), publications sur le routage multi-modèles, retours
d'utilisateurs de Claude Code.

**Là où le publié et le mesuré divergent**, j'ai retenu le mesuré et je le dis : le contexte
long est annoncé « sans surcoût » et nous coûte **2,08 ×** (parce qu'il supprime la
compaction, pas parce qu'il est plus cher) ; le routage des sous-agents est annoncé cassé par
un ticket public et fonctionne **148 fois sur 148** chez nous ; des blogs donnent Opus 5 à
96 % sur SWE-bench alors qu'Anthropic n'en publie aucun score — ces blogs sont écartés, seul
l'officiel est cité.
