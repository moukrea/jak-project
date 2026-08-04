# Gtouch-longjump-regression — le long jump au TACTILE est cassé (régression récente, bisectable)

## LE FAIT CLÉ (owner, 2026-08-04)
« Pour le long jump j'ai pas de manette, mais faut faire en sorte qu'avec le tactile ça fonctionne
aussi ! **Ça fonctionnait avant** donc il n'y a pas de raisons que ça fonctionne plus ! »
→ Ce N'EST PAS une limite du jeu ni du tactile : c'est une **régression récente**, donc bisectable.

## Repro exacte (owner, au tactile sur son device)
Courir vers l'avant + maintenir R1/R2 (zone tactile) + saut (X) → le saut est **annulé** :
au lieu du wheel/long jump on obtient duck-walk + saut normal. Systématique chez l'owner.

## Ce qui est DÉJÀ prouvé (hd-models3, ne pas refaire)
- x86, replay pad déterministe (cpad), toggle HD ON vs OFF : **identique**, 5/5 long jumps les deux
  côtés, Y COMPRIS la combo exacte de l'owner → la machine d'états du jeu fait le long jump
  parfaitement sur entrée manette propre. Le companion HD est innocenté.
- Device (Redmi, pad_replay) : des sauts ratent **aussi avec HD OFF** (stock) sur le même binaire →
  le toggle HD n'est pas la cause. MAIS les deux legs tournaient sur le MÊME binaire récent : ça
  n'innocente PAS le binaire. Signature des ratés : R1-en-courant atterrit pendant une vitesse de
  stick lue BASSE → `can-wheel?` (gaté sur la vitesse du stick) refuse → duck-walk + saut plain.

## PISTES (dans l'ordre)
1. **BISECT** : trouver QUAND ça a cassé. Candidats récents qui touchent l'overlay/l'input tactile :
   la refonte menu (Grecharged-menu-overhaul — zones tactiles, CAM pill, boutons redessinés), le
   drone/menu V4, dyn-rs (pacing variable → échantillonnage du stick ?). Construis 2-3 APK de
   commits antérieurs (avant la refonte menu p.ex.) et A/B la MÊME injection tactile.
2. **Injection TACTILE réelle** (pas cpad) : rejouer le geste de l'owner en événements touch
   (multi-touch : stick maintenu en course + tap R1 + tap X qui se chevauchent) — c'est le chemin
   overlay→pad merge qu'il faut exercer. Suspects concrets : le mapping des zones qui vole/relâche
   le doigt du stick quand R1 est touché (perte de la vitesse de stick), un ordre de traitement des
   touches modifié par la refonte menu, un seuil de vitesse affecté par le pacing.
3. Fix + preuve : la combo owner passe au tactile N fois de suite (trace d'états montrant
   target-wheel/wheel-flip), sur device eae4df44, AVANT/APRÈS clair. Zéro régression des autres
   gestes tactiles (roulade, punch, menu).

## Règles
- C'est de l'INPUT/OVERLAY, pas du HD : ne touche pas aux companions/merc.
- Preuve par injection touch + traces d'états (pas d'œil agent) ; l'owner confirme au tactile réel.
- L'owner est à distance : build final → jak-builds jak1-rtlight-wip.
