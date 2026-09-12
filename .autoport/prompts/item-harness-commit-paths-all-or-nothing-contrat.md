# Un chemin qui refuse de s'indexer ne fait plus perdre le commit de tout un essai — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SIGNALEMENT DU 12/09 (reports/gl-uniforms-dead-seven/FINDINGS.txt), verifie sur l'arbre. `orchestrator.py:854 git_commit_paths` fait UN SEUL `git add` pour tous les chemins sales. Le 12/09 a 02:26, a la fermeture de `lighting-legacy-purge`, un chemin a fait sortir git en fatal — « game/graphics/opengl_renderer/loader/PbrTestPattern.cpp ne correspond a aucun fichier » — et AUCUN des 64 fichiers n'a ete commite.
CE QUE CA A COUTE, MESURE. L'arbre porte depuis 357 insertions et 6390 suppressions que decrit aucun commit. Le constructeur bati depuis l'ARBRE : l'APK publie a 03:05 sur le commit cbc8e8598b porte donc du code d'un AUTRE item, bloque, dont l'essai avait ete tue. Pire, la mesure de `gl-uniforms-dead-seven` le chiffre : `kept_uniform_pushes=230880`, `kept_uniform_list=u_rt_sh[0]` — les neuf coefficients d'ambiante directionnelle SH, feature VALIDEE par l'owner (Grecharged-directional-ambient ROUND 2), partent vers un emplacement que le pilote ne connait plus, parce que les deux seuls appelants de `rt_sh_ambient()` (pbr_fused.glsl, pbr_helpers.glsl) sont supprimes dans ce checkpoint. La feature est ETEINTE dans tout binaire bati sur cet arbre, sans un mot.
ET LE DANGER SUIVANT : le premier item qui commitera un de ces fichiers emportera le travail d'un autre sous son nom. C'est deja arrive le 11/09 avec six shaders a moitie purges.

## Livrable — le contrat, en entier

`commit_paths_defects` = 0, somme de termes publies SEPAREMENT.
1. Un chemin qui refuse de s'indexer n'emporte plus les autres : l'indexation se fait chemin par chemin, ou le lot est retente sans le chemin fautif. Publier le compte de chemins indexes et le compte de chemins refuses, separement — jamais un seul booleen.
2. Un refus est DIT dans le journal avec le chemin et la raison rendue par git, et l'essai ne se ferme pas en silence sur un commit vide. Publier le compte de commits vides evites.
3. Preuve a deux bras sur un depot jetable : un lot contenant un chemin impossible, juge par le code d'AVANT (zero fichier commite) et par celui d'APRES (tous les autres commites). Le chemin impossible est REPRODUIT, pas simule par un drapeau.
4. La porte de fermeture refuse de conclure quand l'arbre reste sale sur des chemins moteur qui n'appartiennent pas a l'item courant : publier le compte de fichiers sales etrangers a l'item. Un essai qui bati sur le travail non commite d'un autre item mesure un binaire que personne ne peut reproduire.

## Hors perimetre

Ne touche a aucun code du jeu. Ne commite et ne restaure rien de l'arbre courant.

## Ou l'owner regardera

Invisible. C'est la facon dont le harnais enregistre le travail d'un essai.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

