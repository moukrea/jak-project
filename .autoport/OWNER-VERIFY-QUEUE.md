# CE BUILD EST IDENTIQUE AU PRECEDENT — ET J'AI UNE QUESTION POUR TOI

Branche `physics-keira-clean`. **Rien n'a change dans le jeu ce cycle.** Le moteur et les donnees
sont identiques au bit pres au build precedent (fichier de reglages restaure, md5 verifie). Si tu
vois une difference, c'est une information importante et inattendue — dis-le-moi.

Tout le cycle est de la **mesure**, et elle debouche sur **un choix qui t'appartient**.

---

## 1. CE QUE J'AI TROUVE, EN UNE PHRASE

Sa poitrine part **2,4 a 2,7 fois plus loin** que ta propre spec ne l'autorise, et je sais enfin
**quelle piece** le fait : ce n'est pas la deformation de la chair, c'est **l'os du haut de la
chaine qui bascule**. Il porte **62 %** du depassement.

Pourquoi cet os precisement : il mesure **1040 unites** alors que le sein entier en mesure **602**.
C'est un bras de levier **1,7 fois plus long que l'organe**. Du coup un retard parfaitement normal
— **onze degres** — suffit a manger **84 a 88 %** de tout le budget que ta spec accorde. Il n'y a
rien d'anormal dans le mouvement : c'est la **geometrie du squelette** qui transforme un petit
retard en gros deplacement.

## 2. LA QUESTION, ET C'EST TOI QUI DOIS TRANCHER

J'ai teste la seule manoeuvre disponible aujourd'hui : **souder cet os** (le figer sur le torse).

| | aujourd'hui | os soude |
|---|---|---|
| depassement de ta spec | **100 % du temps** | **0 %** (gauche) · **2,7 %** (droite) |
| sa poitrine traverse son thorax | 0,098 m | 0,087 m (−12 %) et 0,054 m (−40 %) |
| **mouvement de sa poitrine** | reference | **−50 %, sur TOUS les mouvements** |

**Le troc est de 1 pour 1** : je supprime la moitie du defaut en supprimant la moitie du mouvement.
Et la perte **n'epargne pas** les mouvements subtils que tu juges bons depuis le 11/08 : quand elle
se penche pour souder, c'est **−53 %** ; a l'arret complet, **−45 a −50 %**.

**J'ai donc RETIRE cette modification** — je ne te livre pas en douce une poitrine deux fois moins
vivante pour faire verdir un chiffre. Mais c'est un arbitrage de **qualite**, donc c'est le tien :

> **Veux-tu que je te livre une version « os soude » pour que tu la voies de tes yeux ?**
> Elle respecte ta spec sur l'amplitude, et elle bouge moitie moins. Un mot et je la construis.

## 3. CE QUE J'AI EU FAUX, ET JE TE LE DIS

J'avais grave **six predictions avant de mesurer**. **Quatre sont fausses**, dont les deux
principales :

1. Je predisais que souder cet os **ne suffirait pas** a rentrer dans ta spec. J'avais meme le
   calcul. **Faux** — ca suffit largement. Mon calcul supposait que les pieces etaient
   independantes ; elles ne le sont pas. La deformation de la chair **s'effondre avec l'os**
   (−49 % et −74 %), parce que c'est lui qui l'entrainait.
2. Je predisais que la perte de mouvement serait **plus faible qu'avant**, parce qu'un changement
   recent a rendu le bout de la chaine nettement plus reactif (sa frequence propre est passee de
   1,57 a 2,30 Hz). **Faux** : c'est exactement le meme prix qu'il y a neuf cycles. Le bout de la
   chaine **ne prend pas le relais** — sa rotation propre *baisse* meme legerement.

## 4. DEUX BONNES NOUVELLES QUE PERSONNE N'AVAIT PUBLIEES

- **Le defaut que tu decris sur ses cheveux n'existe pas sur sa poitrine.** « Le milieu bouge plus
  que les pointes » : sur la poitrine, le mouvement croit bien de la racine vers la pointe, sur
  **372 mesures sur 372**.
- **Son volume se conserve.** Ta spec demande 98–101 % ; c'est tenu sur **100 %** des mesures,
  avec une vraie deformation (±20 % de forme). Reserve honnete : le moteur **force** cette
  conservation, donc le chiffre prouve que la regle est appliquee, pas qu'elle emerge toute seule.

## 5. CE QUI RESTE ROUGE, ET NE SE CACHE PAS

- **Sa poitrine traverse toujours son thorax** : 0,098 m contre un plafond de 0,0005. Meme en
  soudant l'os, ca resterait 170 fois trop.
- **L'excursion reste hors bande** dans le build que tu as : 100 % du temps.
- **Ta SPEC 35 (son debardeur ne doit rien faire) reste absente** : elle demande un repesage du
  mesh que je n'ai pas fait ce cycle.
- **Sa SPEC 33 exige qu'ils s'entrechoquent** et le test du moteur ne peut pas le compter.

## 6. LA SUITE, ET ELLE A BESOIN DE TON FEU VERT SUR LE PRINCIPE

Le reglage est ferme (ta spec fixe la frequence, donc borne la raideur). Le soudage est ferme (1
pour 1). **Il reste le squelette** : raccourcir ce bras de levier baisse le depassement **sans
retirer un degre de liberte** — c'est la seule voie qui ne soit pas un troc. Tu m'as autorise a
toucher au rig le 17/08. **L'obstacle est reel et je ne le cache pas** : le rig HD n'accepte que
des ajouts en bout, donc on ne peut pas simplement glisser une articulation au bon endroit.
Etablir ce qui est faisable est le travail du prochain cycle.
