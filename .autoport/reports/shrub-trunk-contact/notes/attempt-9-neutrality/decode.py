import pathlib,struct,csv
D=pathlib.Path(__file__).parent
with (D/'capture.csv').open('w') as out:
 w=csv.writer(out);w.writerow(['banc','shader','contact','wind','vertex','clip_x','clip_y','clip_z','clip_w','pre_x','pre_y','pre_z','post_x','post_y','post_z'])
 for n in ['shrub','tfrag3','etie','etie_base']:
  for c in range(2):
   for wind in range(2):
    raw=(D/f'{n}-c{c}-w{wind}-on.bin').read_bytes();v=struct.unpack('120f12I',raw)
    for i in range(12):w.writerow(['synthetic',n,c,wind,v[120+i],*v[4*i:4*i+4],*v[48+i*3:51+i*3],*v[84+i*3:87+i*3]])
  off=(D/f'{n}-c0-w0-on.bin').read_bytes();on=(D/f'{n}-c0-w1-on.bin').read_bytes()
  count=sum(off[192+i*12:204+i*12]!=on[192+i*12:204+i*12] for i in range(12))
  print(f'{n} synthetic_wind_changes_pre={count}/12')
  assert count==12
