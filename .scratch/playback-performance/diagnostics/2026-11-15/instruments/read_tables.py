import xml.etree.ElementTree as E
from pathlib import Path

def table(name,root='.build/instruments-display'):
 tree=E.parse(Path(root)/(name+'.xml')); ids={x.get('id'):x for x in tree.iter() if x.get('id')}
 def resolve(x):return ids[x.get('ref')] if x.get('ref') else x
 cols=[c.findtext('mnemonic') for c in tree.findall('.//schema/col')]
 rows=[]
 for row in tree.findall('.//row'):
  vals={}
  for key,x in zip(cols,row):
   x=resolve(x); vals[key]=x.text if x.tag!='sentinel' else None;vals[key+'_fmt']=x.get('fmt')
  rows.append(vals)
 return rows
if __name__=='__main__':
 for n in ['display-compositor-events-interval','display-events-interval','metal-io-surface-access','ca-client-buffer-wait-interval']:
  try:r=table(n)
  except Exception as e: print(n,e);continue
  print(n,len(r)); print(*r[:3],sep='\n')
