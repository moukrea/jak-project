DIRECTIVES v775512c234
# Profil du raccord physique — préparation

Le lecteur Python n'implémente aucun seuil ni calcul de bande :
`attempt10-profile-native.cpp` appelle directement `ao_contact_profile::analyze`
dans le header moteur inchangé. Seuil strict4/255, portée8+référence,
censure des plateaux et non-vacuité restent ceux du code existant.
`depth_jump=0` ne sert qu'au compteur de discontinuités ; aucune exclusion n'en dépend.

Construction locale (aucun build jeu/appareil) :

    g++ -std=c++17 -O2 -Wall -Wextra -Werror -I. .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-profile-native.cpp -o .autoport/reports/ao-prepass-tie-alpha/notes/attempt10-profile-native

Après attribution GPU v2 produite par `attempt10-analyze.py` :

    python3 notes/attempt10-profile.py ARCHIVE --attribution roi-gpu.json --qualification notes/attempt10-contact-patches.json --native notes/attempt10-profile-native --output contact-profiles.json

`attempt10-contact-patches.json` nomme deux patches sources TFRAG par empreinte
géométrique et offsets originaux : mur73087/73088/73089 et toit29051/29052/29053.
Le lecteur recalcule leur intersection3D, exige positions statiques et projection/
viewport communs, puis qualifie seulement les paires de pixels GPU uniques dont
le segment entre centres traverse la projection de cette intersection physique.
Un pixel voisin à l'écran sans cette condition ne qualifie aucun contact.
Les identités ne dépassent pas ces deux primitives ; pas de fusion par draw.

Chaque stage R8 archivé complet, même taille/frame et empreinte vérifiée, passe
au lecteur natif. Aucun rééchantillonnage. Populations nulles et profils censurés
restent explicites ; aucune somme globale de défauts n'est publiée.
Les distances signées/en pixels concernent la projection de l'intersection3D,
pas une relecture GPU des positions monde de chaque fragment.

L'archive SSAO de référence est au tick1400. Les futures captures au tick600
ne lui sont PAS déclarées équivalentes : caméra, animation et régime/mode peuvent
différer. Le profil compare d'abord les stages d'une même archive ; l'égalité
des entrées entre avant/après reste à établir, même si les ticks sont égaux.

Tests : attempt10-test-profile.log (pont natif bande1, plateau censuré,
population non qualifiée, intersection3D et segment écran).
