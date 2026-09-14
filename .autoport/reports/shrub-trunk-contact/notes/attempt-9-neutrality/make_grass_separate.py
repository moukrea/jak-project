from pathlib import Path
D=Path(__file__).parent
s=(D/'grassfull.cpp').read_text()
s=s.replace('GLuint p[2]={program(std::string(argv[1])+"/grass-0.vert",false),program(std::string(argv[1])+"/grass-1.vert",true)};', 'GLuint p[3]={program(std::string(argv[1])+"/grass-0.vert",false),program(std::string(argv[1])+"/grass-color.vert",false),program(std::string(argv[1])+"/grass-1.vert",true)};')
s=s.replace('k<2','k<3')
s=s.replace('glBeginTransformFeedback(GL_POINTS);glDrawArrays(GL_POINTS,0,10);glEndTransformFeedback();', 'if(!glIsEnabled(GL_RASTERIZER_DISCARD))throw std::runtime_error("discard disabled");GLuint query;glGenQueries(1,&query);glBeginQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN,query);glBeginTransformFeedback(GL_POINTS);glDrawArraysInstanced(GL_POINTS,0,10,1);glEndTransformFeedback();glEndQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN);GLuint written=0;glGetQueryObjectuiv(query,GL_QUERY_RESULT,&written);glDeleteQueries(1,&query);if(written!=10)throw std::runtime_error("capture count");')
a=s.index('std::string tag=std::string(argv[1])+"/grass-full-s');b=s.index('\n return 0;',a)
s=s[:a]+'''std::string tag=std::string(argv[1])+"/grass-separate-s"+std::to_string(scenario)+"-c"+std::to_string(c);
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
''' +s[b:]
(D/'grass-separate.cpp').write_text(s)
