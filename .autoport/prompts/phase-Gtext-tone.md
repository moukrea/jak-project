# Gtext-tone — le ton des textes : moins formel, raccord avec l'esprit du jeu

## La demande (owner 2026-08-28)

> « "Appuyer sur la touche start" c'est hyper formel et l'infinitif est bizarre... Ça colle pas à
> l'esprit teenager du jeu. Ça devrait plutôt être "Appuies sur start" (et sur mobile "Appuies sur
> start ou touche l'écran"), de même dans les autres langues, moins formel, moins robotique... pour
> tous les hints genre bouton à appuyer pour parler à un PNJ et interactions (genre les portails).
> C'est pas une quantité astronomique de trucs à changer, mais ça rendrait le jeu plus moderne et
> raccord avec son ton teenage. C'est à faire SEPAREMENT de la refonte du système d'affichage de
> texte avec la font Urbanist hein ! »

**Phase SEPAREE de `Gfont-urbanist`, par ordre explicite de l'owner.** Ne toucher a aucun code de
rendu ici : uniquement le CONTENU des textes.

## PORTEE MESUREE — plus petite qu'annoncee

Comptage sur `game/assets/jak1/text/game_case_text_*.json` :

- **Les indices en jeu sont DEJA au bon ton.** Le francais dit deja « Appuie sur <PAD_CIRCLE> pour
  parler. », « Appuie sur <PAD_CIRCLE> pour te teleporter » — imperatif, tutoiement. Rien a y faire.
- **Seules 8 chaines sur 626 sont a l'INFINITIF** en francais, et elles sont toutes de niveau
  systeme/menu :

      Appuyer sur la touche start          <- celle que l'owner cite
      Utiliser touches directionnelles
      Choisir fichier de sauvegarde
      Choisir une sauvegarde a charger
      Utiliser l'option de sauvegarde pour sauvegarder manuellement...
      Inserer une Memory_Card_(PS2) avec un espace libre suffisant...
      Inserer une Memory_Card_(PS2) contenant des donnees de Jak and Daxter...
      Inserer le disque de Jak and Daxter pour continuer a jouer

- L'anglais dit deja « Press Start » : rien a corriger la.
- Langues avec fichier de casse : de-DE, en-GB, en-US, es-ES, fr-FR, it-IT, ja-JP. Les autres
  n'en ont pas encore et sortent du perimetre tant qu'elles n'en ont pas.

## Ce qu'il faut faire

1. **Passer ces 8 chaines (et leurs equivalentes dans chaque langue) a l'imperatif, en tutoyant.**
   « Appuie sur start », « Utilise les touches directionnelles », « Choisis ta sauvegarde »...
2. **Variante tactile sur mobile** : l'owner veut « Appuie sur start ou touche l'ecran ». C'est une
   chaine NOUVELLE, pas une reecriture : il faut une variante selectionnee quand l'appareil est
   tactile. Verifier s'il existe deja un aiguillage tactile/manette dans le systeme de texte avant
   d'en creer un.
3. **Passer en revue les autres langues avec la meme regle**, pas une traduction mot a mot du
   francais : l'espagnol et l'italien ont leurs propres formes familieres.

## Detail d'orthographe, a appliquer sans le discuter

L'owner ecrit « Appuies ». La forme correcte a l'imperatif est **« Appuie »** (sans s), et c'est
deja celle qu'emploient les chaines existantes du jeu. Livrer « Appuie », par coherence avec les
indices deja en place.

## Interdits

- Ne pas toucher aux textes de dialogue ni aux sous-titres : la demande porte sur les INDICES et
  les invites d'interface.
- Ne pas modifier le systeme de rendu de texte : c'est le sujet de `Gfont-urbanist`.

## Exige pour fermer

1. La liste AVANT/APRES des chaines modifiees, par langue.
2. La variante tactile existe et est prouvee selectionnee sur un appareil tactile.
3. Aucun depassement de boite : les nouvelles formulations sont plus courtes ou egales, le verifier
   sur l'ecran-titre et les invites d'interaction.
