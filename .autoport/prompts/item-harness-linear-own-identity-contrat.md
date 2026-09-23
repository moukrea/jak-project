# Le harnais parle sur Linear sous sa propre identité, pas sous celle de l'owner — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

Owner 17/09 (JAK-180) : « Le harnais poste sur les issues en tant que Emeric Commenge (moukrea) parce que c'est un token personnel… c'est pénible car dur à dissocier, et surtout on bénéficie pas des notifs Linear du coup parce que tous les messages sont envoyés par… moi-même ». Deux voies : (1) un second compte Linear « Autoport » invite dans le workspace (organizationInviteCreate), sa propre cle API dans ~/.config/autoport/linear.env : aucun changement de code, l'owner recoit les notifications comme pour un collegue ; (2) une application OAuth Linear en mode acteur=application (identite « app »), qui demande la creation de l'app dans les reglages Linear par l'owner et un flux OAuth cote harnais. Recommandation : (1).

OWNER 17/09 21:10 : « C'est un peu dégueu non de créer un compte fake pour ça ? Il n'y a pas un moyen natif propre ? » -> VOIE RETENUE : (2) application OAuth Linear en mode acteur=application (c'est ce que font les integrations officielles et les « agents » Linear) : le harnais poste sous l'identite de l'application « Autoport », l'owner est notifie. Prerequis owner : creer l'application dans Linear (Settings > API > OAuth applications : nom Autoport, icone, redirect http://127.0.0.1:8765/callback, scopes read write comments:create issues:create), me donner client id + secret (dans ~/.config/autoport/linear.env, jamais dans le depot), puis UNE fois donner son accord sur la page d'autorisation (actor=app). Le harnais garde le jeton d'acces et le rafraichit.

## Livrable — le contrat, en entier

`linear_identity_defects` = 0 :

1. UN AUTEUR DISTINCT : tout commentaire du harnais (linear_sync --comment, changements de colonne, verdicts, annonces de build) porte un auteur different de l'owner ; publier l'identifiant utilisateur de l'auteur et celui de l'owner, differents.

2. LA DETECTION DES RETOURS NE DEPEND PLUS DU MARQUEUR : un commentaire de l'owner se reconnait par son auteur (user.id == owner), plus par l'absence du marqueur 🤖 (qui reste pour la lisibilite).

3. LES NOTIFICATIONS : un commentaire du harnais sur un ticket cree par l'owner lui produit une notification Linear (verifie par l'owner : une fois suffit).

4. RIEN NE CASSE : etiquettes, adoption des tickets, deplacements, reactions et annonces fonctionnent sous la nouvelle identite (une passe de synchro sans erreur, `--check` a 0 ecart).

## Hors perimetre

Pas de changement de la logique du miroir au-dela de l'identite. Tout ce qui n'est pas cet item.

## Ou l'owner regardera

Sur Linear : les commentaires du harnais apparaissent sous un autre nom que le tien, et tu recois une notification quand il te repond.

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-17
> C'est un peu dégueu non de créer un compte fake pour ça ? Il n'y a pas un moyen natif propre ?

### 2026-09-17
> Client ID: [SECRET-MASQUE]  Client Secret: [range dans ~/.config/autoport/linear.env, retire d ici]  Je te les donnes direct en commentaire, c'est pas sensible car nous deux seulement avons accès à cet espace.

### 2026-09-17
> Je rêve ou t'as supprimé le message avec le client id et client secret ?

### 2026-09-17
> Bah c'est parfait ça ! Du coup tu peux virer l'emoji bot de tes réponses aussi

### 2026-09-17
> Oui et pour moi c'est bon, je vois pas pourquoi on devrait attendre qu'un build soit publié pour ça du coup !

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

