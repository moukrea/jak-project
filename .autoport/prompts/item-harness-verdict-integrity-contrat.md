# Le verdict d'un item de harnais est aussi epingle et aussi falsifiable que celui d'un item moteur — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

CINQ SIGNALEMENTS DU 12/09 (reports/harness-proof-props-pin/FINDINGS.txt).
1. `validators/generic.sh:23` refuse une preuve dont une source de `game/ common/ android/ goal_src/` est plus RECENTE qu'elle, mais ne regarde PAS `.autoport/`. Or le verdict d'un item de harnais vit maintenant dans `lib/census/<id>.sh` : il peut etre edite APRES la course sans que la porte s'en apercoive. Le precedent `builder-checkpoint-steals-work` avait mis sa somme dans `game/system/checkpoint_census.cpp` exactement pour ca.
2. Le teardown de FIN de course (trap EXIT de proof_run.sh, ~ligne 460) ne recoit pas `AUTOPORT_TEARDOWN_REPORT` : ce qu'il efface apres la course reste muet, et la course suivante repart d'un etat dont personne n'a le releve.
3. Le bras x86 relit l'environnement par `printenv` DU SHELL QUI EXPORTE, pas par `/proc/<pid>/environ` du `gk` lance : il attrape un `export` refuse, pas un lanceur qui filtrerait l'environnement. Le cote appareil n'a pas ce trou.
4. La liste de SECOURS de `device_teardown.sh:62-69` est ecrite a la main et son propre en-tete recense cinq proprietes qu'elle avait ratees. Si le `getprop` global echoue, `teardown_props_found` ne porte que ce que la liste connait, et un compte faible se lit « rien n'etait pose » au lieu de « getprop muet ».
5. MECHE LENTE DEJA ALLUMEE : `lib/census/harness-proof-props-pin.sh` et `lib/pin_props_selftest.sh` cherchent l'etat d'AVANT et le bras d'ablation dans les 60 DERNIERS commits du fichier. `orchestrator.py` et `proof_run.sh` bougent tous les jours : le jour ou la fenetre est depassee, la porte vire au ROUGE sans qu'aucun defaut existe.

## Livrable — le contrat, en entier

`verdict_integrity_defects` = 0, somme de termes publies SEPAREMENT.
1. La fraicheur du validateur couvre les sources qui PRODUISENT le verdict, `.autoport/` comprise. Publier le nombre de fichiers epingles et leur empreinte RECALCULEE a la lecture, pas seulement recopiee. Une preuve plus vieille que son propre juge est refusee.
2. Le teardown de FIN de course dit ce qu'il efface, comme celui du debut. Publier le compte et les noms. Un zero se lit « rien n'etait pose », jamais « pas regarde ».
3. Le bras x86 relit `/proc/<pid>/environ` du processus MESURE. Publier le compte de variables relues a cet endroit, et le comparer a celui du shell : l'ecart est la grandeur qui compte.
4. Un `getprop` global muet est DISTINGUE d'un appareil sans proprietes : deux cles, pas une.
5. La fenetre de recherche de l'etat d'AVANT cesse d'etre un nombre de commits. Ancrer sur une empreinte de contenu ou sur la revision qui a introduit le bras, et publier laquelle a servi. Une porte qui rougit parce qu'un fichier voisin a bouge est un faux rouge programme.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change le verdict d'aucun item deja ferme.

## Ou l'owner regardera

Invisible. C'est l'integrite des preuves du harnais lui-meme.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

