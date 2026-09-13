#pragma once

// sched_affinity — perf-thread-build : LE FIL GOAL TOURNE SUR UN GROS COEUR, ET ON LE MESURE.
//
// POURQUOI CE FICHIER EXISTE.
// ---------------------------
// Avant lui, `grep -rn "sched_setaffinity\|setpriority\|pthread_setschedparam" game/ android/`
// rendait ZERO : aucun fil du moteur n'avait ni affinite ni priorite. Le seul reglage existant
// etait en Java, `THREAD_PRIORITY_DISPLAY` pose sur le fil SDL (SDLActivity.java:2158), dont le
// fil GOAL herite par construction. Sur un SoC 2xA76 + 6xA55 (Redmi Note 9 Pro, cpu6/cpu7 a
// 2 323 200 kHz contre 1 804 800 kHz pour cpu0-5), EAS est libre de laisser `opengoal-rt` sur un
// petit coeur : la boucle GOAL, qui est le chemin critique de l'image, paie alors 30 % de
// frequence en moins ET une microarchitecture plus etroite.
//
// CE QUE CE MODULE FAIT, ET CE QU'IL NE FAIT PAS.
// ----------------------------------------------
// Il POSE : l'affinite des fils GOAL et GL sur l'ensemble des gros coeurs DETECTE (jamais une
// liste ecrite en dur : le meme binaire tourne sur le Honor de l'owner) et une priorite relevee.
// Il MESURE : sur quel coeur chaque fil a reellement tourne, image par image, et si le SoC a
// plafonne la frequence de ses gros coeurs pendant la course.
// Il ne juge rien d'autre : `sched_defects` est la SOMME de trois termes publies un par un.
//
// POURQUOI LA DETECTION EST DYNAMIQUE. « Les coeurs 6-7 » est vrai du Redmi et faux ailleurs.
// On lit `cpuinfo_max_freq` de chaque coeur et on appelle « gros » ceux qui portent la frequence
// maximale, A CONDITION qu'au moins un coeur porte une frequence plus basse. Sur une machine
// homogene il n'y a donc pas de « gros coeur », et le module publie `sched_topology=homogene`
// au lieu d'un verdict qui ne voudrait rien dire.
//
// POURQUOI LE PLAFOND DE FREQUENCE, ET PAS L'ETAT DE REFROIDISSEMENT. Mesure du 2026-09-13 sur
// eae4df44, appareil au repos a 58 degres : `/sys/class/thermal/cooling_device9` (type
// `thermal-cpufreq-6`) rend `cur_state=7` sur `max_state=13` pendant que
// `/sys/devices/system/cpu/cpu6/cpufreq/scaling_max_freq` vaut 2 323 200, c'est-a-dire le nominal.
// L'etat de refroidissement ne decrit donc PAS une limitation effective sur ce SoC. Le plafond
// `scaling_max_freq`, lui, est la grandeur que la mitigation abaisse et que le gouverneur
// respecte : c'est elle que la porte lit. L'etat de refroidissement et les temperatures sont
// publies A COTE, comme contexte pour l'owner (« la chauffe de l'appareil sur 10 minutes »).
//
// ARMEMENT. Le correctif est ON dans le binaire de l'owner — un acquis livre derriere un drapeau
// eteint n'existe pas. Le SEUL desarmement possible est le bras d'ablation du harnais, quand il
// nomme CET item avec `armed=0` : `pin_current_thread` ne pose alors rien, et `pct_big` s'effondre.

#include <cstdint>

namespace sched_affinity {

enum class Role {
  Goal,  // le fil qui porte KernelCheckAndDispatch (« opengoal-rt » sur Android, « EE » sur PC)
  Gl,    // le fil qui porte la boucle de rendu (SDLThread sur Android, le fil principal sur PC)
};

// Pose l'affinite gros coeurs et la priorite SUR LE FIL COURANT. A appeler DEPUIS le fil concerne
// (sched_setaffinity/setpriority visent le TID courant quand on leur passe 0). Idempotent par
// role : un deuxieme appel republie, il ne repose pas.
void pin_current_thread(Role role);

// Une image du fil GOAL. Echantillonne `sched_getcpu()`, entretient le releve thermique et
// publie la table toutes les 60 images. A appeler une fois par image, depuis le fil GOAL.
void goal_frame();

// Une image du fil GL. Echantillonne `sched_getcpu()` seulement : aucun fichier n'est lu ici.
void gl_frame();

// Priorite relevee pour un fil PC nomme (EE, EE-Worker, ...). Sans effet ailleurs que sur POSIX.
// `nice` negatif exige RLIMIT_NICE : sur un bureau ordinaire l'appel echoue, et l'echec est
// PUBLIE (`sched_pc_nice_applied`) au lieu d'etre suppose reussi.
void raise_pc_thread_priority(const char* thread_name);

}  // namespace sched_affinity
