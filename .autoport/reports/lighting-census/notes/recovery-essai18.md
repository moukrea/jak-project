# Provenance consommée — essai 18
DIRECTIVES v6fca51fe40

## Changement livré
Le module `game/system/asset_manifest` produit un manifeste distinct quand
`OG_REFSET_ASSET_MANIFEST` désigne un chemin neuf et `OG_REFSET` vaut capture/replay.
Il emploie le SHA256 complet existant de RPack sur les buffers fournis, sans relire
leurs chemins. Les noms sont encodés en hexadécimal ; offsets et longueurs sont explicites.
Le fichier est réservé par O_EXCL, les écritures protégées par mutex et leurs erreurs fatales.
Le checkpoint est le SHA256 des lignes asset uniques triées, avec leur LF de consommation
d'image dans le label. C'est un ensemble cumulé, pas une preuve d'ordre de chargement,
de liaison des textures aux draws, ni de l'état des acteurs. Les répétitions sont dédupliquées.

Points branchés : buffers de lecture ISO Jak1 ; FileLoad ; objets avant relocation dans
jak1_jak2_begin ; les deux lectures FR3 ; shaders après preprocessing ; textures de base
et cartes PBR au téléversement, y compris plans R8 et payloads KTX2. Les cartes portent leur
sémantique (normal/roughness/etc.) pour ne pas confondre un échange entre deux cartes.
L'empreinte échantillonnée du hotreload, le registre historique, les sidecars v2 et la
qualification restent inchangés. Aucun champ de preuve supplémentaire ni crédit de porte.

## Exécution et contrôles
`essai18-assets/build.log` : cible gk incrémentale liée, garde PNJ47 tenue ; aucun build GOAL,
NDK ou reconfiguration manuelle. SHA livré14ab30c2a18899f6.
`asset-test.log` : PASS SHA complet (mutation octet17000), ordre inverse, doublons concurrents,
checkpoint vide, encodage, refus d'écrasement/symlink, configuration invalide et erreur I/O.
Une seule preuve60s, sans nouveau bootstrap : script `essai18-assets/run.sh`.
`proof-run.log` : rc0, crash0, frames3287 ; `run.log` :5880records79fb964dc17507ec,
dispatch10/PID12, compared1, maxdiff195/diffpx57581, slip0..0. L'écart historique est inchangé
par rapport à l'essai17 ; cela ne démontre pas l'identité des pixels entre ces deux essais.
`manifest-audit.log` : checkpoint origine/h00/chain-lf1081 validé par hashlib,
2133entrées =4FR3+749plagesISO+485objets+108shaders+787textures-base.
SHA checkpoint d11b3282507e3ffdc4440187d99133b88cc50f68e560cbac14dd430dbf4bf4ed.
Fichier final2141entrées,119209054octets de payloads ; son ensemble comprend aussi des
lectures après checkpoint. SHA fichier884904f7166cceebe5b88f46cb6aae63bc7e202bc01e0afb5e0a6eed36a79224.
Les4FR3 GAME/title/village1/beach et5objets sont corroborés avec les octets disque.
Aucune branche texture-map ni FileLoad vue dans cette course. Ces branches restent non prouvées.
575SHA historiques OK avant/après ; gk/3CGO/pad/bootstrap/12sources inchangés pendant la mesure.
Le builder2541075 était idle, suspendu dans le shell long avec trap, puis repris (tester STAT Ss).

## Baseline indépendante : piste concrète, pas qualification
`essai18-assets/baseline-audit.txt` reproduit l'audit de sources : commit pré-refonte
a9ea15a69062a57335278db7680cd647df3c1e1d,163exports contre173actuels,10ajouts/0retrait.
FR3v44 avec baked_tangents déjà présent ; aucun delta goalc/mips2c depuis ce commit.
La compatibilité en exécution n'est pas établie. Cette baseline serait le fork pré-refonte,
pas le moteur pristine : son atlas gamefontnew contenait déjà un contournement du maître.
Étape suivante : source isolée à ce commit, adaptateur avec les10exports RÉELS et le protocole
actuel, en conservant renderer ET shaders historiques distincts. Les shaders x86 viennent
du disque : partager ceux de HEAD invaliderait l'indépendance. Aucun adaptateur ni binaire
baseline nouveau n'a été construit dans cet essai. Le pristine existant reste intact.

## Reste explicite
Le manifeste ne couvre pas toutes les configurations matérielles/params et ne certifie pas
l'état après bootstrap : beach était encore loading à la frontière17. Il n'est pas lié à une
attestation baseline/candidat et ne permet aucune adoption v2. Aucun candidat capturé/adopté.
Il reste à qualifier origine à données/état identiques, fournir le producteur/consommateur
d'attestation v2, couvrir trois modes/21niveaux/8heures/≥4intérieurs/ciel puis cinq rejeux exacts.
Liste des20niveaux absents de la comparaison courte dans proof.txt : training, beach, jungle,
jungleb, misty, firecanyon, village2, sunken, sunkenb, swamp, rolling, ogre, village3, snow,
maincave, darkcave, robocave, lavatube, citadel, finalboss. Village1 n'a qu'origine/h00/intérieur.
Sunkenb reste manquant, ciel insuffisant. Ni HDR/SDR corrigé, ni Android testé, ni appareil touché.
Generic reste réservé à l'orchestrateur. Aucun owner-ok, aucun assouplissement de sentinelle.
