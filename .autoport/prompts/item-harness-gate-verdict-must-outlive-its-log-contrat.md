# La preuve qu'une porte a tenu vit dans l'item, pas dans un journal que rien ne conserve — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

TROIS SIGNALEMENTS DU 12/09 (reports/harness-close-gate-code-free/FINDINGS.txt).
1. La promotion machine relit desormais le VERDICT avant de valider un `to-test` — c'etait le correctif demande. Mais ce verdict vit dans `logs/<id>/validator-NNN.txt`, et `.gitignore:174` exclut tout `.autoport/logs/`. Sur un clone neuf, ou apres une purge de journaux, le verdict est INTROUVABLE. Le code choisit alors de ne pas promouvoir, ce qui est le bon defaut, mais l'effet est qu'un item prouve reste gele — exactement la panne que `perf-ocean-idle` a vecue deux jours.
2. `orchestrator.py:2837` : la porte ne laisse AUCUNE TRACE dans l'item de ce qu'elle a rendu. Elle pose `to-test` et `delivered`, rien d'autre. La seule preuve qu'elle a tenu est un fichier de journal non versionne. Le backlog, lui, est la seule verite du travail et il est versionne.
3. `lib/gate_verdict.py:CODE_FREE_PATTERNS` : le perimetre « ce chantier ne touche pas au code du jeu » est reconnu par une LISTE DE TOURNURES francaises. Un item ouvert avec une formulation neuve — « n'ajoute aucun C++ », « harnais seulement » — n'est pas reconnu, et la porte redemande le code. Une autorite qui depend de la facon dont j'ecris une phrase n'est pas une autorite.

## Livrable — le contrat, en entier

`verdict_durability_defects` = 0, somme de termes publies SEPAREMENT.
1. Le verdict de la porte est ECRIT DANS L'ITEM au moment ou elle le prononce : au minimum le resultat, la date, et l'empreinte de la preuve jugee. Publier le compte d'items `to-test` portant ce champ et le compte de ceux qui n'en ont pas.
2. La promotion machine lit ce champ EN PREMIER et ne retombe sur le journal que s'il manque. Preuve a deux bras sur une copie jetable : journaux EFFACES, le bras d'AVANT ne promeut pas, celui d'APRES promeut. C'est la purge des journaux qui est le stimulus, pas un drapeau.
3. Le perimetre cesse d'etre devine dans une phrase. Un champ explicite fait foi ; la lecture de la prose ne sert plus que de repli, et chaque repli est COMPTE et publie. Un item dont le perimetre a du etre devine doit apparaitre dans un compte, pas passer inapercu.
4. Rien de ce que le chantier precedent a livre ne regresse : reprendre ses quatre termes et montrer qu'ils gardent leurs valeurs, bancs semes compris.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change pas la definition du verdict lui-meme, ni les criteres de `generic.sh`. Priorite 31 volontaire : la refonte de l'eclairage passe AVANT.

## Ou l'owner regardera

Invisible. C'est ce qui reste d'une porte une fois les journaux effaces.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

