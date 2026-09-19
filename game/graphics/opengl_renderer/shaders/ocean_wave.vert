#version 410 core

// water-ocean-mesh (verdict C du 17/09, reprise du 19/09) — LA SONDE DE HOULE.
// Un triangle plein cadre, sans attribut. La cible est dimensionnee par l'hote, qui l'utilise a
// DEUX tailles : 61 x 61 au pas de l'anneau 0 (45 m autour de la camera, la fenetre du verdict C)
// et 121 x 121 au pas de 1,5 m (180 m, la fenetre qui compare le relief a 0-24 m et a 30-90 m).
// Ce fichier ne sait rien de ces tailles : il couvre la fenetre, quelle qu'elle soit.

void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
