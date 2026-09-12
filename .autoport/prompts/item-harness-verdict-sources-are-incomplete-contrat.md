# Tout ce qui PRONONCE un verdict est epingle, y compris le critere lui-meme — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

SEPT SIGNALEMENTS DU 12/09 (reports/harness-verdict-integrity/FINDINGS.txt). Le chantier precedent epingle les SCRIPTS qui produisent un verdict. Il en reste trois familles dehors, et un piege intermittent.
1. LE CRITERE LUI-MEME n'est pas epingle. `gate.key/op/value` et `frames_min` vivent dans `backlog.yaml`, que l'orchestrateur reecrit, et `verdict_sources_sha` ne les couvre pas. Un critere peut donc changer apres la course sans que la fraicheur s'en apercoive. Le critere produit le verdict autant que le script qui le calcule.
2. LES HUIT SCRIPTS D'ACQUIS (`.autoport/acquis/*.sh`) prononcent un verdict a CHAQUE fermeture (GATE 3) et ne sont epingles par rien : ni la fraicheur moteur, ni `verdict_sources`.
3. LA DERIVATION LIT LES COMMENTAIRES COMME DES CITATIONS : l'en-tete de `lib/ablation_anchor.sh` NOMME ses anciens lecteurs, ce qui les epingle par erreur. Un commentaire ne doit pas creer une dependance.
4. Les cles du teardown de FIN sont AJOUTEES a `proof.txt` apres le `mv` atomique, depuis le `trap EXIT` : un lecteur peut ouvrir le fichier entre les deux. Meme classe que la porte qui lit un artefact en cours d'ecriture.
5. DEUX BACS A SABLE ne copiaient pas les fichiers que la porte s'est mis a appeler (`pin_props_selftest.sh` pour `impossible.py`, `test_proof.py` pour `verdict_sources.sh`). Un bac a sable incomplet fabrique un rouge qui ne decrit aucun defaut.

## Livrable — le contrat, en entier

`verdict_sources_defects` = 0, somme de termes publies SEPAREMENT.
1. Le CRITERE entre dans l'empreinte epinglee : publier l'empreinte du critere jugee et celle relue a la fermeture. Preuve a deux bras — modifier le critere apres la course doit REFUSER dans le bras d'APRES et passer dans celui d'AVANT.
2. Les scripts d'acquis entrent dans la meme empreinte. Publier leur nombre et leur empreinte collective : un compte de huit qui tombe a sept est un defaut, pas un detail.
3. La derivation ignore les commentaires. Publier le compte de fichiers epingles avant et apres ce changement, et la liste de ceux qui sortent : chacun doit etre justifiable.
4. `proof.txt` n'est plus ecrit apres son propre `mv` : tout ce qu'il porte y est avant. Publier le compte d'ecritures posterieures observees, qui doit etre zero, et le CONSTATER sur une course reelle, pas sur une intention.
5. Un bac a sable declare ce qu'il copie a partir de la MEME liste que la porte reelle. Publier l'ecart entre les deux listes : zero, ou le defaut est compte.

## Hors perimetre

Ne touche a aucun code du jeu. Ne change aucun critere existant au passage. Priorite 32 volontaire : la refonte de l'eclairage passe AVANT.

## Ou l'owner regardera

Invisible. C'est ce qui a le droit de changer entre une preuve et son verdict.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

(aucun retour enregistre sur cet item)

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

