#pragma once

// settings_case_l10n — LA MESURE DE L'ITEM `recharged-settings-case-l10n`.
//
// LE DEFAUT QUE L'OWNER DECRIT (2026-09-04) : « tous les elements sont en majuscule dans les
// reglages rechargees, et pas tous sont localises correctement. » (2026-09-05) : « Traduire
// celles qui restent en anglais dans toutes les langues supportees par le jeu ! »
//
// CE QUI EST MESURE, ET POURQUOI CE DECOUPAGE.
// -------------------------------------------
// Une ligne du menu Recharged est DESSINEE a partir d'un tampon `name-override` que
// `refresh-runtime-option-labels!` remplit depuis le banc de texte de la langue courante
// (goal_src/jak1/pc/progress-pc.gc). Deux moities, donc deux temoins :
//
//   * GOAL sait quelle LIGNE existe et quel identifiant de banc alimente son tampon. Il les
//     rapporte ligne par ligne (`note_label`), avec la chaine REELLEMENT posee dans le tampon.
//     Une ligne dont le libelle ne vient d'aucun identifiant est rapportee par
//     `note_uncovered_row` : elle ne peut etre traduite dans AUCUNE langue, c'est le defaut
//     de fond.
//   * Le C++ sait lire les 23 bancs `<n>COMMON.TXT` REELLEMENT LIVRES dans le dossier iso.
//     Il juge chaque identifiant dans CHAQUE langue.
//
// Le pont entre les deux est verifie, pas suppose : `mismatch` compte les lignes ou la chaine
// que GOAL a posee dans le tampon ne vaut pas la chaine du banc de la langue courante pour
// l'identifiant annonce. Sans ce terme, une table d'identifiants qui aurait derive du menu
// rendrait un zero qui ne parle de rien.
//
// LES QUATRE DEFAUTS COMPTES (leur somme est `settings_case_l10n_defects`) :
//   uncovered  — une ligne du menu sans identifiant de banc : intraduisible par construction.
//   caps       — un libelle rendu en TOUT-MAJUSCULES hors sigles, dans n'importe quelle langue.
//                La reference est le reste du menu : `0COMMON.TXT` porte `Graphic Options`,
//                `SFX Volume`, et `3COMMON.TXT` `Opciones graficas`. Ce menu ne doit pas s'en
//                distinguer.
//   missing    — identifiant absent du banc d'une langue TRADUITE : le jeu retombe sur l'anglais
//                (text.gc:73-111, `*fallback-text*`), et l'owner lit de l'anglais.
//   same_as_en — identifiant present mais dont la chaine est l'anglais mot pour mot, dans une
//                langue TRADUITE, alors que le libelle anglais contient au moins un mot qui n'est
//                pas un sigle.
//
// « LANGUE TRADUITE » EST MESURE, PAS DECRETE. Un banc est declare traduit quand plus de la
// moitie de ses entrees STOCK (identifiants < 0x1700, presentes des deux cotes) different de
// l'anglais. Mesure du 2026-09-05 sur les 23 bancs livres : 0.00 pour la langue 0 (en-US) et
// 0.02 pour la langue 6 (en-GB) — l'anglais britannique EST de l'anglais, l'y compter
// fabriquerait 70 faux defauts. Toutes les autres sont entre 0.58 et 0.90. Sans cette mesure,
// le seuil serait un choix ; avec elle, c'est un fosse.
//
// LA VACUITE EST UN ECHEC, PAS UN ZERO. Aucune ligne rapportee, ou moins de deux bancs lus, et
// le module publie une valeur SENTINELLE hors de portee de la porte : un compteur qui n'a rien
// regarde ne doit jamais dire « zero defaut ».

#include <cstdint>

namespace settings_case_l10n {

// Debut d'un recensement. `current_language` est `(-> *pc-settings* text-language)`.
void begin_census(int current_language);

// Une ligne du menu Recharged dont le libelle vient de l'identifiant de banc `text_id`.
// `shown` est la chaine que le menu DESSINE pour cette ligne dans la langue courante, en
// octets de la police jak1 (pas de l'UTF-8).
void note_label(int text_id, const char* shown);

// Une ligne du menu Recharged dont le libelle ne vient d'aucun identifiant de banc.
void note_uncovered_row(const char* who);

// Fin du recensement : lit les bancs livres, juge, publie.
void end_census();

}  // namespace settings_case_l10n
