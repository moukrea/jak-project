#pragma once
// GrassContactPrints.h — grass-interaction-direction : L'EMPREINTE DU CORPS, PAS UN POINT.
//
// POURQUOI CE FICHIER EXISTE. L'essai 3 a passe sa porte et l'owner l'a refuse (20/09) : « toujours
// tres fake et pas vraiment correle au mesh du personnage […] quand on saute l'herbe se releve et
// quand on atterrit ca passe d'un etat a l'autre instant sans transition […] quand on spin ou punch
// en avant […] ca prend pas en compte le mesh de Jak (ou ses collisions) ». La cause est de
// CADRAGE : la source du couchage etait `u_jak_pos` + un cap — UN POINT ET UN VECTEUR. Un point n'a
// pas de bras, pas de roue, pas de pieds ; il ne peut ni sauter ni frapper.
//
// LA SOURCE EST MAINTENANT L'ENSEMBLE DES SPHERES DE COLLISION DE JAK, telles que le jeu les tient
// deja (`collide-shape-prim::prim-core::world-sphere`, plus les trois spheres d'attaque du spin et
// du punch quand `collide-as` porte `target-attack`). Chaque sphere est projetee au sol :
//
//     rayon d'empreinte = sqrt(r^2 - h^2),   h = hauteur du centre au-dessus du brin
//
// C'est la trace EXACTE du volume au niveau du sol. Cette seule formule repond a DEUX des plaintes
// de l'owner d'un coup, et sans aucun etat binaire :
//   - le saut : en montant, h croit, l'empreinte se referme CONTINUMENT jusqu'a disparaitre a h=r ;
//     l'atterrissage la rouvre de la meme facon. L'ancienne bande d'altitude etait une coupure.
//   - le corps : un pied pose donne un petit disque, le tronc n'en donne aucun tant qu'il est haut,
//     la roue du spin en donne une couronne, le bras du punch un lobe DEVANT. Rien n'est scripte :
//     c'est la geometrie des volumes que le jeu utilise deja pour ses collisions.
//
// LE RESSORT. Une empreinte ne disparait pas quand la sphere s'en va : elle est STAMPEE dans un
// vivier (`Pool`) et relachee par un oscillateur amorti (zeta = 0,7), temps de retour a 5 % =
// RETURN_S. Jamais un etat binaire, jamais un fondu lineaire : la meme loi pour le decollage, pour
// l'atterrissage et pour la marche.
//
// CE FICHIER EST COMPILE DEUX FOIS, ET C'EST LE POINT. `GrassRenderer.cpp` le fait tourner sur
// l'appareil ; `GrassBakeCore.cpp` le fait tourner hors ligne sur un mannequin scripte (marche,
// saut, spin, punch) pour publier les grandeurs de la porte. La porte ne mesure donc pas un miroir
// de la loi : elle mesure LA loi. Un recalcul separe serait exactement la faute que l'essai 3 a
// commise ailleurs. Il ne doit dependre ni d'OpenGL ni de GOAL : le binaire `grass_bake` est
// GL-free.
#include <array>
#include <cmath>
#include <cstdint>

