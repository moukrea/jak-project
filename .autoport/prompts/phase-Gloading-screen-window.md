# Gloading-screen-window — l'ecran doit ENCADRER la transition, et le texte fait moitie

Retour owner 2026-08-30, mot pour mot, dans
`.autoport/reports/Gloading-screen/owner-defects-round4.txt`. Lis-le en entier.

## ACQUIS — a ne pas casser
« L'animation est parfaite par contre, beau boulot. » La silhouette, sa cadence et son sens
sont VALIDES. Tout lot qui les touche republie la preuve qu'ils sont inchanges.

## Trois familles, dans cet ordre

### A. La fenetre est DECALEE (D3, D4, D7) — c'est le gros morceau
L'ecran s'ouvre APRES que la scene entrante a commence a se dessiner (l'owner voit
l'interieur de la hutte du Sage Vert, en qualite degradee, AVANT l'ecran) et se ferme AVANT
que la scene soit complete (pop-in a Geyser Rock). Cible : l'ecran couvre depuis AVANT le
dernier dessin de la scene sortante jusqu'a APRES le dernier element entrant.
Mesure exigee : horodater, sur la meme trace, le premier dessin de la scene entrante, la
pose de l'ecran, la levee de l'ecran, et le dernier element entrant devenu dessinable.
Les deux ecarts signes doivent etre >= 0 apres correction, sur les DEUX transitions que
l'owner nomme (chargement de sauvegarde a Geyser Rock ; teleporteur vers la Hutte du Sage
Vert). ATTENTION : « dessinable » n'est pas la residence GPU ni 'loaded — c'est 'active
(voir PITFALLS, la phase Gbeach-actors-gate a deja paye cette confusion).

### B. Les a-coups (D1, D5)
L'animation bafouille pendant les gros chargements et pendant le declenchement de la
cinematique. PITFALLS : « la barriere qui AFFICHE l'ecran le FIGE » — une barriere armee
met le renderer sur update_blocking SANS budget et parque le thread GOAL (3 768 ms mesures
entre deux images). Mesurer l'ecart entre images PENDANT l'ecran de chargement, publier le
pire ecart avant/apres, et viser un plafond tenu sur les deux transitions nommees.

### C. Cosmetique, independant (D2, D6) — livrer meme si A et B patinent
- Texte « Chargement... » et glyphes precurseurs : MOITIE moins gros (facteur cible 0,5),
  places plus BAS et plus a DROITE. Publier les tailles et positions avant/apres en
  fraction de la hauteur et de la largeur d'ecran.
- Le texte est en degrade gris : le passer en BLANC PLEIN. Verifier la couleur reellement
  soumise au rendu, pas la constante ecrite dans la source (PITFALLS : un canal se prouve
  par ce qu'il DEPOSE, pas par ce qu'on lit dans le code).

## Preuve
x86 au clavier pour C et pour les mesures de fenetre reproductibles ; appareil quand il est
libre, jamais comme prerequis bloquant. L'appareil de preuve est le Redmi eae4df44.
La Shield est la TV de l'owner : INTERDITE dans cette phase.

## Format des marqueurs (le validateur les LIT)
Dans `.autoport/reports/Gloading-screen-window/report.txt` :

    RESULT: LOADING WINDOW BRACKETED
    LSWIN transition=<save-geyser|teleport-sagehut> t_up=<ms> t_first_draw_in=<ms> t_last_active=<ms> t_down=<ms>
    LSFRAME transition=<...> worst_gap_before=<ms> worst_gap_after=<ms>
    LSTEXT scale_before=<f> scale_after=<f> xfrac_before=<f> xfrac_after=<f> yfrac_before=<f> yfrac_after=<f>
    LSCOLOR submitted=<RRGGBB> gradient=<0|1>
    LSANIM frames=<n> dir=<right|left> fps=<f> unchanged=<0|1>

Verifie mecaniquement :
- LSWIN present pour LES DEUX transitions nommees par l'owner ;
- t_up <= t_first_draw_in (l'ecran est pose AVANT que la scene entrante se dessine) ;
- t_down >= t_last_active (il se leve APRES le dernier element devenu 'active) ;
- LSFRAME : worst_gap_after < worst_gap_before, et worst_gap_after <= 100 ms ;
- LSTEXT : scale_after/scale_before dans [0,45 ; 0,55] (« moitie moins gros »),
  yfrac_after > yfrac_before (plus bas) et xfrac_after > xfrac_before (plus a droite) ;
- LSCOLOR : submitted == FFFFFF et gradient == 0 ;
- LSANIM : unchanged == 1 — l'animation est VALIDEE par l'owner, la casser est un echec.
