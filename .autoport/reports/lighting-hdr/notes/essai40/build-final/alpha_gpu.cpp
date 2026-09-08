#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl32.h>
#include <fstream>
#include <sstream>
#include <iostream>
#include <array>
#include <cmath>
#include <cstdlib>
std::string read(const char* p){std::ifstream f(p);std::stringstream s;s<<f.rdbuf();auto t=s.str();if(t.empty())exit(3);t.replace(0,t.find('\n'),"#version 320 es\nprecision highp float;\nprecision highp int;");return t;}
GLuint shader(GLenum k,const std::string&s){GLuint x=glCreateShader(k);const char*p=s.c_str();glShaderSource(x,1,&p,0);glCompileShader(x);GLint ok;glGetShaderiv(x,GL_COMPILE_STATUS,&ok);if(!ok){char b[8192];glGetShaderInfoLog(x,sizeof b,0,b);std::cerr<<b;exit(4);}return x;}
GLuint program(const char*p,bool sprite){std::string v="#version 320 es\nprecision highp float; precision highp int;\nuniform vec4 source;\n";v+=sprite?"flat out vec4 fragment_color; out vec3 tex_coord; flat out uvec2 tex_info;\n":"out vec4 fragment_color; out vec4 gs_scissor;\n";v+="void main(){vec2 p=vec2((gl_VertexID<<1)&2,gl_VertexID&2);gl_Position=vec4(p*2.-1.,0,1);fragment_color=source;";v+=sprite?"tex_coord=vec3(0.5);tex_info=uvec2(0,1);}":"gs_scissor=vec4(0);}";GLuint x=glCreateProgram();glAttachShader(x,shader(GL_VERTEX_SHADER,v));glAttachShader(x,shader(GL_FRAGMENT_SHADER,read(p)));glLinkProgram(x);GLint ok;glGetProgramiv(x,GL_LINK_STATUS,&ok);if(!ok){char b[8192];glGetProgramInfoLog(x,sizeof b,0,b);std::cerr<<b;exit(5);}return x;}
using V=std::array<float,4>;
int failures=0;
bool separate_alpha=false;
bool hdr_chain=false,uses_hud=false;
void check(bool x,const char*m){std::cout<<"check "<<m<<" "<<(x?"PASS":"FAIL")<<"\n";if(!x)++failures;}
V draw(GLuint p,bool hdr,int mode,V s,float amin=0,float amax=3){glUseProgram(p);glUniform4fv(glGetUniformLocation(p,"source"),1,s.data());auto loc=glGetUniformLocation(p,"scissor_enable");if(loc>=0)glUniform1i(loc,0);loc=glGetUniformLocation(p,"alpha_min");if(loc>=0)glUniform1f(loc,amin);loc=glGetUniformLocation(p,"alpha_max");if(loc>=0)glUniform1f(loc,amax);glClearColor(.8,.6,.1,mode>=4?.9:.5);glClear(GL_COLOR_BUFFER_BIT);if(mode==0)glDisable(GL_BLEND);else {glEnable(GL_BLEND);glBlendEquationSeparate(mode==1?GL_FUNC_ADD:GL_FUNC_REVERSE_SUBTRACT,mode==1?GL_FUNC_ADD:GL_FUNC_REVERSE_SUBTRACT);glBlendFuncSeparate(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA,mode==3?GL_ZERO:GL_ONE,GL_ZERO);}if(mode>=4){
 glEnable(GL_BLEND); GLenum sf=mode==5?GL_DST_ALPHA:GL_SRC_ALPHA;
 glBlendEquation(mode==6?GL_FUNC_REVERSE_SUBTRACT:GL_FUNC_ADD);
 if(hdr_chain&&!uses_hud&&separate_alpha)glBlendFuncSeparate(sf,GL_ONE,mode==6?GL_ZERO:GL_ONE,GL_ZERO);
 else glBlendFunc(sf,GL_ONE);
}glDrawArrays(GL_TRIANGLES,0,3);V r;if(hdr)glReadPixels(0,0,1,1,GL_RGBA,GL_FLOAT,r.data());else{unsigned char b[4];glReadPixels(0,0,1,1,GL_RGBA,GL_UNSIGNED_BYTE,b);for(int i=0;i<4;++i)r[i]=b[i]/255.f;}auto e=glGetError();std::cout<<" RGBA="<<r[0]<<","<<r[1]<<","<<r[2]<<","<<r[3]<<" gl_error="<<e<<"\n";if(e)++failures;return r;}
int main(int argc,char**argv){if(argc!=5)return 2;auto get=(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");EGLDisplay d=get(EGL_PLATFORM_SURFACELESS_MESA,EGL_DEFAULT_DISPLAY,nullptr);EGLint ma,mi;if(!eglInitialize(d,&ma,&mi))return 6;eglBindAPI(EGL_OPENGL_ES_API);EGLint at[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_NONE};EGLConfig cfg;EGLint n;if(!eglChooseConfig(d,at,&cfg,1,&n)||!n)return 7;EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};auto ctx=eglCreateContext(d,cfg,EGL_NO_CONTEXT,ca);if(!eglMakeCurrent(d,EGL_NO_SURFACE,EGL_NO_SURFACE,ctx))return 8;std::cout<<"vendor="<<glGetString(GL_VENDOR)<<" renderer="<<glGetString(GL_RENDERER)<<" version="<<glGetString(GL_VERSION)<<" EGL="<<ma<<"."<<mi<<"\n";GLuint ps[]={program(argv[1],false),program(argv[2],false),program(argv[3],true),program(argv[4],true)};GLuint vao;glGenVertexArrays(1,&vao);glBindVertexArray(vao);GLuint white;glGenTextures(1,&white);glBindTexture(GL_TEXTURE_2D,white);unsigned char w[]={255,255,255,255};glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA8,1,1,0,GL_RGBA,GL_UNSIGNED_BYTE,w);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);glViewport(0,0,1,1);
for(bool hdr:{false,true}){hdr_chain=hdr;GLuint fb,rt;glGenFramebuffers(1,&fb);glBindFramebuffer(GL_FRAMEBUFFER,fb);glGenRenderbuffers(1,&rt);glBindRenderbuffer(GL_RENDERBUFFER,rt);glRenderbufferStorage(GL_RENDERBUFFER,hdr?GL_RGBA16F:GL_RGBA8,1,1);glFramebufferRenderbuffer(GL_FRAMEBUFFER,GL_COLOR_ATTACHMENT0,GL_RENDERBUFFER,rt);check(glCheckFramebufferStatus(GL_FRAMEBUFFER)==GL_FRAMEBUFFER_COMPLETE,"framebuffer_complete");V src={.2,.3,.4,2.0078125};for(int mode=0;mode<4;++mode){std::cout<<"format="<<(hdr?"RGBA16F":"RGBA8")<<" mode="<<mode<<" before";auto a=draw(ps[0],hdr,mode,src);std::cout<<"format="<<(hdr?"RGBA16F":"RGBA8")<<" mode="<<mode<<" after";auto b=draw(ps[1],hdr,mode,src);if(!hdr){bool same=true;for(int k=0;k<4;++k)same&=std::abs(a[k]-b[k])<=1.f/255;check(same,"normalized_before_after_same_factors");}else{if(mode!=2)check(b[3]>=0&&b[3]<=1,"HDR_alpha_bounded");else check(b[3]==-1,"old_reverse_factors_still_negative_after_shader_clamp");if(mode==1){check(a[0]<0&&a[1]<0,"old_source_over_negative_destination_contribution");check(std::abs(b[0]-.2)<.001&&std::abs(b[1]-.3)<.001&&std::abs(b[2]-.4)<.001,"corrected_source_over_equals_source");}if(mode==3)check(b[3]==0,"reverse_corrected_alpha_zero");}}
std::cout<<"format="<<(hdr?"RGBA16F":"RGBA8")<<" HDR_RGB_no_blend_after";auto bright=draw(ps[1],hdr,0,{2.5,3,4,2.0078125});if(hdr)check(bright[0]==1&&bright[1]==1&&bright[2]==1&&bright[3]==1,"current_shader_source_RGB_clamp_preserved");
for(int mode=4;mode<=6;++mode){
 std::cout<<"essai40 format="<<(hdr?"RGBA16F":"RGBA8")<<" mode="<<mode<<" legacy";
 separate_alpha=false;auto legacy=draw(ps[1],hdr,mode,{.2,.3,.4,1});
 std::cout<<"essai40 format="<<(hdr?"RGBA16F":"RGBA8")<<" mode="<<mode<<" guarded";
 separate_alpha=true;auto fixed=draw(ps[1],hdr,mode,{.2,.3,.4,1});
 bool rgb_same=true;for(int k=0;k<3;++k)rgb_same&=std::abs(legacy[k]-fixed[k])<.001;
 check(rgb_same,"essai40_single_draw_RGB_unchanged_same_destination");
 check(fixed[3]>=0&&fixed[3]<=1,"essai40_alpha_bounded");
 if(hdr){check(mode==6?legacy[3]<0:legacy[3]>1,"essai40_legacy_alpha_outside_unit_interval");check(fixed[3]==(mode==6?0:1),"essai40_corrected_alpha_exact");}
 else{bool same=true;for(int k=0;k<4;++k)same&=legacy[k]==fixed[k];check(same,"essai40_OFF_identical_RGBA");}
 separate_alpha=false;
}
if(!hdr){
 hdr_chain=true;uses_hud=true;
 for(int mode:{4,5}){
  std::cout<<"essai40_final HDR_chain=1 HUD=1 RGBA8 mode="<<mode<<" legacy";
  separate_alpha=false;auto legacy=draw(ps[1],false,mode,{.2,.3,.4,.4});
  std::cout<<"essai40_final HDR_chain=1 HUD=1 RGBA8 mode="<<mode<<" guarded";
  separate_alpha=true;auto guarded=draw(ps[1],false,mode,{.2,.3,.4,.4});
  bool same=true;for(int k=0;k<4;++k)same&=legacy[k]==guarded[k];
  check(same,"essai40_final_HDR_HUD_RGBA_unchanged");
  GLint sf,df;glGetIntegerv(GL_BLEND_SRC_ALPHA,&sf);glGetIntegerv(GL_BLEND_DST_ALPHA,&df);
  check(sf==(mode==5?GL_DST_ALPHA:GL_SRC_ALPHA)&&df==GL_ONE,"essai40_final_HDR_HUD_legacy_blend_state");
 }
 hdr_chain=false;uses_hud=false;separate_alpha=false;
}
for(int arm=0;arm<2;++arm){std::cout<<"format="<<(hdr?"RGBA16F":"RGBA8")<<" sprite_arm="<<arm<<" raw_alpha_window_1.5_to_3";auto pass=draw(ps[2+arm],hdr,0,src,1.5,3);check(std::abs(pass[0]-.2)<.005,"raw_alpha_pass_before_clamp");std::cout<<"format="<<(hdr?"RGBA16F":"RGBA8")<<" sprite_arm="<<arm<<" raw_alpha_window_0_to_1";auto discard=draw(ps[2+arm],hdr,0,src,0,1);check(std::abs(discard[0]-.8)<.005&&std::abs(discard[3]-.5)<.005,"raw_alpha_discard_before_clamp");}glDeleteRenderbuffers(1,&rt);glDeleteFramebuffers(1,&fb);}
std::cout<<"failures="<<failures<<" EGL_error="<<eglGetError()<<"\n";return failures?1:0;}
