# La fabrication des APK reprend apres un refus de donnees precalculees perimees — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Diagnostic superviseur du 14/09 apres six refus : correctif a9317464c4 deja produit ; delivery_stale_bake_defects=0 sur 22 cas a l essai 3. Essai 1 refuse sur rouge herite de suite ; essais 2-3 sur collecte acquis Urbanist exposee a /tmp sature ; essais 4-6 sur identite de preuve ancienne conservee volontairement faute de prealable corrige. Cause exacte du timeout Urbanist non demontree, risque quota etabli. Dependance temporaire obligatoire avant reprise. Les demons fonctionnent normalement, sans surcharge ADB ; ne pas les relancer.

## Livrable — le contrat, en entier

Reparer la reprise de construction au point de production : les donnees de cuisson requises doivent etre remises a jour par le chemin de build autorise avant empaquetage, sans reconfiguration CMake ni modification du format moteur. Un echec ne doit pas etre memorise comme une construction reussie ni abandonne jusqu au prochain changement moteur. Banc isole couvrant donnees perimees, echec de cuisson, succes puis absence de changement : tentative retentee apres echec, repere avance seulement sur APK complet, publication reservee a un artefact coherent. Publier delivery_stale_bake_defects et les populations testees via le producteur de preuve. Ne pas lancer de campagne ni contacter un appareil.

## Hors perimetre

Aucun fichier moteur, aucun appareil, aucune relance de l orchestrateur. Pas de suppression des gardes STALE BAKE. Ne pas retoucher les mesures AO.

## Ou l'owner regardera

La livraison de nouveaux builds reprend ; pas de validation visuelle.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-14
> Reprends le rôle superviseur et le travail autorisé. Lis .autoport/SWITCH_HANDOFF.md et .autoport/SUPERVISOR_CATCHUP.md, puis les handoffs et FINDINGS récents. Rends compte du rattrapage, vérifie la santé du harnais et entretiens la file. Relance les démons de build/livraison listés dans .autoport/.backend.json si arrêtés. Pas de code jeu ni de contact appareil. La veille externe de run-codex.sh entretient l’orchestrateur.

### 2026-09-14
> Complément de reprise : la bascule est commitée (a9c0c2bb37 puis ad502cc6c1). Suite complète : 602 tests passent, journal .autoport/logs/backend-switch-tests-final.log ; test supplémentaire de contrôleur appelant et isolation des chemins : 3 passent. TMPDIR doit être hors /tmp, dont le quota utilisateur est atteint. Ancien orchestrateur et les deux anciens superviseurs Claude sont vérifiés absents. La veille et ton worker Codex sont vivants. Les démons de build/livraison restent à reprendre selon le prompt initial, puis confirme ton rattrapage et rends le statut à l’owner.

### 2026-09-14
> Correction de reprise : les démons doivent reprendre leur configuration normale. Je vois un lancement avec ADB=/usr/bin/false : cela désactive une fonction du harnais sans demande de l’owner. La demande initiale autorise la reprise du harnais existant, y compris ses démons automatiques de build/livraison ; le superviseur ne doit toujours pas exécuter adb lui-même. Arrête par PID exact les deux démons que tu viens de lancer et relance-les sans remplacer ADB par false, avec leurs gardes USB existantes. Cette remise à l’identique est autorisée, aucune nouvelle confirmation nécessaire.

### 2026-09-14
> Remise des démons effectuée depuis la session de bascule : arrêt des instances ADB=false et relance des deux scripts avec ADB non surchargé, configuration normale. Ne les redémarre pas à nouveau ; vérifie simplement les PID et poursuis ton rattrapage. Précision de périmètre également commitée dans SUPERVISOR_CATCHUP.md (8fe8e4d5f6).

### 2026-09-14
> Reprise superviseur requise pour : harness-delivery-stale-bake-recovery. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessaire et reprends le travail autorisé sous Codex. Ne te limite pas à annoncer l'arrêt ; ne valide rien et ne relance pas le même essai sans diagnostic.

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.
