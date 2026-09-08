#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <array>
#include <cmath>
#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>
using V = std::array<float, 4>;
int failures = 0;
void check(bool ok, const char* name) {
  if (!ok) { ++failures; std::cout << "FAIL " << name << '\n'; }
}
GLuint shader(GLenum type, std::string s) {
  GLuint sh = glCreateShader(type); const char* p = s.c_str();
  glShaderSource(sh, 1, &p, nullptr); glCompileShader(sh);
  GLint ok; glGetShaderiv(sh, GL_COMPILE_STATUS, &ok);
  if (!ok) { char log[8192]; glGetShaderInfoLog(sh, sizeof log, nullptr, log); std::cerr << log; exit(3); }
  return sh;
}
GLuint program(const char* path) {
  std::ifstream file(path); std::stringstream ss; ss << file.rdbuf(); auto source = ss.str();
  if (source.empty()) exit(2);
  source.replace(0, source.find('\n'), "#version 320 es\nprecision highp float; precision highp int;");
  GLuint p = glCreateProgram();
  glAttachShader(p, shader(GL_VERTEX_SHADER, "#version 320 es\nprecision highp float; out vec2 tex_coord; void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.-1.,0,1);tex_coord=vec2(.5);}"));
  glAttachShader(p, shader(GL_FRAGMENT_SHADER, source)); glLinkProgram(p);
  GLint ok; glGetProgramiv(p, GL_LINK_STATUS, &ok); if (!ok) exit(4);
  return p;
}
GLuint texture;
V draw(GLuint p, V input, int mode, float knee) {
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, 1, 1, 0, GL_RGBA, GL_FLOAT, input.data());
  glUseProgram(p); glUniform1i(glGetUniformLocation(p,"tex_T0"),0);
  glUniform1f(glGetUniformLocation(p,"u_hdr_exposure"),1);
  glUniform1f(glGetUniformLocation(p,"u_hdr_knee"),knee);
  glUniform1i(glGetUniformLocation(p,"u_hdr_curve"),mode);
  glDrawArrays(GL_TRIANGLES,0,3); V result;
  glReadPixels(0,0,1,1,GL_RGBA,GL_FLOAT,result.data());
  check(glGetError()==GL_NO_ERROR,"GL error"); return result;
}
void print(const char* label, V v) {
  std::cout << label << '=' << v[0] << ',' << v[1] << ',' << v[2] << ',' << v[3] << ' ';
}
int main(int argc, char** argv) {
  if(argc!=3) return 2;
  auto get = (PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");
  auto d = get(EGL_PLATFORM_SURFACELESS_MESA,EGL_DEFAULT_DISPLAY,nullptr);
  EGLint major,minor; if(!eglInitialize(d,&major,&minor)) return 5;
  eglBindAPI(EGL_OPENGL_ES_API);
  EGLint attr[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_NONE};
  EGLConfig cfg; EGLint n; eglChooseConfig(d,attr,&cfg,1,&n);
  EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE}; auto ctx=eglCreateContext(d,cfg,EGL_NO_CONTEXT,ca);
  if(!eglMakeCurrent(d,EGL_NO_SURFACE,EGL_NO_SURFACE,ctx)) return 6;
  std::cout << "renderer=" << glGetString(GL_RENDERER) << " version=" << glGetString(GL_VERSION) << '\n';
  GLuint p[]={program(argv[1]),program(argv[2])};
  GLuint vao,fb,rb; glGenVertexArrays(1,&vao);glBindVertexArray(vao);
  glGenFramebuffers(1,&fb);glBindFramebuffer(GL_FRAMEBUFFER,fb);
  glGenRenderbuffers(1,&rb);glBindRenderbuffer(GL_RENDERBUFFER,rb);
  glRenderbufferStorage(GL_RENDERBUFFER,GL_RGBA32F,1,1);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,rb);
  check(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"framebuffer");
  glGenTextures(1,&texture);glBindTexture(GL_TEXTURE_2D,texture);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glViewport(0,0,1,1);
  for(V input : std::vector<V>{{2,1,2,.5},{.2,.1,2,.5},{2,1,.1,.5},{1,1,1,.5},{8,2,8,1}}) {
    auto a=draw(p[0],input,0,.95);auto b=draw(p[1],input,0,.95);
    print("input",input);print("before",a);print("after",b);std::cout << '\n';
  }
  // Exercise the actual new shader across both joins, not a copied curve formula.
  float prev = 0, prev_slope = 0, max_jump = 0;
  for (int i = 0; i <= 8000; ++i) {
    float x = i * .001f;
    auto value = draw(p[1], V{x,x,x,.375f}, 0, .95f);
    check(value[0] >= prev - 1e-6f, "monotone GPU curve");
    check(value[0] <= 1 && value[0] >= 0, "bounded GPU curve");
    float slope = (value[0]-prev)/.001f;
    if (i > 1) max_jump = std::max(max_jump, std::abs(slope-prev_slope));
    prev = value[0]; prev_slope = slope;
  }
  check(max_jump <= .05f, "continuous GPU slope");
  std::cout << "curve_samples=8001 max_slope_jump=" << max_jump << '\n';
  int samples=0;
  for(float knee : {.8f,.95f,.99f}) for(float value : {0.f,.1f,.5f,.8f,.95f,1.f,2.f,8.f,32.f}) {
    V gray={value,value,value,.375}; auto a=draw(p[0],gray,0,knee), b=draw(p[1],gray,0,knee);
    if (value <= knee) for(int c=0;c<4;++c) check(std::abs(a[c]-b[c])<1e-6,"below knee unchanged");
    V input={value,.25,2,.375}; a=draw(p[0],input,1,knee);b=draw(p[1],input,1,knee);
    for(int c=0;c<4;++c) check(std::abs(a[c]-b[c])<1e-6,"Filmique unchanged");
    b=draw(p[1],input,0,knee);
    check(b[1]==input[1],"low channel preserved despite bright neighbor");
    check(b[3]==input[3],"alpha unchanged");
    for(int c=0;c<3;++c) check(b[c]>=0 && b[c]<=1 && b[c]<=input[c]+1e-6,"bounded no brightening");
    auto more=input;more[2]=32;auto m=draw(p[1],more,0,knee);
    check(m[0]==b[0] && m[1]==b[1],"channel independence"); ++samples;
  }
  std::cout << "samples=" << samples << " failures=" << failures << '\n';
  return failures?1:0;
}
