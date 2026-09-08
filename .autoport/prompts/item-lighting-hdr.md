# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Le contraste c'est normal non qu'il soit différent,.si on a plus de détails dans les ombres et lumières... Faut juste plus que ce soit brûlé avec par example le ciel blanc..  enfin a toi de me dire »
- 2026-09-08 : « Faut trouver l'équilibre, et n'oublie pas les autres niveaux j'ai l'impression que tu retombes dans tes travers »

## Cause connue
Essais16-18 : trois verdicts rouges de couverture224/processus ; campagne owner refusee par DIRECTIVES. Perimetre corrige : proof_plan et SCOPE-lighting-hdr, integration lots autorisee. Ne pas repeter essai17 inchangé.

## Livrable
Reprendre calibration HDR/SDR selon SPEC §4.5 et proof_plan du backlog. D abord IMPLEMENTER cumul par lots dans les fichiers autorises du SCOPE, tests negatifs inclus ; pas un nouveau rapport demandant arbitrage. Ensuite completer ciel swamp/sunkenb avec vues representatives alternatives, sans rejouer les200paires historiques par principe ni reparer parcours monolithique. Les anciennes captures ne prouvent pas automatiquement le build courant : etablir compatibilite rendu/config ou recapturer seulement ce qui est invalide. Couvrir21niveaux/8heures, ciel exterieur/interieurs/hutte ; aucun prerequis224paires dans un processus. Mesures ImageMagick ON/OFF eclairage seul, autres effets identiques. Equilibre niveau/heure, pires derives explicites ; iterer courbe/exposition puis residus locaux si mesures le justifient. Pas de recherche frame exacte. Couleur/luma/aplats/brulures, contraste95% diagnostic. LUT/profils SDR/HDR distincts permis, pas de compressionSDR reutilisee avant HDR natif. Cumul via proof_run/generic, couverture incomplete rouge. Conserver controles HDR>1/ordre, sans zero fabrique ; travail non prouve explicite. Ne pas clore sur audits seuls.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
