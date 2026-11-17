import sys,json,statistics,collections
sys.path.insert(0,'.build/instruments-display');from read_tables import table
root='.build/layer-vsync-probe/trace-export';t=table('time-info',root)[0];epoch=int(t['mabs-epoch'])*125/3/1e9
r=json.load(open('.build/layer-vsync-probe/events.json'));marks=[x for x in r if 'marker'in x];print('markers',[(x['block'],x['marker']-epoch)for x in marks[:4]])
acc=table('metal-io-surface-access',root);swaps=table('display-surface-swap',root);req=table('ca-client-present-request',root);gpu=table('metal-gpu-intervals',root)
for lo,hi in [(8,18),(27,37),(44,54)]:
 a=[x for x in acc if lo<int(x['timestamp'])/1e9<hi];s=[x for x in swaps if lo<int(x['timestamp'])/1e9<hi]
 print('range',lo,hi,'swaps',len(s),'swap surfaces',collections.Counter(x['surface-id']for x in s))
 for pid in ['652','14637']:
  for typ in ['0','1']:
   vals=[x for x in a if x['pid']==pid and x['access-type']==typ];print(pid,typ,len(vals),collections.Counter(x['surface-id']for x in vals).most_common(8))
 fs={}
 for x in r:
  if 'id'in x:fs.setdefault(x['id'],{}).update(x)
 f=[x for x in fs.values() if lo<x.get('submit',0)-epoch<hi and x.get('actual',0)>0]
 for k in ['submit','gpuEnd','actual']:
  z=[(x[k]-epoch)for x in f if k in x];print(k,len(z),z[:3])
 print('actual postgpu',statistics.median((x['actual']-x['gpuEnd'])*1000 for x in f if 'gpuEnd'in x))
print('async request example',next(x for x in req if 30<int(x['timestamp'])/1e9<31))
print('async acc example',next(x for x in acc if 30<int(x['timestamp'])/1e9<31 and x['pid']=='652'))
