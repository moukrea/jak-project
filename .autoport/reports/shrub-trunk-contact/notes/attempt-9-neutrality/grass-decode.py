import struct,pathlib,csv
D=pathlib.Path(__file__).parent
names=['clip_x','clip_y','clip_z','clip_w','color_r','color_g','color_b','alpha','uv_x','uv_y','is_card','seed']
with (D/'grass-differences.csv').open('w') as f:
 w=csv.writer(f);w.writerow(['scenario','contact','vertex','component','historical','instrumented','historical_bits','instrumented_bits'])
 for scenario in range(9):
  for c in range(2):
   a=(D/f'grass-full-s{scenario}-c{c}-off.bin').read_bytes();b=(D/f'grass-full-s{scenario}-c{c}-on.bin').read_bytes()
   for i in range(10):
    for j in range(12):
     x=a[(i*12+j)*4:(i*12+j+1)*4];y=b[(i*22+j)*4:(i*22+j+1)*4]
     if x!=y:w.writerow([scenario,c,i,names[j],struct.unpack('f',x)[0],struct.unpack('f',y)[0],x.hex(),y.hex()])
