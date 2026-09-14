#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <fstream>
#include <iostream>
#include <vector>
#include <cstring>
#include <cmath>
#include <string>
#include <stdexcept>
void check(){auto e=glGetError(); if(e)throw std::runtime_error("GL error "+std::to_string(e));}
GLuint shader(GLenum type,std::string s){GLuint a=glCreateShader(type);const char*p=s.c_str();glShaderSource(a,1,&p,0);glCompileShader(a);GLint ok;glGetShaderiv(a,GL_COMPILE_STATUS,&ok);char l[16384];glGetShaderInfoLog(a,sizeof(l),0,l);if(!ok)throw std::runtime_error(l);return a;}
GLuint program(std::string path,bool probe){std::ifstream f(path);std::string s((std::istreambuf_iterator<char>(f)),{});GLuint p=glCreateProgram();glAttachShader(p,shader(GL_VERTEX_SHADER,s));glAttachShader(p,shader(GL_FRAGMENT_SHADER,"#version 300 es\nprecision highp float;out vec4 c;void main(){c=vec4(1);}"));const char* v[]={"gl_Position","v_color","v_alpha","v_uv","v_is_card","v_seed","probe_grass_pre","probe_grass_post","probe_grass_ids"};glTransformFeedbackVaryings(p,probe?9:6,v,GL_INTERLEAVED_ATTRIBS);glLinkProgram(p);GLint ok;glGetProgramiv(p,GL_LINK_STATUS,&ok);char l[8192];glGetProgramInfoLog(p,sizeof(l),0,l);if(!ok)throw std::runtime_error(l);return p;}
void uf(GLuint p,const char*n,float v){glUniform1f(glGetUniformLocation(p,n),v);}void ui(GLuint p,const char*n,int v){glUniform1i(glGetUniformLocation(p,n),v);}void uv(GLuint p,const char*n,float a,float b,float c,float d){glUniform4f(glGetUniformLocation(p,n),a,b,c,d);}
std::vector<float> run(GLuint p,bool probe,int contact,int wind,std::string file){
 glUseProgram(p);uf(p,"u_near_dist",100000);uf(p,"u_card_dist",200000);uf(p,"u_time",wind*3.7);uf(p,"u_droop_len",1);uf(p,"fog_constant",1);float camera[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};glUniformMatrix4fv(glGetUniformLocation(p,"camera"),1,0,camera);ui(p,"u_shrub_contact_on",contact);ui(p,"u_tie_contact_on",contact);ui(p,"u_shrub_native_on",wind);uf(p,"u_tie_sway_amp",wind*100.f);uf(p,"u_tie_sway_time",3.7f);uf(p,"u_tie_sway_flutter",.2f);glUniform2f(glGetUniformLocation(p,"u_tie_sway_dir"),.6f,.8f);uv(p,"u_jak_pos",0,0,0,contact);uv(p,"u_jak_ledge",100,0,100,contact);ui(p,"u_trample_count",contact);uv(p,"u_trample[0]",100,0,100,1000);uv(p,"u_trample2[0]",.7,0,0,0);
 ui(p,"tex_T18",0);ui(p,"u_tie_contact_tex",1);ui(p,"tex_T10",2);float mat[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};glUniformMatrix4fv(glGetUniformLocation(p,"cam_no_persp"),1,0,mat);uv(p,"persp0",0,0,1,.01);uv(p,"persp1",1,1,0,1);
 GLuint ub=glGetUniformBlockIndex(p,"ub_frame");if(ub!=GL_INVALID_INDEX)glUniformBlockBinding(p,ub,2);
 GLuint buffer;glGenBuffers(1,&buffer);int stride=probe?22:12;glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER,buffer);glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER,10*stride*4,nullptr,GL_STREAM_READ);glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER,0,buffer);glEnable(GL_RASTERIZER_DISCARD);if(!glIsEnabled(GL_RASTERIZER_DISCARD))throw std::runtime_error("discard disabled");GLuint query;glGenQueries(1,&query);glBeginQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN,query);glBeginTransformFeedback(GL_POINTS);glDrawArraysInstanced(GL_POINTS,0,10,1);glEndTransformFeedback();glEndQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN);GLuint written=0;glGetQueryObjectuiv(query,GL_QUERY_RESULT,&written);glDeleteQueries(1,&query);if(written!=10)throw std::runtime_error("capture count");glDisable(GL_RASTERIZER_DISCARD);check();auto data=glMapBufferRange(GL_TRANSFORM_FEEDBACK_BUFFER,0,10*stride*4,GL_MAP_READ_BIT);if(!data)throw std::runtime_error("map");std::vector<float> all(10*stride);memcpy(all.data(),data,all.size()*4);glUnmapBuffer(GL_TRANSFORM_FEEDBACK_BUFFER);std::ofstream out(file,std::ios::binary);out.write((char*)all.data(),all.size()*4);glDeleteBuffers(1,&buffer);return all;}