namespace grass_prints {

constexpr float GP_U = 4096.f;  // unites de jeu par metre

// ---- BORNES DU CANAL. Elles ne sont pas decoratives : le groupe de primitives de Jak est lu
// depuis GOAL par un `dotimes` sur `num-prims`, et un `root-prim` qui ne serait pas un groupe
// rendrait des positions arbitraires. Le refus se fait ICI, AU POINT DE PRODUCTION, jamais au
// point de controle.
constexpr int SPH_MAX = 12;           // spheres acceptees par image
constexpr float SPH_R_MIN = 0.10f * GP_U;   // sous ce rayon, ce n'est pas un volume de corps
constexpr float SPH_R_MAX = 2.50f * GP_U;   // au-dessus, c'est une lecture hors-groupe
constexpr float SPH_REACH = 4.00f * GP_U;   // distance max au centre de Jak

// ---- L'EMPREINTE
// GAIN 1,0 : L'EMPREINTE EST LA GEOMETRIE, SANS MARGE INVENTEE.
// Il a valu 1,35 — « l'empreinte visible deborde un peu du volume » — et c'etait un choix
// d'apparence, pas une mesure. La porte l'a chiffre : a gain 1,35, QUARANTE-CINQ POUR CENT de
// l'aire ou l'une des deux cartes est non nulle est l'anneau compris entre l'empreinte vraie et
// l'empreinte dilatee, ou la reference vaut zero PAR CONSTRUCTION. C'etait l'essentiel des 0,22
// de correlation manquants. Or la plainte de l'owner porte precisement sur la fidelite au corps :
// elargir l'empreinte pour « qu'on la voie mieux » est exactement ce qui faisait « fake ».
// L'herbe se couche donc sous le volume, et nulle part ailleurs.
constexpr float PRINT_GAIN = 1.00f;
// ... et le plancher descend avec lui : a 0,26 m il coupait net l'empreinte d'un pied a mi-pas
// (0,236 m a 15 cm du sol), ce qui reintroduisait un etat binaire au milieu du cycle de marche.
// A 0,12 m la fermeture de l'empreinte reste continue jusqu'au bout.
constexpr float PRINT_R_MIN = 0.12f * GP_U;
constexpr float PRINT_R_MAX = 2.20f * GP_U;
constexpr float PRINT_MERGE = 0.40f * GP_U;  // une sphere rafraichit une empreinte a moins de 40 cm
constexpr float PRINT_LIFE_S = 1.60f;        // au-dela le ressort est rendu, l'empreinte meurt
// DIX PLACES, ET C'EST UNE MESURE QUI L'A FIXE. A huit, la porte hors ligne a rendu une variation
// image a image de 0,294 pour un plafond contractuel de 0,30 : Jak marchant a 3 m/s depose plus
// d'empreintes en 0,9 s de ressort que le vivier n'a de places, et chaque eviction faisait
// disparaitre d'un coup une empreinte encore visible. Ce n'est pas le plafond qui etait trop
// serre, c'est le vivier qui debordait. Dix places et un rayon de fusion a 40 cm suppriment la
// cause ; le cout est deux etapes de plus dans le deroulage LITTERAL du shader. Cette constante
// et la taille des tableaux `u_jak_print`/`u_jak_printv` du shader DOIVENT rester d'accord.
constexpr int PRINT_MAX = 10;                // deroulage a index LITTERAL cote shader

// ---- LE RESSORT AMORTI. zeta = 0,7 : un seul depassement, ~4,6 %, et un retour a 5 % en
// RETURN_S. Le contrat exige ce temps dans [0,6 ; 1,2] s ; il est DECLARE ici et MESURE par la
// porte sur la meme fonction, jamais recopie dans le juge.
constexpr float RETURN_S = 0.90f;
constexpr float SPRING_A = 3.0f / RETURN_S;               // zeta*omega : exp(-A t) = 5 % a t=RETURN_S
constexpr float SPRING_WD = SPRING_A * 1.0200f;           // omega_d pour zeta = 0,7

// ---- LA VITESSE QUI ORIENTE. Memes bornes que le cap de l'essai 3 (publiees en milli par le
// moteur : spd_lo=800, spd_hi=4000) : la continuite de reglage est voulue.
constexpr float SPD_LO = 0.80f * GP_U;   // m/s * U : sous ce seuil, poussee purement radiale
constexpr float SPD_HI = 4.00f * GP_U;   // au-dela, orientation pleine
constexpr float IMPACT_VY = 2.50f * GP_U;  // descente au-dela de laquelle l'appui est un IMPACT
constexpr float IMPACT_GAIN = 1.30f;       // l'impact ouvre un disque plus large, puis il rend

// Genres, tels que GOAL les publie. Le genre ne change PAS la loi : il sert a apparier une sphere
// avec son empreinte (un pied ne rafraichit pas l'empreinte d'un bras) et a recenser.
enum Kind : int { KIND_BODY = 0, KIND_LIMB = 1, KIND_ATTACK = 2 };

// LES VOLUMES D'ATTAQUE NE TOUCHENT PAS LE SOL, ET POURTANT ILS COUCHENT L'HERBE.
// La roue d'un spin et le bras d'un punch balaient a hauteur de hanche : leur sphere ne coupe
// jamais le plan du sol, donc `sqrt(r^2 - h^2)` rendrait ZERO et l'owner ne verrait ni la
// couronne ni le lobe — precisement les deux formes qu'il a nommees (« un spin couche l'herbe en
// couronne autour de lui, un coup de poing en avant la couche devant le bras »). Ce qu'un joueur
// voit la n'est pas un appui, c'est le SOUFFLE du balayage. On donne donc aux volumes d'attaque
// une portee verticale supplementaire — DECLAREE, publiee, et appliquee des DEUX cotes de la
// porte — au lieu de mentir sur la geometrie des spheres ou de coder la couronne a la main.
constexpr float ATTACK_REACH = 0.80f * GP_U;
inline float kind_reach(int kind) {
  return kind == KIND_ATTACK ? ATTACK_REACH : 0.f;
}

struct Sphere {
  float x = 0.f, y = 0.f, z = 0.f;  // centre MONDE
  float r = 0.f;                    // rayon MONDE
  int kind = KIND_BODY;
  int slot = -1;  // rang stable dans la publication GOAL : c'est lui qui apparie les images
};

struct Print {
  bool live = false;
  int kind = KIND_BODY;
  int slot = -1;
  float x = 0.f, y = 0.f, z = 0.f;  // position au SOL de l'empreinte
  float r = 0.f;                    // rayon d'empreinte retenu (le MAX vu pendant sa vie)
  float dx = 1.f, dz = 0.f;         // direction de poussee, XZ unitaire
  float speed = 0.f;                // 0 = repli radial, 1 = orientation pleine
  float peak = 1.f;                 // amplitude a la derniere stampe (impact = plus fort)
  double t_stamp = 0.0;             // instant de la derniere stampe : l'age du ressort
};

// L'EMPREINTE AU SOL D'UNE SPHERE. `dh` = hauteur du centre au-dessus du plan du sol considere.
// Hors du volume, zero — et zero veut dire zero, pas « un petit peu ».
inline float footprint_radius(float r, float dh) {
  const float a = dh < 0.f ? -dh : dh;
  if (a >= r) {
    return 0.f;
  }
  return std::sqrt(r * r - a * a);
}

// LE RESSORT, a l'age `age` secondes depuis la stampe. 1 au contact, descend en oscillant une
// seule fois sous zero (~-4,6 %) et rend a ~5 % en RETURN_S.
inline float spring(float age) {
  if (age <= 0.f) {
    return 1.f;
  }
  const float e = std::exp(-SPRING_A * age);
  const float w = SPRING_WD * age;
  return e * (std::cos(w) + (SPRING_A / SPRING_WD) * std::sin(w));
}

// La force que le shader recoit : le ressort, plancher a zero (un depassement negatif redresse le
// brin, il ne le couche pas a l'envers).
inline float spring_str(float age, float peak) {
  const float s = spring(age);
  return s <= 0.f ? 0.f : s * peak;
}

// Le poids d'orientation d'une vitesse XZ : 0 sous SPD_LO (repli radial EXACT), 1 au-dela de
// SPD_HI. C'est le `gcd_speed` de `grass_contact_dir.glsl`.
inline float speed_weight(float vx, float vz) {
  const float sp = std::sqrt(vx * vx + vz * vz);
  if (sp <= SPD_LO) {
    return 0.f;
  }
  if (sp >= SPD_HI) {
    return 1.f;
  }
  return (sp - SPD_LO) / (SPD_HI - SPD_LO);
}

// Ce que le vivier a fait pendant UNE image. Publie tel quel par le moteur et par l'outil : aucune
// de ces grandeurs n'est derivee ailleurs.
struct StepStats {
  int spheres_in = 0;
  int spheres_rejected = 0;
  int spheres_grounded = 0;  // celles dont l'empreinte au sol est non vide
  int stamped = 0;           // empreintes rafraichies ou creees
  int created = 0;
  int impacts = 0;
  int live = 0;
  int kind_mask = 0;
};

// LE VIVIER. Il porte tout l'etat temporel du couchage. Une image = un `step`.
struct Pool {
  std::array<Print, PRINT_MAX> prints{};
  std::array<Sphere, SPH_MAX> prev{};
  int prev_n = 0;
  double t_prev = -1.0;

