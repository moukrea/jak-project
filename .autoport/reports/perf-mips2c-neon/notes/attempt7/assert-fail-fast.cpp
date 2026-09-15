#include <cstdio>
#include <cstdlib>
[[noreturn]] void private_assert_failed(const char* expr,const char* file,int line,const char* fn,const char* msg) { std::fprintf(stderr,"ASSERT %s %s:%d %s %s\n",expr,file,line,fn,msg); std::abort(); }
