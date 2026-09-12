
#include <vector>

#include "common/dma/dma_chain_read.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/SkyBlendCommon.h"
#include "game/graphics/pipelines/opengl.h"

class SkyBlendGPU {
 public:
  SkyBlendGPU();
  ~SkyBlendGPU();
  void init_textures(TexturePool& tex_pool, GameVersion version);
  SkyBlendStats do_sky_blends(DmaFollower& dma,
                              SharedRenderState* render_state,
                              ScopedProfilerNode& prof);

 private:
  GLuint m_framebuffers[2];  // sky, clouds
  GLuint m_textures[2];      // sky, clouds
  int m_sizes[2] = {32, 64};
  GLuint m_gl_vertex_buffer;

  struct Vertex {
    float x = 0;
    float y = 0;
    float intensity = 0;
  };

  Vertex m_vertex_data[6];

  struct TexInfo {
    GpuTexture* tex;
    u32 tbp;
  } m_tex_info[2];

  // ===================== hdr-sky-gpu-alpha ============================================
  // `Target` est une cible de rendu de la taille d'un etage de ciel, dans le format que le
  // pilote a REELLEMENT accepte pour cet etage (`m_stage` ci-dessous). Trois familles :
  //   * `m_prev`     l'etat de la cible AVANT le tirage courant. Le melange GL est eteint et
  //                  l'addition se fait dans `sky_blend.frag` ; ce tampon est son operande.
  //                  Il fait partie de l'ETAT LIVRE : il existe toujours.
  //   * `m_witness`  la MEME accumulation, `alpha_limit` a l'infini : la valeur d'AVANT, tiree
  //                  dans la meme course, sur les memes couches. INSTRUMENT SEUL.
  //   * `m_witness_prev`  l'operande `prev` du temoin.
  struct Target {
    GLuint fbo = 0;
    GLuint tex = 0;
  };
  struct StageFmt {
    GLenum internal_fmt = 0;
    GLenum ext_fmt = 0;
    GLenum type = 0;
    bool is_float = false;
  };

  // Ce qu'une relecture de cible rend. `components` est le DENOMINATEUR : le nombre de
  // composantes alpha REELLEMENT relues. Un maximum sans lui ne se lit pas.
  struct AlphaScan {
    uint64_t components = 0;
    uint64_t alpha_over = 0;  // composantes alpha strictement au-dessus de 1,0
    float alpha_max = 0.f;
    float rgb_max = 0.f;
  };

  bool make_target(int idx, Target* out);
  void destroy_target(Target* t);
  // UNE accumulation : copier la cible dans son operande `prev`, puis la redessiner en ajoutant
  // la couche courante. C'est le geste que le melange a fonction fixe faisait avant.
  void accumulate(GLuint dst_fbo, const Target& prev, int size, GLint loc_limit, float limit);
  // LE CONTROLE SEME. Les couches du ciel se partagent 128 d'intensite : leur somme d'alpha ne
  // depasse jamais 1,0 dans le jeu, et une borne qu'aucune donnee ne touche est un vert par
  // INACTION. Ce controle empile huit fois la MEME couche a pleine intensite dans deux cibles
  // jetables — une bornee, une libre — et publie les deux maxima : le bras libre DOIT depasser
  // 1,0 (la population est atteignable), le bras borne DOIT rendre exactement 1,0 (la borne
  // borne). Il ne touche a aucune cible du jeu.
  void run_seed_control(SharedRenderState* render_state, GLuint src_tex);
  // Relit une cible (glReadPixels, GL_RGBA/GL_FLOAT) et FUSIONNE ce qu'elle contient dans `st`.
  void readback_into(const Target& t, int size, AlphaScan* st);

  StageFmt m_stage[2];
  Target m_prev[2];
  Target m_witness[2];
  Target m_witness_prev[2];
  Target m_seed[2];       // [0] bras borne, [1] bras libre
  Target m_seed_prev[2];  // leurs operandes `prev`
  uint64_t m_seed_clamped_x1000 = 0;
  uint64_t m_seed_free_x1000 = 0;
  bool m_witness_ready = false;
  bool m_witness_failed = false;
  int m_uniform_ok = -1;  // -1 jamais tente, 0 localisation absente, 1 les deux trouvees

  std::vector<float> m_readback;
  uint64_t m_calls = 0;
};