from bs4 import BeautifulSoup
import json, pathlib, urllib.request, time
root=pathlib.Path('assets');(root/'crops').mkdir(parents=True,exist_ok=True)
soup=BeautifulSoup(pathlib.Path('build/research/Ingredients.html').read_text(encoding='utf-8-sig'),'html.parser')
items=[]
for tr in soup.select('table')[0].select('tr'):
 cells=tr.select(':scope > td')
 if len(cells)<11: continue
 if not any(a.get('title','').endswith(' Seed') for a in cells[-1].select('a')): continue
 name=cells[1].get_text(' ',strip=True);img=cells[0].select_one('img')
 if not img: continue
 src=img['src'];url='https://dreamlightvalleywiki.com'+src
 slug=name.lower().replace(' ','_').replace("'",'')
 asset='assets/crops/'+slug+'.png'
 try:
  req=urllib.request.Request(url,headers={'User-Agent':'DreamlightCompanion/0.2 (personal offline planner)'})
  pathlib.Path(asset).write_bytes(urllib.request.urlopen(req,timeout=30).read())
 except Exception as e: print('image failed',name,str(e));continue
 items.append({'name':name,'image':asset,'imageSource':url,'source':'https://dreamlightvalleywiki.com/Ingredients','location':cells[-2].get_text(' ',strip=True),'growth':cells[6].get_text(' ',strip=True)})
 time.sleep(.1)
(root/'crops.json').write_text(json.dumps(items,indent=2),encoding='utf-8')
print('Bundled crops:',len(items));print([c['name'] for c in items])

