# Le harnais parle sur Linear sous sa propre identité, pas sous celle de l'owner

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Owner 17/09 (JAK-180) : « Le harnais poste sur les issues en tant que Emeric Commenge (moukrea) parce que c'est un token personnel… c'est pénible car dur à dissocier, et surtout on bénéficie pas des notifs Linear du coup parce que tous les messages sont envoyés par… moi-même ». Deux voies : (1) un second compte Linear « Autoport » invite dans le workspace (organizationInviteCreate), sa propre cle API dans ~/.config/autoport/linear.env : aucun changement de code, l'owner recoit les notifications comme pour un collegue ; (2) une application OAuth Linear en mode acteur=application (identite « app »), qui demande la creation de l'app dans les reglages Linear par l'owner et un flux OAuth cote harnais. Recommandation : (1).

## Livrable
`linear_identity_defects` = 0 :

1. UN AUTEUR DISTINCT : tout commentaire du harnais (linear_sync --comment, changements de colonne, verdicts, annonces de build) porte un auteur different de l'owner ; publier l'identifiant utilisateur de l'auteur et celui de l'owner, differents.

2. LA DETECTION DES RETOURS NE DEPEND PLUS DU MARQUEUR : un commentaire de l'owner se reconnait par son auteur (user.id == owner), plus par l'absence du marqueur 🤖 (qui reste pour la lisibilite).

3. LES NOTIFICATIONS : un commentaire du harnais sur un ticket cree par l'owner lui produit une notification Linear (verifie par l'owner : une fois suffit).

4. RIEN NE CASSE : etiquettes, adoption des tickets, deplacements, reactions et annonces fonctionnent sous la nouvelle identite (une passe de synchro sans erreur, `--check` a 0 ecart).

## Preuve exigee
`linear_identity_defects == 0` dans `reports/harness-linear-own-identity/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-own-identity x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Sur Linear : les commentaires du harnais apparaissent sous un autre nom que le tien, et tu recois une notification quand il te repond..

## Hors perimetre
Pas de changement de la logique du miroir au-dela de l'identite. Tout ce qui n'est pas cet item.
