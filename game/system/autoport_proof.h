#pragma once

// autoport_proof — LE PUBLICATEUR QUE `lib/proof_run.sh` MOISSONNE.
//
// POURQUOI CE FICHIER EXISTE.
// ---------------------------
// `.autoport/lib/proof_run.sh` ecrit `reports/<id>/proof.txt` et `validators/generic.sh` le juge.
// Le validateur exige DEUX choses que seul le moteur peut produire :
//
//     FEATURE <id-de-l-item> armed=<0|1> hits=<n>      (n > 0, sinon « rien ne prouve que la
//                                                       feature a tire »)
//     <cle>=<valeur>                                   (la grandeur nommee par le `gate:` de
//                                                       l'item, SEULE SUR SA LIGNE)
//
// Aucune des deux n'existait : `grep -rn "AUTOPORT_FEATURE\|debug.opengoal.feature" game/ common/`
// rendait zero le 2026-09-03, alors que `proof_run.sh` pose les deux depuis sa premiere version.
// L'en-tete de `proof_run.sh` le dit lui-meme : « CE QUE LE MOTEUR DOIT EMETTRE (pas encore
// branche) ». Tant que ce module n'existe pas, AUCUN item du backlog ne peut passer sa porte,
// quel que soit le travail fait sur le defaut.
//
// CE QUE CE MODULE N'EST PAS. Il ne juge rien et ne connait aucun item. Il transporte : un
// identifiant lu dans l'environnement (bureau) ou dans une propriete systeme (appareil), un
// compteur que le code de la feature incremente lui-meme, et des couples cle/valeur que ce meme
// code publie. Le verdict reste au validateur.
//
// L'ARMEMENT, ET POURQUOI LE DEFAUT EST « ARME ».
// ----------------------------------------------
// `armed()` rend VRAI quand rien n'est pose. C'est deliberé : une correction livree derriere un
// drapeau eteint par defaut n'existe pas pour l'owner — il joue le binaire tel quel, sans
// propriete. Le desarmement n'a lieu QUE si la propriete `debug.opengoal.feature` nomme
// exactement l'item concerne ET que `debug.opengoal.feature.armed` vaut 0 : c'est le bras
// d'ablation que `proof_run.sh --off` demande, et rien d'autre ne peut y tomber par accident.
//
// LE COMPTEUR. `note_hit()` ne compte que quand la feature est ARMEE. C'est ce qui rend
// l'ablation lisible : le bras desarme doit publier `hits=0`, sinon il ne prouve pas que le
// chemin de code s'est bien tu. Un compteur qui monte des deux cotes ne separe rien.
//
// LES IMAGES. `frame_tick()` publie `AUTOPORT-FRAMES n=<images>`. `proof_run.sh` cherche ce motif
// (ou `PACE-SWAP n=`, ou `A35-RENDER frame=`) pour remplir `frames=` ; sur l'appareil AUCUN des
// trois n'etait emis, donc toute preuve appareil sortait avec `frames=0` et le validateur la
// refusait pour « rien n'a ete dessine assez longtemps ». C'est une panne d'instrument, pas du
// jeu.

#include <cstdint>

