"""Bundle every verified Gardening crop image. Requires previously downloaded wiki HTML."""
from bs4 import BeautifulSoup
from companion_data import gardening_data
import json,pathlib,urllib.request,time
root=pathlib.Path('assets');(root/'crops').mkdir(parents=True,exist_ok=True)
source=pathlib.Path('build/enrichment/Gardening.html')
items=gardening_data(BeautifulSoup(source.read_text(encoding='utf-8-sig'),'html.parser'))
for item in items:
    asset='assets/crops/'+item['name'].lower().replace(' ','_').replace("'",'')+'.png'
    request=urllib.request.Request(item['imageSource'],headers={'User-Agent':'DreamlightCompanion/0.5 (noncommercial offline crop assets)'})
    content=urllib.request.urlopen(request,timeout=45).read()
    if not content.startswith(b'\x89PNG'):raise ValueError('Unexpected image: '+item['name'])
    pathlib.Path(asset).write_bytes(content);item['image']=asset
    time.sleep(.5)
(root/'crops.json').write_text(json.dumps(items,ensure_ascii=False,indent=2),encoding='utf-8')
print('Bundled all',len(items),'verified Gardening crops')
