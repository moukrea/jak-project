> LIS D'ABORD `prompts/item-owner-se-renseigner-sur-le-combo-le-plus-efficient-tou-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Le bon dosage de modèles et d'efforts pour chaque étage du harnais : efficient sans tourner en boucle, mesuré sur nos propres essais

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Cree le 19/09 par l'owner (JAK-182), cadre par le superviseur a 03:10. ETUDE DU HARNAIS, PAS DU JEU : elle se PUBLIE par `lib/census/<id>.sh` et se juge sur des GRANDEURS TIREES DE NOS PROPRES JOURNAUX, jamais sur des tarifs supposes ni des opinions. DONNEES DISPONIBLES (releve du superviseur) : 674 journaux d'essai `logs/<item>/attempt-NNN.jsonl` (1,4 Go) portant, pour chaque message de l'agent, le modele ET les compteurs de jetons (`message.usage` : entree, sortie, cache lu/ecrit) ; 950 verdicts `validator-NNN.txt` (337 verts) qui donnent l'issue de chaque essai ; les bannieres de `logs/orchestrator.log` donnent le profil par essai (277 opus-5, 134 gpt-6-astra, 27 fable-5-1[1m], 13 opus-5[ […suite dans le contrat]

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`model_mix_defects == 0` dans `reports/owner-se-renseigner-sur-le-combo-le-plus-efficient-tou/proof.txt`.
Le proof se produit par `lib/proof_run.sh owner-se-renseigner-sur-le-combo-le-plus-efficient-tou x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Rien à installer. Le rapport `reports/<id>/RAPPORT.md` se lit en cinq minutes : pour chaque profil qui a tourné (Opus 5, Fable 5.1, Codex Astra, avec et sans contexte long), le coût moyen d'un essai, la part d'essais réussis, la part d'essais qui tournent en boucle sur le même échec, et le partage des jetons entre l'agent principal, ses sous-agents et le superviseur ; puis UNE recommandation sous forme d'un profil prêt à activer (pas activé), avec son coût attendu par essai. Toi seul tranches le profil..

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
