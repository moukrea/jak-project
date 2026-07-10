Build de PLAYTEST jak1 — herbe 3D "Recharged" (default ON) sur le niveau d'entraînement (Rocher du Geyser).

**ITÉRATION POLISH — vérifiée sur device (A/B objectif OFF↔ON sur ta Redmi)** :
- **Densité ×beaucoup** (ton ask n°1) : ~179 000 brins, dont ~13 000 à moins de 8 m de Jak (avant : 731 dans toute la bande). Densité graduée : très dense près de toi, plus léger au loin.
- **Jak est maintenant DANS la vraie herbe 3D** : la bande LOD des brins a été repoussée (Jak à 10,8 m de la caméra = en plein dedans, avant il était dans les cards).
- **Grass cards = touffes, plus des rectangles flous** : la card est découpée en vraies lames (alpha-cut) au lieu d'un rectangle plat.
- **Les cards ondulent au vent** comme les brins 3D (rafale partagée, plus douce).
- **Fix du bug n°1 (systémique) de chunks vides / désinstanciation** : c'était le budget d'instances (cap) consommé dans l'ordre de dessin → des chunks proches se retrouvaient sans herbe et ça bougeait à chaque rebuild. Corrigé à la racine : placement du plus proche au plus loin + cap au-dessus du total réel → aucun chunk proche n'est jamais privé d'herbe (couverture mesurée stable à 0,768 pendant toute la marche, zéro trou).
- Plus de variation de teinte / taille / courbure par brin.

**Perf (honnête)** : dense = ça travaille l'Adreno 618 → ~31 fps avec le dynamic-render-scale à son plancher (40 %). C'est le coût de la densité que tu voulais ; c'est réglable en une constante si tu trouves ça trop lourd — dis-moi.

Toggle : Graphics Options > Recharged Settings > **RECHARGED GRASS** (OFF = rendu stock, identique à l'original). Default **ON**. APK autonome, base jak1 v9.

Dis-moi ce que tu vois : densité OK ? Jak bien dans les brins ? cards crédibles ? plus de carrés vides ?
