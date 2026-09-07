# Lecture ciblée après comparaison neuve
DIRECTIVES v6fca51fe40
Aucune cause identifiée ; lecture seule, aucune campagne complémentaire.
Merc2.cpp ne diffère que par roi_model/roi_before/roi_after (OFF sans OG_REFSET_TRACE_ROI=1).
merc2.vert, merc2.frag et generic.frag sont identiques entre arbres selon la comparaison researcher.
Shader.cpp ajoute recensement passif de source HDR et compilation TONEMAP ; pas de réécriture GLSL.
Les shaders monde passent maintenant par shade(), dont les branches fermées conservent s.base.
Aucune fuite d’uniforme démontrée ; master_active=0 ne relève pas les uniformes de chaque draw.
Les changements brise/contact ne sont pas investigués davantage : hors périmètre.
Instrument existant : OG_REFSET_TRACE_ROI=1 attribue un changement de framebuffer au draw/modèle.
Les hooks ROI Merc de HEAD ne sont pas dans le renderer historique, ne pas prétendre deux bras déjà instrumentés.
GJ2VIS_TFTREE/F1A_MERC_DUMP limitent leurs relevés aux premiers modèles/draws ; ne prouvent pas LF2282.
Aucun état privé/pose articulée complet au sample n’a été trouvé dans les instruments existants.