namespace autoport_proof {

// Identifiant d'item demande par le harnais, "" si aucun. Env `AUTOPORT_FEATURE` (bureau) ou
// propriete `debug.opengoal.feature` (Android). Lu une seule fois, au premier appel.
const char* feature_id();

// Vrai si le harnais a demande CET item. Un code de feature s'en sert pour savoir s'il est sous
// mesure ; il ne doit JAMAIS s'en servir pour changer son comportement en dehors de l'ablation.
bool feature_is(const char* id);

// Etat d'armement. VRAI par defaut (voir l'en-tete). Faux uniquement quand le harnais a nomme un
// item ET pose `armed=0`.
bool armed();

// Etat d'armement POUR UN ITEM NOMME. Identique a `armed()` quand le harnais parle de CET item,
// VRAI dans tous les autres cas. `armed()` est global : si le harnais mesure l'item A avec
// `armed=0`, il desarme du meme coup le correctif de l'item B, qui n'a rien demande — deux
// features livrees se desarment l'une l'autre et la course ne mesure plus le binaire de l'owner.
// Un correctif qui se debraye consulte donc CETTE fonction avec son propre identifiant.
bool armed_for(const char* id);

// Le chemin de code de la feature vient de tourner. No-op quand la feature est desarmee : c'est
// ce qui fait la difference entre les deux bras de l'ablation.
//
// CE COMPTEUR-CI EST GLOBAL, ET IL LE RESTE (proof-feature-hits-is-vacuous, 2026-09-12). Un site
// qui l'appelle sans nommer d'item remplit le `hits=` de TOUS les items a la fois : c'est ce qui
// rendait « rien ne prouve que la feature a tire » indeclenchable. Sa prise est desormais rangee
// dans le seau `__unattributed`, publie sous `proof_feature_hits_unattributed`, et AUCUN item ne
// peut s'en prevaloir. Un site qui sait a quel item il appartient appelle `note_hit_for`.
void note_hit(uint64_t n = 1);

// LE MEME GESTE, ATTRIBUE. La prise est comptee pour `id` ET dans le total global. C'est ce
// compte-la — `proof_feature_own_hits` — que `validators/generic.sh` lit pour decider si
// l'instrument de l'item mesure a tourne. Deux items qui tirent sur la meme course rendent donc
// deux comptes DIFFERENTS, ce que le compteur partage ne pouvait pas faire.
// L'armement reste GLOBAL (voir `note_hit`) : le bras `--off` doit publier `hits=0` partout,
// sinon l'ablation ne separe rien.
void note_hit_for(const char* id, uint64_t n = 1);

// CE BINAIRE PORTE UN SITE DE L'ITEM `id`. Enregistre au CHARGEMENT, avant toute image : c'est
// ce qui separe les deux zeros que la porte confondait —
//   `absent`             : aucun site de cet item n'est compile ici (item de harnais, ou
//                          instrument jamais ecrit) ;
//   `declared_unreached` : le site existe et n'a pas ete atteint par la course (defaut).
// Une declaration faite a l'EXECUTION ne saurait pas les distinguer : un chemin jamais atteint
// ne s'enregistrerait pas plus qu'un chemin absent. On utilise la macro, pas la fonction.
void register_site(const char* id);
struct FeatureSite {
  explicit FeatureSite(const char* id) { register_site(id); }
};

#define AUTOPORT_FEATURE_SITE_JOIN2(a, b) a##b
#define AUTOPORT_FEATURE_SITE_JOIN(a, b) AUTOPORT_FEATURE_SITE_JOIN2(a, b)
// A poser au niveau NAMESPACE du .cpp qui porte le site (jamais dans une fonction : la
// construction serait paresseuse et l'enregistrement suivrait l'execution).
#define AUTOPORT_FEATURE_SITE(id)                                            \
  [[maybe_unused]] static const ::autoport_proof::FeatureSite                \
      AUTOPORT_FEATURE_SITE_JOIN(g_autoport_feature_site_, __LINE__)(id)

// Une grandeur mesuree, publiee telle quelle sur sa propre ligne (`cle=valeur`). La DERNIERE
// valeur publiee pour une cle gagne — c'est la regle de moissonnage de proof_run.sh. La cle doit
// respecter `[A-Za-z_][A-Za-z0-9_]*` ; une cle qui ne la respecte pas est refusee en silence
// plutot que d'ecrire une ligne que le moissonneur ignorerait.
void publish(const char* key, uint64_t value);

// La meme chose pour une valeur qui n'est pas un entier (un rapport, un coefficient de variation) :
// publiee telle quelle, sans espace (tout caractere blanc est remplace par `_`, sinon le moissonneur
// de proof_run.sh — `^cle=[^[:space:]]+$` — ignorerait la ligne). Une cle porte soit un entier soit
// un texte : le dernier `publish*` gagne.
void publish_text(const char* key, const char* value);

// Vrai si une valeur a deja ete publiee sous cette cle (entier ou texte). Sert a un module qui
// doit dire ce qui MANQUE a la preuve en lisant la table qui sera moissonnee, pas ses propres
// variables (perf-instruments).
bool has_key(const char* key);

// LE RECENSEMENT DES CONSULTATIONS DE L'ARMEMENT PAR DU CODE DE JEU (hd-stretch-flag-in-game-logic).
// -----------------------------------------------------------------------------------------------
// Un drapeau du HARNAIS ne doit pas decider de ce que le jeu FAIT. Le seul geste legitime est
// l'ablation que les DIRECTIVES reclament, et elle a une polarite obligatoire : quand le pont
// GOAL->C est muet, le comportement LIVRE doit rester. `armed_for()` rend 1 arme et le pont muet
// rend 0 : un site GOAL ecrit `(zero? (__pc-autoport-armed-for "x"))` se DESARME donc tout seul
// des que le pont manque. `disarmed_for` (0 = arme) est la polarite sure.
//
// Ces deux compteurs distinguent les deux familles. La porte lit la DANGEREUSE ; la SURE est le
// temoin qui rend le zero falsifiable : sans elle, un zero obtenu parce que le pont n'est pas
// relie sur l'appareil serait indistinguable d'un zero obtenu parce qu'aucun site n'existe.
enum FlagPolarity {
  kFlagDangerous = 0,  // le pont muet rend « desarme » : le jeu change tout seul
  kFlagSafe = 1,       // le pont muet rend « arme » : le comportement livre tient
};

// Un site de code de JEU vient de consulter l'armement du harnais, sous `id`. Appele depuis les
// ponts kmachine, jamais depuis le code de la feature.
void note_flag_consult(int polarity, const char* id);

// Publie le recensement (`proof_flag_*`). `hit_item_id` : l'item dont le `hits=` doit compter
// cette prise. `hits` est PARTAGE par tout le binaire — un `note_hit` inconditionnel remplirait
// le compteur de TOUS les items et rendrait « rien ne prouve que la feature a tire » indeclenchable.
void publish_flag_census(const char* hit_item_id);

// Une image de plus. A appeler une fois par image, du meme endroit que le reste du recensement.
// Emet periodiquement le bloc complet (images, FEATURE, toutes les cles).
void frame_tick();

// Emet le bloc complet tout de suite (fin de scene, fin de course).
void flush();

}  // namespace autoport_proof
