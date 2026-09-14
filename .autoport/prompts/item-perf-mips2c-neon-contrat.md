# Les calculs d animation et de particules coutent moins sans changer leurs resultats — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

DIAGNOSTIC DE REPRISE : l hypothese de boucles source scalaires sans SIMD est refutee par old-codegen-review.txt. Le compilateur vectorisait deja os et joints. bones.gc active *use-new-bones* et execute new-bones-mtx-calc-asm, pas bones-mtx-calc : 0 operation de ce dernier et 0 image qualifiee, malgre joints/particules compares sans ecart. Le candidat os grossit de 716 a 4812 octets ; aucun gain demontre. Refset USB : hutte maxdiff233 et deux references plage absentes ; A/B x86 egalement incomplets. Le refset local origine contient beach-start-h09, mais presence ne prouve ni deploiement ni provenance/equivalence ; README impose origines immuables. Ne pas confondre cette piste de distribution avec une nouvelle reference qualifiee. Le lot de suppression gnd_oob du build normal est etabli et se conserve.

## Livrable — le contrat, en entier

Lot 1 : gnd_oob_check compile hors du build quand la prop n'est pas armee. Lot 2 : NEON (arm64) et SSE (x86) sur les trois noyaux les plus chauds selon goal_bucket_ms_*, bit-identiques (hd-mtx-check-all, A/B x86, ripple.cpp intact ou bit-identique car l'eau lit ripple-find-height). mips2c_parity_defects = ecarts bit a bit entre chemin scalaire et vectoriel sur 600 images + (refset_replay_maxdiff != 0). Gain publie par seau.
REPRISE DIAGNOSTIQUE OBLIGATOIRE AVANT NOUVELLE COURSE :
1. Auditer le code MACHINE existant et les chemins actifs ; choisir les trois noyaux effectivement executes dans le regime livre, pas l ancien os inactif. Les seaux classent des familles : ne pas pretendre en deduire un classement individuel. Raccorder les compteurs/comparateurs existants aux fonctions choisies, publier la table fonction/chemin/preuve d activite ; ne jamais modifier *use-new-bones* ni le scenario pour fabriquer une population. Si aucune troisieme cible pertinente n est etablie, rendre ce constat avant ajout de SIMD ou course.
2. Retirer des seuls noyaux de cet item les ajouts speculatifs qui n ont aucun benefice etabli, en preservant les travaux voisins. Un compilateur deja vectoriel n est pas une victoire de ce patch. Separer la fenetre de parite de 600 images de la fenetre de cout : oracle eteint pendant mesure de gain, compteurs d ecarts conserves ; aucune parite vide acceptee.
3. Reparer la selection/distribution du refset EXISTANT par le chemin autorise si le diagnostic le justifie : verifier noms reels des cas demandes, phases, heure, origine, manifeste, empreinte et provenance des fichiers locaux puis leur correspondance dans la preuve. Les deux origines sont immuables. Ne pas fabriquer beach-sun depuis beach-start, ne pas recapturer par-dessus, ne pas retirer hutte/plage ni convertir 255 en zero. Diagnostiquer hutte233 avant replay ; un lot encore absent/non equivalent interdit de refaire le meme run. Les corrections de preparation du harnais necessaires a ce perimetre sont autorisees.
4. Conserver les exigences hd-mtx-check-all, trois populations actives, 600 images, refset_replay_maxdiff=0, ripple et gain par seau. Le banc SSE/NEON deja vert ne remplace pas le resultat en jeu. Avant proof_run, consigner les changements effectifs de cible et de references par rapport a l essai 1. Aucune campagne supplementaire autorisee par cette reprise ; utiliser uniquement le cycle de preuve deja prevu une fois ses prealables resolus.

## Hors perimetre

Aucun changement de resultat, meme au dernier bit. Ne touche a aucune feature validee. Reprise : ne pas porter new-bones-mtx-calc-asm vers un ancien chemin pour satisfaire le compteur, ne pas transformer l item en reecriture de tous les noyaux. Pas de nouvelle campagne de captures/refset ni de nouvelle origine implicite. Instrumentation de parite existante raccordable aux cibles actives, sans relacher les seuils. Conserver preuves historiques et modifications des autres items.

## Ou l'owner regardera

rien a voir : identique au pixel et a la pose ; goal_busy_ms baisse

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-15
> Reprise superviseur requise pour : perf-mips2c-neon. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic.

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.
