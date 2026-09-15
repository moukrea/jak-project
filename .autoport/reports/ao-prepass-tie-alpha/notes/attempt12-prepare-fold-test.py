from pathlib import Path
n=Path(__file__).resolve().parent
s=(n/'attempt11-invariants.cpp').read_text()
s=s[:s.index('  auto run = [&]')] + r'''
  // Same existing EGL/texture/chain fixture; translate the 4x4 input against a
  // fixed two-plane concave fold. This checks phases where the candidate is active.
  const int tile[16]={0,11,2,15,9,4,13,6,3,14,1,8,12,7,10,5};
  for(int y=0;y<Y;++y)for(int x=0;x<X;++x)
    flat[y*X+x]=uint32_t(std::lround((.02+std::max(0.,x-399.5)*.00005)*16777215.0))<<8;
  for(int typ=0;typ<2;++typ)for(int shader=0;shader<2;++shader){
    std::vector<float> low(N,1e9),high(N,-1e9),input(N);
    for(int shift=0;shift<16;++shift){
      for(int y=0;y<Y;++y)for(int x=0;x<X;++x)
        input[y*X+x]=typ?tile[((y+shift/4)%4)*4+(x+shift%4)%4]/16.f
                       :tile[((y+shift/4)%4)*4+(x+shift%4)%4]*16.f/255;
      auto output=run_one(programs[shader],typ,input,flat);
      for(size_t k=0;k<N;++k){low[k]=std::min(low[k],output[k]);high[k]=std::max(high[k],output[k]);}
    }
    float maximum=0;int maxx=-1;
    for(int x=390;x<=409;++x){float range=high[300*X+x]-low[300*X+x];
      if(range>maximum){maximum=range;maxx=x;}
      std::printf("FOLD_PHASE shader=%s format=%s x=%d phases=16 min=%.12g max=%.12g range=%.12g\n",
        shader?"candidate":"reference",typ?"R32F":"R8",x,low[300*X+x],high[300*X+x],range);
    }
    std::printf("FOLD_PHASE_MAX shader=%s format=%s phases=16 max_range=%.12g x=%d\n",
      shader?"candidate":"reference",typ?"R32F":"R8",maximum,maxx);
  }
  std::printf("gl_errors=0 diagnostic_only=1\n");return 0;
}
'''
(n/'attempt12-fold-phases.cpp').write_text(s)
