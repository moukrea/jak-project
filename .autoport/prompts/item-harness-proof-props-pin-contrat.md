# Un worker doit pouvoir epingler le regime de SA course, et le verifier — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SIGNALEMENT DU 11/09 23:33 (reports/hdr-glow-range/FINDINGS.txt, dernier point). Le worker a ecrit `proof_props: debug.opengoal.recharged=0` sur son item et `proof_run.sh` a relu 1 dans la MEME minute. Il a contourne en posant la propriete depuis l'hote pendant l'amorcage et en VERIFIANT par une cle du proof (`hdr_glow_fmt_latched_float`).
ATTENTION — LE MECANISME QU'IL NOMME N'EST PAS ETABLI. Il accuse l'orchestrateur de reecrire `backlog.yaml` depuis sa copie memoire. La lecture du code ne le soutient PAS : `set_status` (lib/backlog.py:202) prend le verrou, RELIT le disque, ne pose que les champs passes, et reecrit ce document frais ; `load_backlog()` (orchestrator.py:438) relit a chaque tour. Aucun commit n'a touche backlog.yaml entre 23:00 et 23:35. Le premier travail est donc de REPRODUIRE la perte et de NOMMER l'ecrivain, pas de reparer le coupable suppose.
Constat annexe verifie : `machine_proved_to_validated` (lib/backlog.py:165) n'a AUCUN appelant, ni dans le harnais ni dans les tests — l'orchestrateur pose `validated` par `set_status` (orchestrator.py:1857 et 2026). C'est du code mort qui mute `self.items` sans ecrire ; s'il etait rebranche tel quel il ferait exactement la perte decrite.

## Livrable — le contrat, en entier

`pin_props_defects` = 0, somme de termes publies SEPAREMENT.
1. LA PERTE EST REPRODUITE ET SON ECRIVAIN EST NOMME. Un test ecrit un champ sur un item pendant qu'un tour d'orchestrateur passe, et publie qui l'a efface — ou publie que RIEN ne l'efface, auquel cas la cause est ailleurs et l'item la nomme. Un zero de perte se lit « pas reproduit », jamais « repare ».
2. Le chemin de lecture de `proof_props` est trace de bout en bout : ce que le fichier porte, ce que `proof_run.sh` extrait, ce que l'appareil rend a `getprop`. Publier les trois. L'ecart entre le premier et le troisieme est la grandeur qui compte.
3. Une course publie DESORMAIS le regime OBSERVE, pas le regime demande : au moins une cle par propriete epinglee, relue apres l'amorcage. C'est ce qui rend l'epinglage verifiable sans relire le backlog.
4. `machine_proved_to_validated` : soit elle est rebranchee et ecrit par `set_status`, soit elle est SUPPRIMEE. Une fonction morte qui muterait l'etat en memoire est un piege arme.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change aucun statut d'item existant.

## Ou l'owner regardera

Le harnais : lib/backlog.py, orchestrator.py, lib/proof_run.sh.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

