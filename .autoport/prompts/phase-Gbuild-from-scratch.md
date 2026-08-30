# Gbuild-from-scratch — un build depuis zero doit rendre le MEME etat que le notre

## L'exigence de l'owner (2026-08-29)

> « faut t'assurer qu'elle revienne pas par erreur, c'est un truc qui doit se corriger
> automatiquement au build from scratch quand ça exporte le modèle HD de Jak 2 ou 3 (idem pour les
> bones, retargeting des squelettes, physique et compagnie... Un utilisateur qui build le jeu from
> scratch devrait pouvoir avoir le même état que nous) »

## Pourquoi c'est structurel et pas un detail

Un correctif applique a la main sur un artefact GENERE disparait au prochain build propre. Le
projet en a fait les frais QUATRE fois cette semaine, et a chaque fois la source etait juste :

- le masque de soudure de Keira, « supprime » depuis 15h53 le 28/08, encore present dans le modele
  livre — fichier vieux de ONZE JOURS ;
- le texte anglais converti en casse normale, et l'APK livrant une copie de DIX-SEPT JOURS ;
- l'atlas precurseur corrige de ses sept glyphes inverses, corrige mais PAS LIVRE ;
- une piece justificative archivee qui publiait 92 divergences pour un travail juste.

**Un utilisateur qui construit depuis zero est en permanence dans ce cas.**

## Ce qui doit etre reproductible

Tout ce qui derive des modeles HD de Jak 2 / Jak 3 :

1. **Suppression des pieces parasites** — le masque de soudure (`mask`, `maskstrap`, 173 sommets
   poses au sol, joint parente a la RACINE) doit etre retire PAR L'EXPORTEUR, sur un critere
   NOMME, pas par une suppression ponctuelle.
2. **Les os et leur hierarchie**, y compris le parentage de la boucle de sangle corrige le 30/08.
3. **Le retargeting des squelettes** donneur -> jak1.
4. **Les poids de peau**, y compris la regle de reskin corrigee le 30/08 : elle fabriquait quatre
   sommets de veste domines par l'os de la sangle la ou ND en avait ZERO.
5. **La configuration physique** derivee du rig. `physics_chains.txt` est deja genere depuis le rig
   par motif de nom + hierarchie : c'est le bon modele a suivre pour le reste.

## Critere de reussite

1. **Depuis un arbre propre, sans aucun artefact pre-existant** : construire, puis comparer le
   modele produit a celui qu'on livre aujourd'hui. Meme absence de masque, memes joints, memes
   poids, meme configuration physique. **Publier la comparaison, pas l'affirmation.**
2. **Reconstruire DEUX fois de suite et obtenir le meme resultat.** Le projet a deja rencontre un
   artefact derive non reproductible : cinq constructions, cinq empreintes differentes, sources
   inchangees. Publier les empreintes des deux courses.
3. Nommer tout ce qui NE PEUT PAS etre reproduit et pourquoi. Un point non reproductible qui est
   NOMME vaut mieux qu'un silence.

## Interdits

- Ne pas « corriger » en reintroduisant une suppression manuelle dans un script de post-traitement :
  ce serait le meme defaut deplace.
- Ne pas relancer `physics_keira_gen` a l'aveugle : il a deja detruit des chaines une fois.
  Regenerer puis COMPARER, jamais remplacer sans diff.