  void reset() {
    for (auto& p : prints) {
      p = Print();
    }
    prev_n = 0;
    t_prev = -1.0;
  }

  // Retrouve la sphere du meme rang a l'image precedente : c'est elle qui donne la VITESSE. Un
  // rang absent (volume d'attaque qui vient de s'armer) n'a pas de vitesse : il est radial, ce qui
  // est le comportement juste pour un volume qui apparait.
  const Sphere* match_prev(const Sphere& s) const {
    for (int i = 0; i < prev_n; ++i) {
      if (prev[i].slot == s.slot && prev[i].kind == s.kind) {
        return &prev[i];
      }
    }
    return nullptr;
  }

  // `ground_y` : l'altitude du sol sous Jak (sa racine). `sph`/`n` : les spheres de CETTE image,
  // deja filtrees par `accept()`.
  StepStats step(double tnow, const Sphere* sph, int n, float ground_y) {
    StepStats st;
    const float dt = (t_prev < 0.0) ? 0.f : (float)(tnow - t_prev);
    const float inv_dt = (dt > 1.0e-4f && dt < 0.25f) ? (1.f / dt) : 0.f;

    // --- 1. les empreintes trop vieilles meurent : leur ressort est rendu.
    for (auto& p : prints) {
      if (p.live && (float)(tnow - p.t_stamp) > PRINT_LIFE_S) {
        p.live = false;
      }
    }

    // --- 2. chaque sphere au sol stampe son empreinte.
    for (int i = 0; i < n && i < SPH_MAX; ++i) {
      const Sphere& s = sph[i];
      st.spheres_in++;
      st.kind_mask |= (1 << s.kind);
      const float fr_raw = footprint_radius(s.r + kind_reach(s.kind), s.y - ground_y);
      if (fr_raw <= 0.f) {
        continue;  // le volume ne touche pas le sol : RIEN, et c'est continu
      }
      float fr = fr_raw * PRINT_GAIN;
      if (fr < PRINT_R_MIN) {
        continue;
      }
      st.spheres_grounded++;

      float vx = 0.f, vy = 0.f, vz = 0.f;
      if (const Sphere* q = match_prev(s)) {
        vx = (s.x - q->x) * inv_dt;
        vy = (s.y - q->y) * inv_dt;
        vz = (s.z - q->z) * inv_dt;
      }
      const bool impact = (vy < -IMPACT_VY);
      if (impact) {
        fr *= IMPACT_GAIN;
        st.impacts++;
      }
      if (fr > PRINT_R_MAX) {
        fr = PRINT_R_MAX;
      }

      const float w = speed_weight(vx, vz);
      float dx = vx, dz = vz;
      const float vl = std::sqrt(dx * dx + dz * dz);
      if (vl > 1.0e-3f) {
        dx /= vl;
        dz /= vl;
      } else {
        dx = 1.f;
        dz = 0.f;
      }

      // Appariement : la MEME sphere (rang + genre) proche de son empreinte la rafraichit. Sinon
      // elle en cree une neuve — c'est ce qui fait la COURONNE du spin : le volume d'attaque
      // balaie, chaque nouvelle position depose sa propre empreinte, et les precedentes rendent.
      Print* hit = nullptr;
      for (auto& p : prints) {
        if (!p.live || p.slot != s.slot || p.kind != s.kind) {
          continue;
        }
        const float ddx = p.x - s.x, ddz = p.z - s.z;
        if (ddx * ddx + ddz * ddz < PRINT_MERGE * PRINT_MERGE) {
          hit = &p;
          break;
        }
      }
      if (!hit) {
        // la plus vieille place, vivante ou non : le vivier est FIXE et son echec doit etre
        // impossible, pas silencieux (une place manquante rendrait un contact MUET).
        Print* oldest = &prints[0];
        for (auto& p : prints) {
          if (!p.live) {
            oldest = &p;
            break;
          }
          if (p.t_stamp < oldest->t_stamp) {
            oldest = &p;
          }
        }
        hit = oldest;
        *hit = Print();
        hit->r = 0.f;
        st.created++;
      }
      hit->live = true;
      hit->kind = s.kind;
      hit->slot = s.slot;
      hit->x = s.x;
      hit->y = ground_y;
      hit->z = s.z;
      hit->r = fr > hit->r ? fr : hit->r;  // le MAX vu : le decollage ne retrecit pas l'empreinte
      hit->dx = dx;
      hit->dz = dz;
      hit->speed = w;
      hit->peak = impact ? 1.f : (0.85f + 0.15f * w);
      hit->t_stamp = tnow;
      st.stamped++;
    }

    for (const auto& p : prints) {
      if (p.live) {
        st.live++;
      }
    }

    prev_n = n < SPH_MAX ? n : SPH_MAX;
    for (int i = 0; i < prev_n; ++i) {
      prev[i] = sph[i];
    }
    t_prev = tnow;
    return st;
  }