int main(int argc,char**argv){try{auto get=(PFNEGLGETPLATFORMDISPLAYEXTPROC)eglGetProcAddress("eglGetPlatformDisplayEXT");EGLDisplay d=get(EGL_PLATFORM_SURFACELESS_MESA,EGL_DEFAULT_DISPLAY,nullptr);EGLint major,minor;if(!eglInitialize(d,&major,&minor))throw std::runtime_error("eglInitialize failed "+std::to_string(eglGetError()));eglBindAPI(EGL_OPENGL_ES_API);EGLint a[]={EGL_SURFACE_TYPE,EGL_PBUFFER_BIT,EGL_RENDERABLE_TYPE,EGL_OPENGL_ES3_BIT,EGL_NONE};EGLConfig config;EGLint n;eglChooseConfig(d,a,&config,1,&n);EGLint ca[]={EGL_CONTEXT_CLIENT_VERSION,3,EGL_NONE};auto ctx=eglCreateContext(d,config,EGL_NO_CONTEXT,ca);if(!eglMakeCurrent(d,EGL_NO_SURFACE,EGL_NO_SURFACE,ctx))throw std::runtime_error("eglMakeCurrent failed");EGLint pa[]={EGL_WIDTH,1,EGL_HEIGHT,1,EGL_NONE}; auto surf=eglCreatePbufferSurface(d,config,pa); eglMakeCurrent(d,surf,surf,ctx);std::cout<<"BANC_SYNTHETIQUE renderer="<<glGetString(GL_RENDERER)<<" version="<<glGetString(GL_VERSION)<<std::endl;
 GLuint vao;glGenVertexArrays(1,&vao);glBindVertexArray(vao);float pos[36];for(int i=0;i<12;i++){pos[i*3]=100+i*37;pos[i*3+1]=-200+i*170;pos[i*3+2]=150+i*29;}GLuint vb;glGenBuffers(1,&vb);glBindBuffer(GL_ARRAY_BUFFER,vb);glBufferData(GL_ARRAY_BUFFER,sizeof(pos),pos,GL_STATIC_DRAW);glVertexAttribPointer(0,3,GL_FLOAT,0,0,0);glEnableVertexAttribArray(0);glVertexAttribI4i(2,0,0,0,0);glVertexAttribI4i(3,0,0,0,0);glVertexAttrib4f(4,0,1,0,1);glVertexAttrib1f(7,.25);glVertexAttrib1f(8,.3);glVertexAttribI4i(9,1,0,0,0);glVertexAttribI4ui(10,1,0,0,0);
 float frame[56]={};for(int k=0;k<3;k++)for(int i=0;i<4;i++)frame[k*16+i*5]=1;frame[47]=1;GLuint ub;glGenBuffers(1,&ub);glBindBuffer(GL_UNIFORM_BUFFER,ub);glBufferData(GL_UNIFORM_BUFFER,sizeof(frame),frame,GL_STATIC_DRAW);glBindBufferBase(GL_UNIFORM_BUFFER,2,ub);
 GLuint tex[3];glGenTextures(3,tex);for(int t=0;t<3;t++){float data[24]={};for(int x=0;x<2;x++){int off=t==0?8+x*4:x*4;data[off]=100;data[off+1]=0;data[off+2]=150;data[off+3]=2000;if(t==0){data[x*4]=.04;data[x*4+1]=.02;data[x*4+2]=2000;data[x*4+3]=1;}}glActiveTexture(GL_TEXTURE0+t);glBindTexture(GL_TEXTURE_2D,tex[t]);glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA32F,2,3,0,GL_RGBA,GL_FLOAT,data);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);}
 glDisableVertexAttribArray(0);glVertexAttrib4f(0,100,0,150,2000);glVertexAttrib4f(1,.3,.5,.2,.1);glVertexAttrib4f(2,.4,.5,.6,1e9);glVertexAttrib4f(3,.5,.5,.5,0);glVertexAttrib4f(4,0,1,0,0);
 GLuint p[3]={program(std::string(argv[1])+"/grass-0.vert",false),program(std::string(argv[1])+"/grass-color.vert",false),program(std::string(argv[1])+"/grass-1.vert",true)};
 bool all_equal=true;for(int scenario=0;scenario<9;scenario++)for(int c=0;c<2;c++){
 for(int k=0;k<3;k++){glUseProgram(p[k]);ui(p[k],"u_mode",(scenario==1||scenario>=7)?1:0);ui(p[k],"u_debug",scenario==3?3:0);uf(p[k],"u_overhang",scenario==2?1:0);uv(p[k],"camera_position",scenario==4?1000000:scenario>=7?60000:0,0,0,0);ui(p[k],"u_occ_count",scenario==5?1:0);uv(p[k],"u_occ[0]",100,0,150,5000);}
 glVertexAttrib4f(1,.3,scenario==8?.6:.5,.2,.1);glVertexAttrib4f(4,0,1,0,scenario==1?3:scenario==2?-1:0);glVertexAttrib4f(2,.4,.5,.6,scenario==6?0:1e9);
 std::string tag=std::string(argv[1])+"/grass-separate-s"+std::to_string(scenario)+"-c"+std::to_string(c);
 auto historical=run(p[0],false,c,1,tag+"-historical.bin");auto color=run(p[1],false,c,1,tag+"-color.bin");
 glUseProgram(p[2]);ui(p[2],"u_probe_grass_no_contact",1);auto before=run(p[2],true,c,1,tag+"-before.bin");
 glUseProgram(p[2]);ui(p[2],"u_probe_grass_no_contact",0);auto after=run(p[2],true,c,1,tag+"-after.bin");
 int emitted=0,changed=0,color_mismatches=0,position_mismatches=0,measure_alpha_mismatches=0;
 for(int i=0;i<10;i++){
 if(memcmp(&historical[i*12],&color[i*12],48))color_mismatches++;
 if(memcmp(&color[i*12],&after[i*22],16))position_mismatches++;
 if(memcmp(&color[i*12+7],&after[i*22+7],4))measure_alpha_mismatches++;
 for(auto* capture:{&before,&after}){uint32_t ids[2];memcpy(ids,&(*capture)[i*22+20],8);if(ids[0]!=0||ids[1]!=(unsigned)i)throw std::runtime_error("IDs");}
 if(after[i*22+19]==1)emitted++;
 if(before[i*22+15]>0&&after[i*22+19]>0&&memcmp(&before[i*22+12],&after[i*22+16],12))changed++;
 }
 std::cout<<"grass_separate scenario="<<scenario<<" contact="<<c<<" captured=10 color_bytes=480 color_mismatches="<<color_mismatches<<" measure_position_mismatches="<<position_mismatches<<" measure_alpha_mismatches="<<measure_alpha_mismatches<<" emitted="<<emitted<<" pre_post_changed="<<changed<<std::endl;
 if(color_mismatches||position_mismatches||(!c&&changed)||(c&&scenario==0&&changed!=8)||(c&&scenario==7&&changed!=5))all_equal=false;
 }if(!all_equal)throw std::runtime_error("separate grass neutrality failed");

 return 0;}catch(const std::exception&e){std::cerr<<e.what()<<std::endl;return 1;}}
