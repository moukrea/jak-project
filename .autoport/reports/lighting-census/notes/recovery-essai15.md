# Bootstrap avant play — essai 15
DIRECTIVES v6fca51fe40

## Implémentation et frontière

game/system/boot_replay fournit un flux autonome, identique dans le fork et le pristine.
Variables exclusives : OG_BOOT_REPLAY_CAPTURE=<fichier neuf> / OG_BOOT_REPLAY_REPLAY=<existant>.
Sans variable, appels passifs. Session OS neuve requise ; aucun reboot interne pris en charge.
Format versionné, type/tag/taille/contenu, compteur final et EOF strict. Capture exclusive,
IO vérifiées, checkpoints comparés sans écrasement ; empreinte des octets consommés après finish.
Les données opaques ont ici la représentation x86 commune ; aucun pointeur n'est transféré.
Les buffers du module sont sur le tas pour les appels sur pile GOAL. Branche Windows non compilée.

InitMachineScheme restaure les états complets std::mt19937 natifs et le R Mips2C AVANT GAME.
Sérialisation textuelle, locale classique et tampon fixe ; aucun seed arbitraire choisi.
DecodeTime enregistre/rejoue les huit octets RTC qui initialisent Knuth au chargement GAME.
Enveloppes EE/unix présentes, mais leurs tags n'apparaissent pas dans les 11 records mesurés.
Avant play : checkpoints VU-R, Knuth, random-generator, RNG natifs et compteurs display.
Display : 16 compteurs depuis offset776, cinq floats904..920, soit basic+772 sur148octets.
Après finish, aucune lecture d'horloge du jeu n'est modifiée par ce module.
Les acteurs créés/avancés après play ne sont PAS couverts par cette frontière.

L'empreinte scellée est transmise atomiquement au refset avant play. Elle entre dans
census_config_fingerprint : sidecars et sélection des lignes du registre incluent donc cet input.
Sans bootstrap, l'identité historique reste identique. Aucun refus de qualification n'est retiré.

## Exécutions

run-essai15.sh archive l'essai14, suspend le builder après vérification PID/idle, enregistre
un bootstrap20s, puis lance proof_run pour le rejeu60s. Son trap reprend le builder.
Aucun PNG neuf : le refset reste en replay historique. Le flux est fork-bootstrap.bin.
Les 11 records finissent avec8cafacae708f4b5a dans capture et les deux preuves.
Test autonome C++17 -Wall -Wextra -Werror : roundtrip/rejets rc0, empreinte b6ede934ecf3e6a1.

Revue finale : l'identité bootstrap manquait au registre. Après correction, build incrémental
13étapes puis replay-final-essai15.sh réutilise le flux, sans nouvelle capture. Première preuve
archivée essai15-avant-ledger. Config mesurée8a9493fa059e5429 contre1bc0c751a065de33.
Preuve finale exclusivement produite par lib/proof_run.sh ; generic jamais lancé.
3397frames, crash0, legacy/origine/h00, maxdiff202/diffpx794 ; aucun crédit census.
575 SHA historiques passent avant/après. Registre append-only, anciennes lignes conservées.
Origine1402218draws stock/classifiés0, GPU8.2137ms, rb_mismatch0, résiduel0,
shade_gate_reads_outside5 : aucune preuve de classification complète des trois modes.

## Pristine indépendant

Checkout /home/emeric/code/jak-original-v033, HEAD c4bc4d3ff4691902ff023319cb33df71c0040501.
Patch bootstrap seul : essai15-data/pristine-bootstrap.patch. Renderer/GOAL/pad/assets inchangés.
Calcul EE original ns*3/10 conservé ; aucune dépendance refset/render_pace/autoport_proof importée.
Premier build arrêté sur borne100objets à cause de curl : cette borne était trop grossière.
Reprise même arbre configuré sans cmake -B : rc0,167objets en142.5s ; logs conservés.
Binaire615f120e4e0de8f625d0111a173417ba89f45e9ded6ca544ce052ee53f976fe5.
Un test12s rejoue le flux fork : 11 records/empreinte identiques avant play ; rc124 = timeout demandé.
Commande, SHA binaires/CGO et logs sont dans essai15-data. Ce pristine utilise ses CGO DISTINCTS :
le test mesure la compatibilité du protocole/champs comparés, PAS la qualification des images.

## Reprise concrète

Au lieu du play automatique, armer un premier ListenerFunction : kernel-dispatcher utilise
reset-and-call avant le parcours de l'arbre acteurs (audit pristine gkernel.gc1317 puis1329).
Un wrapper pourrait faire play(#t,#f), puis initialize!(game-info,game,#f,continue).
initialize! crée un restart qui suspend avant start : cette séquence et les naissances suivantes
doivent être reproduites, pas masquées par une remise à zéro au moment de photographier.
Cet audit ne vaut pas implémentation : aucun wrapper ni restauration d'acteurs livré ici.
Des CGO/FR3 pristine communs aux deux moteurs ne qualifient pas les CGO fork livrés.
Restent références candidates complètes, qualification à données/état identiques, Sunkenb,
ciel/couverture et cinq rejeux exacts avant adoption et correction HDR.

Patches fork initial/final incluent les nouveaux fichiers ; SHA sources/entrées dans essai15-data.
Aucun appareil ni owner-ok. Builder2541075 repris. Rapport et handoff bornés aux mesures ci-dessus.
