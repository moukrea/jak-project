> LIS D'ABORD `prompts/item-harness-delivery-stale-bake-recovery-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# La fabrication des APK reprend apres un refus de donnees precalculees perimees

## Defaut cite
- 2026-09-14 : « Reprise superviseur requise pour : harness-delivery-stale-bake-recovery. Ces priorités sont bloquées. Lis leurs derniers handoffs et journaux de validation, identifie la cause, corrige le harnais ou le périmètre nécessai… »

## Cause connue
Diagnostic superviseur du 14/09 apres six refus : correctif a9317464c4 deja produit ; delivery_stale_bake_defects=0 sur 22 cas a l essai 3. Essai 1 refuse sur rouge herite de suite ; essais 2-3 sur collecte acquis Urbanist exposee a /tmp sature ; essais 4-6 sur identite de preuve ancienne conservee volontairement faute de prealable corrige. Cause exacte du timeout Urbanist non demontree, risque quota etabli. Dependance temporaire obligatoire avant reprise. Les demons fonctionnent normalement, sans surcharge ADB ; ne pas les relancer.

## Livrable
Reparer la reprise de construction au point de production : les donnees de cuisson requises doivent etre remises a jour par le chemin de build autorise avant empaquetage, sans reconfiguration CMake ni modification du format moteur. Un echec ne doit pas etre memorise comme une construction reussie ni abandonne jusqu au prochain changement moteur. Banc isole couvrant donnees perimees, echec de cuisson, succes puis absence de changement : tentative retentee apres echec, repere avance seulement sur APK complet, publication reservee a un artefact coherent. Publier delivery_stale_bake_defects et les populations testees via le producteur de preuve. Ne pas lancer de campagne ni contacter un appareil.

## Preuve exigee
`delivery_stale_bake_defects == 0` dans `reports/harness-delivery-stale-bake-recovery/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-delivery-stale-bake-recovery x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : La livraison de nouveaux builds reprend ; pas de validation visuelle..

## Hors perimetre
Aucun fichier moteur, aucun appareil, aucune relance de l orchestrateur. Pas de suppression des gardes STALE BAKE. Ne pas retoucher les mesures AO.
