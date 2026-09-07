# Lecture ciblée ROI — essai33
DIRECTIVES v6fca51fe40
Researcher natif gpt-6-astra/high, lecture seule ; aucune cause démontrée par la lecture.
ROI initiale : lighting_census.cpp:333-337, [285,13,315,72], sans intersection delta neuf [77,110,105,143].
OG_REFSET_TRACE_ROI=1, au plus24captures ; wants_scene_probe lie la lecture au sample en vol.
Lecteur restaure bindings texture/renderbuffer/read-FBO/read-buffer, PACK et PBO ; aucun draw/uniforme changé.
Limites : glReadPixels synchrone ; pas de contrôle erreur GL ; FBO default/MSAA/certains attachements rejetés.
Apparier par capture,bucket,hash,first_index,texture,base/envmap,occurrence ; comparer hashes avant/après.
Un rgb_changed seul n’attribue pas le delta ; profondeur/poses absentes et timing synchrone non prouvé neutre.
Merc2 des arbres réels diffère seulement par hooks ROI ; merc2.vert,merc2.frag,generic.frag identiques.
Piste active : DirectRenderer.cpp:1033-1040 supprime mipmaps demandés master OFF ; baseline:1004-1007 les conserve.
Lien de cette piste avec bbox non prouvé ; aucun changement du filtrage autorisé sans attribution.
HDR fermé retourne RGBA8 (hdr.cpp:356-359) ; shade fermé conserve s.base (shade.glsl:199-200,758).
Port requis : ROI/API/includes/hooks uniquement ; renderer/shaders historiques séparés, aucun CMake nécessaire.

Revue delta final : aucune contradiction bloquante relevée en lecture.
Parsing strict borné, arrêt avant débordement entier ; invalid désactive diagnostic.
[77,110,105,143] => GL(77,36,29,34) à320x180 ; GL(192,90,73,85) à800x450.
Arrondi extérieur conservé ; à250% conversion bbox inverse peut relever x76, sans omission.
Blocs ROI cpp/h identiques ; Merc2 des deux arbres désormais identiques.
Hooks bucket HEAD1644/1722/1724 et baseline1566/1644/1646, mêmes positions logiques.
Aucun changement shaders/CMake/renderer hors lectures ; revue ne vaut pas preuve runtime.
