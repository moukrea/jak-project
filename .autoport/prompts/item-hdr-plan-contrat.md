# Le plan de la sortie HDR, avant d'y toucher une ligne de plus — CONTRAT COMPLET

Ce fichier porte ce que la consigne, plafonnee a 2560 octets, ne peut pas contenir.
La consigne ORDONNE de le lire : elle est un resume, pas le contrat.

## Cause connue

LIS D'ABORD `reports/hdr-study/ETUDE.md`. Cinq refus de l'owner sur hdr-display-output, chacun corrige a l'aveugle. Owner 11/09 : « planifie de fou avant en prenant tout en compte, on va arreter de tourner en rond pendant des jours... je prefere des heures de planification pour un resultat beton que 45 iterations qui echouent ». Et il a corrige TROIS erreurs de lecture de l'etude, toutes retenues ici : (a) « la sortie HDR est l'identite du SDR par construction » est FAUX — c'est ce que fait la courbe actuelle, pas une loi ; si on calcule en HDR on peut sortir du HDR sans passer par la compression SDR. (b) Les entrees 8 bits (AO en GL_R8, ciel et palettes en RGBA8) sont NOS choix, pas des contraintes, et la refonte de l'eclairage les rouvre de toute facon. (c) « decider sur quel materiel le HDR est une cible » contredit son exigence permanente : ca doit s'adapter a TOUT ecran qui annonce du HDR, jamais a un appareil nomme.

## Livrable — le contrat, en entier

Un PLAN, pas une correction : `reports/hdr-plan/PLAN.md`. Aucun changement de rendu, aucune option ajoutee. Il doit contenir, chacun argumente et chiffre : (1) LE CHEMIN CIBLE, etage par etage, du calcul d'eclairage au pixel : ou la scene reste lineaire, ou elle est encodee, quelle precision a chaque etage, et OU SE BRANCHE la sortie HDR — qui ne passe PAS par la compression SDR. Dire ce qui change par rapport au chemin actuel, fichier par fichier. (2) LES ENTREES A ENRICHIR : pour chaque source aujourd'hui en 8 bits (occlusion ambiante, ciel, palettes de cycle jour/nuit, et toute autre trouvee), ce qu'elle devient, ce que ca coute en memoire et en cadence sur le Redmi, et ce que ca rapporte. Une source qu'on laisse en 8 bits doit etre justifiee. (3) L'ADAPTATION, SANS AUCUN APPAREIL NOMME : comment le chemin se regle sur ce que l'ecran ANNONCE et sur ce que le systeme ACCORDE, y compris quand il n'accorde rien. Aucune constante liee au Redmi ou au Honor nulle part. (4) L'ORDRE ET LES DEPENDANCES avec la refonte de l'eclairage en cours (lighting-ao-indirect, lighting-regimes, lighting-bake, lighting-materials, lighting-presets) : ce qui doit passer avant, ce qui se fait en meme temps, ce qui serait refait deux fois si on se trompe d'ordre. (5) CE QUI SE PROUVE SANS ECRAN HDR et ce qui exige du materiel — nommement, pour que l'owner sache ce qu'il devra juger de ses yeux et quand. (6) LES RISQUES : ce qui peut casser le SDR livre, ce qui peut couter de la cadence, et le retour arriere de chaque etape. Le plan se termine par une PROPOSITION DE CHANTIERS — decoupage, ordre, et pour chacun le verdict machine qui le fermera. Le superviseur la soumet a l'owner AVANT toute execution.

## Hors perimetre

AUCUNE correction, aucun changement de rendu, aucune option. Ce chantier produit un document. Corriger avant d'avoir planifie est precisement ce qui a coute cinq refus.

## Ou l'owner regardera

rien a voir : c'est un plan, il ne change pas le rendu ; owner_test=false

## Tous les refus de l'owner, dans l'ordre, mot pour mot

### 2026-09-11
> mais attention planifies de fou avant en prenant tout en compte, on va arreter de tourner en rond pendant des jours... je prefere des heures de planification pour un resultat beton que 45 iterations qui echouent

## Pourquoi ce fichier existe

Owner, 2026-09-11 : « faudrait pas perdre des infos, sinon justement le principe
iteratif est un peu detruit ». Chaque refus ajoute un verdict ; la consigne est
plafonnee. Ce qui en sort atterrit ici, jamais a la poubelle.

