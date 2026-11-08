import json,pathlib,urllib.request,time
from bs4 import BeautifulSoup
items={};sources=[]
soup=BeautifulSoup(pathlib.Path('build/research/Collections.html').read_text(encoding='utf-8-sig'),'html.parser')
for a in soup.select('.ct-hub-card'):
 name=a['data-ct-section'];url='https://dreamlightvalleywiki.com/api.php?action=parse&page='+urllib.parse.quote('Collections/'+name,safe='')+'&prop=text&format=json'
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'DreamlightCompanion/0.2'})
  data=json.load(urllib.request.urlopen(req,timeout=40));doc=BeautifulSoup(data['parse']['text']['*'],'html.parser')
  found=doc.select('.ct-item[data-ct-pid]')
  for item in found:
   image=item.select_one('img');img=urllib.parse.urljoin('https://dreamlightvalleywiki.com',image['src']) if image else None
   area=item.get('data-ct-area','Unknown area');details={'fields':{'Collection:':name,'Location / DLC:':area},'image':img,'blocks':[],'links':[],'schedule':[],'summary':True}
   row={'id':item['data-ct-pid'],'title':item['data-ct-name'],'categories':json.dumps([name,area]),'details':json.dumps(details)};
   if row['id'] in items: row['categories']=json.dumps(sorted(set(json.loads(items[row['id']]['categories'])+json.loads(row['categories']))))
   items[row['id']]=row
  sources.append(name);print(name,len(found),flush=True)
 except Exception as e:print('FAILED',name,str(e),flush=True)
 time.sleep(.25)
pathlib.Path('assets/catalog.json').write_text(json.dumps({'source':'https://dreamlightvalleywiki.com/Collections','license':'CC BY-NC-SA 4.0','sources':sources,'records':list(items.values())}),encoding='utf-8')
print('Snapshot:',len(items),flush=True)
