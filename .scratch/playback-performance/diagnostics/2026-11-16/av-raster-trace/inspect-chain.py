import sys,json,collections,statistics
sys.path.insert(0,'.build/instruments-display');from read_tables import table
p='.build/av-raster-probe/trace-export';t=table('time-info',p)[0];ep=int(t['mabs-epoch'])*125/3/1e9
raw=json.load(open('.build/av-raster-probe/events.json'));fs=[x for x in raw if 'videoSurface'in x];acc=table('metal-io-surface-access',p);sw=table('display-surface-swap',p)
print('swaps',len(sw))
for lo in [8,25,40,55]:print(lo,len([x for x in sw if lo<int(x['timestamp'])/1e9<lo+10]))
f=next(x for x in fs if 26<x['enqueue']-ep<27);start=f['enqueue']-ep
rr=sorted([x for x in acc if x['pid']=='652' and x['access-type']=='0' and int(x['surface-id'])==f['videoSurface'] and start<int(x['timestamp'])/1e9<start+.05],key=lambda x:int(x['timestamp']))
r=rr[0];print('frame',f,'trace enqueue',start,'read',r)
cmd=r['cmdbuffer-id'];enc=r['encoder-id'];a=[x for x in acc if x['cmdbuffer-id']==cmd];print('same cmd access',[(x['access-type'],x['surface-id'],x['encoder-id'],x['width'],x['height'],int(x['timestamp'])/1e9)for x in a])
for sid in set(x['surface-id']for x in a if x['access-type']=='1'):
 print('output',sid,'swaps',[(int(x['timestamp'])/1e9)for x in sw if x['surface-id']==sid and start<int(x['timestamp'])/1e9<start+.08]);print('reads',[(int(x['timestamp'])/1e9,x['cmdbuffer-id'],x['encoder-id'])for x in acc if x['surface-id']==sid and x['access-type']=='0' and start<int(x['timestamp'])/1e9<start+.05][:8])
