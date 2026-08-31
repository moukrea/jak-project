# Gjak1-crate-collision — DES CAISSES SANS COLLISION A GEYSER ROCK. Priorite haute.

Retour owner mot pour mot : `.autoport/reports/Gjak1-crate-collision/owner-defects.txt`.

## Pourquoi c'est prioritaire
Une caisse qu'on traverse est une caisse qu'on ne peut pas casser : ramassages perdus,
progression bloquee. L'owner l'a vu sur DEUX builds a un jour d'ecart, donc ce n'est pas
un hasard de course.

## L'indice a exploiter en premier
La phase `Gjak2-polish`, parquee par l'owner le 2026-07-10, decrit LE MEME symptome :
« collision REGRESSION game-breaking (no crates, no moving-platform landing) from the
crouch-fix nav/collide enablement ». La cause y est nommee. Verifie si ce chemin est
partage avec jak1 ou s'il a ete reactive ici. A CONFIRMER PAR LA MESURE, pas a supposer :
le symptome peut etre commun et la cause differente.

## COMPLEMENT OWNER (2026-08-31) — LIS CECI AVANT DE CHERCHER
« les caisses sont là mais je passe au travers », « pas toutes », « des fois aucunes »,
« c'est pas toujours les mêmes ».
 - Les caisses sont DESSINEES : l'acteur nait bien. Le defaut est dans l'ENREGISTREMENT
   ou l'ACTIVATION de la collision, pas dans le spawn ni le chargement.
 - Ce ne sont PAS toujours les memes : une donnee de collision cassee est EXCLUE, elle
   ferait echouer les memes caisses a chaque fois. Ne cherche pas dans les fichiers de
   niveau ni les maillages : c'est un defaut d'ETAT A L'EXECUTION.
 - Une course entiere peut etre propre : publie le compte PAR COURSE, jamais un agregat.
Instrumente le triplet qui tranche : pour CHAQUE caisse nee — son identite, si sa forme
de collision a ete allouee, et l'occupation du pool a cet instant. Il departage entre
budget epuise, course d'initialisation, et allocation qui echoue en silence.

## L'intermittence interdit la course unique
« c'est un peu random ». Une course propre ne prouve RIEN. Compte les caisses : combien
sans collision, sur combien testees, sur combien de courses. Publie les trois nombres.

## Depuis quand
L'owner l'a vu le 2026-08-30 au soir. Les archives datees sont sur jak-builds
(app-jak1-<date>-<commit>.apk) : bissecte dessus pour encadrer l'apparition, plutot que
de deviner en lisant le journal des modifications.

## Format des marqueurs
    RESULT: CRATES SOLID
    CRATEREPRO course=<n> caisses_testees=<n> caisses_sans_collision=<n> niveau=training
    CRATEBISECT build=<nom-apk> commit=<sha> caisses_sans_collision=<n>
    CRATECAUSE nommee=<...> methode=<mesure|ablation> lien_jak2=<oui|non|indetermine>
    CRATEOK courses=<n> caisses_testees=<n> caisses_sans_collision=0
Verifie : au moins 2 lignes CRATEREPRO avec caisses_sans_collision >= 1 (sans reproduction
rien n'est prouve) ; CRATEBISECT sur >= 2 builds pour encadrer l'apparition ; CRATECAUSE
nommee ; CRATEOK avec >= 3 courses, >= 20 caisses testees, et ZERO sans collision.
