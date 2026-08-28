# Gkeira-hd-detached-parts — trois morceaux detaches du modele HD de Keira

## Le defaut, mot pour mot (owner 2026-08-28)

> « le modèle de Keira HD il a une visière attachée, à genre quelques mètres du main modèle, je
> pense que c'était un moyen hacky d'avoir la visière à disposition pour certaines animations de
> Jak 2 (ou p'tetre 3) mais dans Jak 1 ça sert à rien, faut que tu vires cette partie. »

**CORRECTION DU 2026-08-28, apres verification par l'owner** : ma premiere lecture parlait de
« sangles » et c'etait FAUX. `TopStrap`/`BotStrap` sont ses BRETELLES (parents `Lshoulder` /
`Rshoulder` et `hips`), pas sa visiere. La visiere, ce sont les joints `goggles*` et `maskstrap`,
qui forment un groupe distinct. Il y a donc TROIS defauts distincts, pas un.

## Mesure (out/jak1/fr3/skin/keira-hd-lod0.glb, modele haut de 3,14 unites)

Positions de repos calculees depuis les matrices de bind inverses, distance a `chest` :

| joint | position | d(chest) | sommets portes |
|---|---|---|---|
| `lTopStrap2` `rTopStrap2` `lBotStrap2` `rBotStrap2` | y = **167,86** | **167,45** | 112 au total |
| `gogglesBase` | (-0,95 ; 0,51 ; 1,94) | **2,43** | 40 |
| `maskstrap` | (0 ; 0 ; 0) — l'ORIGINE du modele | **1,72** | 100 |

Pour reference, les joints sains : `gogglesMid/Left/Right` a d=0,73 (a hauteur de tete, correct),
`head` a 0,57, `hips` a 0,23.

**Les trois portent de la vraie geometrie.** `maskstrap` est parente directement a `prejoint`
(la racine) et non a la tete : ses 100 sommets sont epingles a l'origine du modele.

Le squelette porte par ailleurs **106 noms de joints en double sur 214 noeuds** — deux
hierarchies dans le meme fichier. A verifier, peut-etre sans rapport.

## DECISION DE L'OWNER (2026-08-28) — « La visière faut la supprimer, rien à foutre là, le reste j'en sais rien. »

Traduction en consigne, sort de chacun des trois groupes :

### 1. `maskstrap` — **SUPPRIMER**
100 sommets epingles a l'ORIGINE du modele, joint parente a `prejoint` (la RACINE) et non a la
tete. Nom distinct de `goggles*`. C'est le bricolage que l'owner decrit : une piece rendue
« disponible » sans etre rattachee a quoi que ce soit. Elle ne sert a rien dans Jak 1.

**GARDE OBLIGATOIRE AVANT DE SUPPRIMER** : publier ce que sont ces 100 sommets — leur materiau,
leur boite englobante locale, et s'ils sont ou non des DOUBLONS de la geometrie `goggles*`. Si la
mesure montre qu'ils font partie des lunettes qu'elle porte reellement sur la tete, **ARRETER et
le dire** : on aurait supprime quelque chose de visible. L'owner a tranche sur une piece
parasite, pas sur ses lunettes.

### 2. `gogglesBase` — **RECOLLER**, ne pas supprimer
Ses trois enfants `gogglesMid` / `gogglesLeft` / `gogglesRight` sont CORRECTEMENT places a
hauteur de tete (d=0,73 du torse, contre 0,57 pour `head`). Seule la base part de cote, sous et
devant (d=2,43). C'est donc un joint mal pose des vraies lunettes de Keira, pas une piece en
trop. Et l'owner veut de la physique sur ses lunettes plus tard.

### 3. Bouts de bretelles `lTopStrap2` `rTopStrap2` `lBotStrap2` `rBotStrap2` — **RECOLLER**
Parents : `Lshoulder` / `Rshoulder` / `hips`. Ce sont ses BRETELLES, et « à ses bretelles » est
explicitement dans la liste de ce que l'owner veut animer. Les supprimer reviendrait a jeter
exactement ce qu'il veut faire bouger. Recoller les extremites au bout de leur parent.

**L'owner a dit « le reste j'en sais rien » : ces deux arbitrages sont les miens, ils sont donc
a publier clairement dans le rapport pour qu'il puisse les renverser.**

## Pourquoi ca compte au-dela du visuel

`recharged_assets/physics_chains.txt` lignes 40-41 :

    FALLBACK topstrapL.lTopStrap: 0 skinned vertices, radius from lTopStrap2
    FALLBACK topstrapR.rTopStrap: 0 skinned vertices, radius from rTopStrap2

Les chaines de bretelles tirent leur RAYON des joints casses a 167,86.

## Interdits

- **Ne pas editer le .glb** : artefact GENERE, il sera ecrase. Corriger la PREPARATION.
- **Ne pas relancer le generateur de chaines a l'aveugle** : `physics_keira_gen` a deja detruit
  des chaines une fois. Regenerer puis COMPARER, jamais remplacer sans diff.

## Critere de reussite

1. Aucun joint du skin a plus de ~4 unites du centre du modele.
2. Zero sommet orphelin sur les trois groupes (272 sommets concernes au total).
3. Les deux lignes `FALLBACK ... radius from *Strap2` ont disparu.
4. Boite englobante publiee avant/apres.
5. Le sort de CHACUN des trois groupes est justifie separement.
