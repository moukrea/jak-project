# Un worker doit pouvoir epingler le regime de SA course, et le verifier — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

MECANISME ETABLI LE 12/09 — ce n'est PAS une reecriture du backlog.
`proof_run.sh` lit `proof_props` depuis le backlog a la ligne 145, puis lance `lib/device_teardown.sh` a la ligne 471, qui efface TOUTES les proprietes commencant par `debug.opengoal.` lues sur l'appareil, et seulement APRES pose les siennes (lignes 473 a 486). Une propriete posee par le worker depuis l'hote AVANT la course est donc effacee entre sa pose et le lancement. Seul `proof_props`, qui traverse le teardown dans une variable du script, survit. Signale par le worker du chantier C (reports/hdr-output-regime/FINDINGS.txt, dernier point), verifie ligne a ligne.
CE QUE J'AVAIS REFUSE D'ECRIRE, ET QUI ETAIT BIEN FAUX. Le worker de `hdr-glow-range` accusait l'orchestrateur de reecrire `backlog.yaml` depuis sa copie memoire. `set_status` (lib/backlog.py:202) prend le verrou, RELIT le disque et ne pose que les champs passes ; `load_backlog()` (orchestrator.py:438) relit a chaque tour ; aucun commit n'a touche le backlog entre 23:00 et 23:35 le 11/09. L'accusation ne tient pas. Le vrai coupable est le teardown.
CONSTAT ANNEXE VERIFIE : `machine_proved_to_validated` (lib/backlog.py:165) n'a AUCUN appelant, ni dans le harnais ni dans les tests — l'orchestrateur pose `validated` par `set_status` (orchestrator.py:1857 et 2026). C'est du code mort qui mute `self.items` sans jamais ecrire ; rebranche tel quel, il ferait exactement la perte que le worker imaginait.

## Livrable — le contrat, en entier

`pin_props_defects` = 0, somme de termes publies SEPAREMENT.
1. L'EFFACEMENT CESSE D'ETRE SILENCIEUX. Le teardown publie ce qu'il efface : le nombre de proprietes `debug.opengoal.*` trouvees posees a son passage, et leurs noms. Un worker qui en a pose une depuis l'hote doit pouvoir le LIRE dans la preuve, au lieu de mesurer l'autre regime sans rien voir. Un zero se lit « rien n'etait pose », jamais « rien n'a ete efface ».
2. Le chemin de lecture de `proof_props` est trace de bout en bout : ce que le fichier porte, ce que `proof_run.sh` extrait, ce que l'appareil rend a `getprop` APRES le teardown. Publier les trois. L'ecart entre le premier et le troisieme est la grandeur qui compte.
3. Une course publie DESORMAIS le regime OBSERVE, pas le regime demande : au moins une cle par propriete epinglee, relue apres l'amorcage. C'est ce qui rend l'epinglage verifiable sans relire le backlog.
4. `machine_proved_to_validated` : soit elle est rebranchee et ecrit par `set_status`, soit elle est SUPPRIMEE. Une fonction morte qui muterait l'etat en memoire est un piege arme.
5. Le chemin recommande est DIT quelque part qu'un worker lit : poser un reglage de course par `proof_props` dans le backlog, jamais par un `setprop` depuis l'hote avant la course.

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

