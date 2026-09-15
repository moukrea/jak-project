// DIRECTIVES v775512c234. Local synthetic tests only.
#define main readback_original_main
#include "test/test_ao_contact_readback.cpp"
#undef main
#include <fstream>
#include <sstream>
#include <algorithm>
#include <cmath>
std::string source(const std::string& path) {std::ifstream f(path); CHECK(f.good()); std::ostringstream s; s<<f.rdbuf(); return s.str();}
GLuint compile(GLenum type,const std::string& text) {GLuint id=glCreateShader(type);const char* p=text.c_str();glShaderSource(id,1,&p,nullptr);glCompileShader(id);GLint ok=0;glGetShaderiv(id,GL_COMPILE_STATUS,&ok);if(!ok){char log[16384];glGetShaderInfoLog(id,sizeof(log),nullptr,log);std::fprintf(stderr,"%s\n",log);}CHECK(ok);return id;}

#include <map>
std::vector<uint8_t> bytes(const std::string& path){std::ifstream f(path,std::ios::binary);CHECK(f.good());return std::vector<uint8_t>(std::istreambuf_iterator<char>(f),{});}
void save(const std::string& path,const void*p,size_t n){std::ofstream f(path,std::ios::binary);f.write((const char*)p,n);CHECK(f.good());}
int main(int argc,char** argv){ CHECK(argc==4);
  auto getDisplay = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
  CHECK(getDisplay);
  EGLDisplay d = getDisplay(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
  CHECK(d != EGL_NO_DISPLAY);
  CHECK(eglInitialize(d, nullptr, nullptr));
  CHECK(eglBindAPI(EGL_OPENGL_API));
  EGLint attrs[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
                    EGL_NONE};
  EGLConfig cfg;
  EGLint count;
  CHECK(eglChooseConfig(d, attrs, &cfg, 1, &count) && count == 1);
  EGLint ctxAttrs[] = {EGL_CONTEXT_MAJOR_VERSION_KHR, 4, EGL_CONTEXT_MINOR_VERSION_KHR, 1, EGL_CONTEXT_OPENGL_PROFILE_MASK_KHR, EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT_KHR, EGL_NONE};
  EGLContext c = eglCreateContext(d, cfg, EGL_NO_CONTEXT, ctxAttrs);
  CHECK(c != EGL_NO_CONTEXT);
  CHECK(eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c));
  std::printf("GL_VENDOR=%s\nGL_RENDERER=%s\nGL_VERSION=%s\n", glGetString(GL_VENDOR),
              glGetString(GL_RENDERER), glGetString(GL_VERSION));

  const std::string notes=".autoport/reports/ao-prepass-tie-alpha/notes/";
  const std::string archive=notes+"attempt10-01-ssao-before/ao-hut-archive-18920-1400/";
  std::map<std::string,float> m;std::istringstream manifest(source(archive+"manifest.txt"));std::string line;while(std::getline(manifest,line)){auto eq=line.find('=');if(eq==std::string::npos)continue;try{m[line.substr(0,eq)]=std::stof(line.substr(eq+1));}catch(...){}}
  const int X=800,Y=600;const size_t N=X*Y;
  auto depthbytes=bytes(archive+"prepass-depth.f32");CHECK(depthbytes.size()==N*4);
  std::vector<uint32_t> depth(N),flat(N);for(size_t k=0;k<N;++k){float d;std::memcpy(&d,&depthbytes[k*4],4);depth[k]=uint32_t(std::lround(double(d)*16777215.0))<<8;flat[k]=uint32_t(std::lround(.02*16777215.0))<<8;}
  GLuint dt,ao[2],fbo[2],ft[2],ff[2],vao,vbo;
  glGenTextures(1,&dt);glActiveTexture(GL_TEXTURE1);glBindTexture(GL_TEXTURE_2D,dt);glTexStorage2D(GL_TEXTURE_2D,1,GL_DEPTH24_STENCIL8,X,Y);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_COMPARE_MODE,GL_NONE);glTexSubImage2D(GL_TEXTURE_2D,0,0,0,X,Y,GL_DEPTH_STENCIL,GL_UNSIGNED_INT_24_8,depth.data());
  glActiveTexture(GL_TEXTURE0);glGenTextures(2,ao);glGenFramebuffers(2,fbo);glGenTextures(2,ft);glGenFramebuffers(2,ff);
  for(int typ=0;typ<2;++typ)for(int i=0;i<2;++i){glBindTexture(GL_TEXTURE_2D,typ?ft[i]:ao[i]);glTexStorage2D(GL_TEXTURE_2D,1,typ?GL_R32F:GL_R8,X,Y);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);glBindFramebuffer(GL_FRAMEBUFFER,typ?ff[i]:fbo[i]);glFramebufferTexture2D(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_TEXTURE_2D,typ?ft[i]:ao[i],0);CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE);}
  glGenVertexArrays(1,&vao);glBindVertexArray(vao);glGenBuffers(1,&vbo);glBindBuffer(GL_ARRAY_BUFFER,vbo);const float v[]={-1,-1,-1,1,1,-1,1,1};glBufferData(GL_ARRAY_BUFFER,sizeof(v),v,GL_STATIC_DRAW);glEnableVertexAttribArray(0);glVertexAttribPointer(0,2,GL_FLOAT,GL_FALSE,0,nullptr);glViewport(0,0,X,Y);glDisable(GL_BLEND);glDisable(GL_DEPTH_TEST);glDisable(GL_DITHER);
  GLuint programs[2];for(int candidate=0;candidate<2;++candidate){GLuint p=programs[candidate]=glCreateProgram();glAttachShader(p,compile(GL_VERTEX_SHADER,source(argv[1])));glAttachShader(p,compile(GL_FRAGMENT_SHADER,source(argv[candidate?3:2])));glLinkProgram(p);GLint ok;glGetProgramiv(p,GL_LINK_STATUS,&ok);CHECK(ok);glUseProgram(p);auto loc=[&](const char*n){return glGetUniformLocation(p,n);};float camera[16],inv[16];for(int j=0;j<16;++j){camera[j]=m["camera_"+std::to_string(j)];inv[j]=m["inverse_"+std::to_string(j)];}glUniformMatrix4fv(loc("u_camera"),1,GL_FALSE,camera);glUniformMatrix4fv(loc("u_inv_camera"),1,GL_FALSE,inv);glUniform4f(loc("u_hvdf_offset"),m["hvdf_0"],m["hvdf_1"],m["hvdf_2"],m["hvdf_3"]);glUniform4f(loc("u_cam_pos"),m["pos_0"],m["pos_1"],m["pos_2"],m["pos_3"]);glUniform1f(loc("u_fog"),m["fog"]);glUniform2f(loc("u_depth_size"),X,Y);glUniform2f(loc("u_ao_size"),X,Y);glUniform1i(loc("u_ao"),0);glUniform1i(loc("u_depth"),1);glUniform1i(loc("u_blur_report"),0);glUniform1f(loc("u_edge_reject"),1);}

  std::printf("desktop_shader_compile_link=pass gl_errors=%u\n", glGetError()); return 0;
}
