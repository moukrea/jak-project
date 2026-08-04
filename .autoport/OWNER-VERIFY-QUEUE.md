# OWNER VERIFY QUEUE — à tester au réveil (2026-08-04)
# Protocole nuit (owner ~01:55) : le framework avance en continu ; le superviseur fait une PRÉ-GATE
# humaine (vérifie ce qu'il peut : device, logs, captures grossières) et pose le token owner-ok pour
# ne pas bloquer la chaîne. TA vérification reste le verdict FINAL — tout item pré-gaté ici doit être
# re-testé par ton œil ; on rouvre ce qui ne te va pas.

## Légende
- [PRÉ-GATÉ ✅/⚠️] = passé par la pré-gate superviseur (✅ = confiant, ⚠️ = réserves notées)
- [EN COURS] = le framework bosse encore dessus
- [À TESTER] = prêt pour ton verdict

## 1. Menu overhaul (parké AVANT la nuit — rappel, rien de nouveau)
- [À TESTER, déjà connu] Structure 5 catégories OK (tu l'avais acceptée) ; esthétique holo/drone
  PARKÉE à ta demande (dégradé violacé plein écran ≠ holo bleuté gauche + drone). On y revient après HD.

## 2. HD Jak (Grecharged-hd-models3) — [EN COURS, cycle défauts]
### PRÉ-GATE 03:20 [⚠️ faux vert intercepté — cycle défauts CONTINUE]
- Le validator a re-passé à 02:59 MAIS sur le rapport d'AVANT la réouverture (aucune preuve nouvelle) :
  faux vert intercepté par le superviseur. Validator DURCI (preuves plus récentes que le début de cycle
  + lignes de résolution explicites long-jump et fantôme-cinématique exigées). Phase rouverte, worker
  reparti (attempt 2/6). Le vrai travail du cycle (harnais A/B long-jump, analyse movie/ghost) était
  en cours mais pas fini — rien de perdu.
### PRÉ-GATE 02:20 [✅ base / ⚠️ défauts en cours]
- Vérifié par le superviseur : validator+close-gate PASSÉS (attempt 3) ; deploy_verify PASS sur le
  Honor (le device fait tourner le build frais, prouvé) ; capture de preuve du worker regardée :
  **Jak HD cohérent et texturé, visible en jeu** (cheveux blonds, tunique bleue, Daxter au dos),
  zéro crash. → La base M1 est réelle.
- Décision : PAS de token — phase ROUVERTE pour brûler TES 7 défauts (long jump + Jak fantôme en
  priorité, rédhibitoires). Le worker exécute son propre runbook défaut par défaut, preuves device.
- À TON RÉVEIL : re-tester les 7 points sur le DERNIER build du Honor (surtout long jump R1/R2+X,
  une cinématique avec PNJ, et les yeux/gap de près).
Jalon acquis : Jak HD VISIBLE + animé sur Honor. Ta liste de défauts (01:45) est le brief du worker :
  (7) long jump cassé [priorité 1] · (6) Jak fantôme figé dans les cinématiques où il ne doit pas
  être [priorité 1] · (1) yeux blancs sans pupilles · (2) gap bandeau/cheveux (2 hypothèses : cheveux
  trop hauts OU pièce manquante) · (5) PNJ qui clignotent en cinématique · (4) visage inanimé ·
  (3) clipping vêtements (bleu/blanc jambes, col/lanière).
À ton réveil : re-tester ces 7 points sur le DERNIER build (le tien datait d'avant plusieurs fixes).

## 3. Keira/Samos plus cursed (fix village1 stock) — [PRÉ-GATÉ ✅ mécaniquement]
La village1.fr3 cursed a été écrasée par la stock sur le Honor (vérifié par taille/bytes).
À ton réveil : un coup d'œil au village (Keira au chantier du zeppelin, Samos dans sa hutte) → normaux.

## 4. (sera rempli au fil de la nuit : HD-models4 Daxter/Keira/Samos si M1 passe, etc.)

---
(Le superviseur ajoute une entrée datée à chaque pré-gate avec : ce qui a été vérifié, comment,
les réserves, et EXACTEMENT quoi tester toi-même.)