  // Les deux tableaux d'uniformes, remplis dans l'ordre des places (stable d'une image a l'autre,
  // donc aucun scintillement) :
  //   a[i] = (x, y, z, rayon d'empreinte)
  //   b[i] = (dir.x, dir.z, force du ressort, poids d'orientation)
  // Une place morte rend force = 0 : le shader la saute sans branchement a index calcule.
  void fill_uniforms(double tnow, float* a, float* b) const {
    for (int i = 0; i < PRINT_MAX; ++i) {
      const Print& p = prints[i];
      const float str = p.live ? spring_str((float)(tnow - p.t_stamp), p.peak) : 0.f;
      a[i * 4 + 0] = p.x;
      a[i * 4 + 1] = p.y;
      a[i * 4 + 2] = p.z;
      a[i * 4 + 3] = str > 0.f ? p.r : 0.f;
      b[i * 4 + 0] = p.dx;
      b[i * 4 + 1] = p.dz;
      b[i * 4 + 2] = str;
      b[i * 4 + 3] = p.speed;
    }
  }
};

// LE FILTRE D'ENTREE, au POINT DE PRODUCTION. GOAL publie ce que le groupe de primitives contient ;
// si le `root-prim` de Jak n'etait pas un groupe, `num-prims` et `prims` rendraient des ordures, et
// l'herbe se coucherait au hasard a l'autre bout du niveau. Une sphere qui ne tient pas dans ces
// bornes n'est pas corrigee, elle est REFUSEE et comptee.
inline bool accept(const Sphere& s, float jx, float jy, float jz) {
  if (!(s.r > SPH_R_MIN) || !(s.r < SPH_R_MAX)) {
    return false;
  }
  const float dx = s.x - jx, dy = s.y - jy, dz = s.z - jz;
  if (dx * dx + dy * dy + dz * dz > SPH_REACH * SPH_REACH) {
    return false;
  }
  // NaN / infini : un `!(a < b)` les attrape la ou `a >= b` les laisse passer.
  if (!(s.x == s.x) || !(s.y == s.y) || !(s.z == s.z)) {
    return false;
  }
  return true;
}

}  // namespace grass_prints
