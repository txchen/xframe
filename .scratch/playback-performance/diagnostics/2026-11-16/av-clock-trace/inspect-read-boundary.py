exec(open('.build/av-clock-probe/analyze.py').read().split("print('unambiguous")[0])
import bisect
for fid in [4685,4687,4865,5107,6483,6486,6737,6783]:
 f=next(x for x in frames if x['id']==fid);t=f['enqueue']-epoch;ff=bySurf[f['videoSurface']];i=ff.index(f);p=ff[i-1]if i else None;n=ff[i+1]if i+1<len(ff)else None
 rr=sorted((s,c)for s,c in reads[f['videoSurface']]if t-.05<s<t+.08)
 print(fid,'sid',f['videoSurface'],'next',None if n is None else (n['id'],round((n['enqueue']-f['enqueue'])*1000,2)),'prev',None if p is None else (p['id'],round((f['enqueue']-p['enqueue'])*1000,2)),'reads',[(round((s-t)*1000,3),c)for s,c in rr])
