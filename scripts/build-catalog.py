"""Build the shared catalog with paced wiki access; no player data is uploaded."""
import argparse, datetime, email.utils, gzip, json, math, pathlib, re, time, urllib.request, urllib.parse, urllib.error
from bs4 import BeautifulSoup
from reference_data import enrich
ROOT=pathlib.Path(__file__).resolve().parents[1]
CACHE=ROOT/'build'/'wiki-source-cache'; CACHE.mkdir(parents=True,exist_ok=True)
LAST=0.0

def clean(element):
    if element is None:return ''
    clone=BeautifulSoup(str(element),'html.parser')
    for note in clone.select('sup.reference,.mw-editsection'):note.decompose()
    return re.sub(r'\s+',' ',clone.get_text(' ',strip=True)).strip()

def page(title):
    global LAST
    filename=CACHE/(re.sub(r'[^A-Za-z0-9_-]','_',title)+'.html')
    if filename.exists() and time.time()-filename.stat().st_mtime<21600:return BeautifulSoup(filename.read_text(encoding='utf-8'),'html.parser')
    for attempt in range(4):
        time.sleep(max(0,6-(time.monotonic()-LAST)))
        url='https://dreamlightvalleywiki.com/api.php?'+urllib.parse.urlencode({'action':'parse','page':title,'prop':'text','format':'json'},quote_via=urllib.parse.quote)
        try:
            LAST=time.monotonic()
            request=urllib.request.Request(url,headers={'User-Agent':'DreamlightCompanionData/0.3 (noncommercial wiki catalog; github.com/xspiral97/dreamlight-companion)'})
            data=json.load(urllib.request.urlopen(request,timeout=60))
            text=data['parse']['text']['*']; filename.write_text(text,encoding='utf-8')
            return BeautifulSoup(text,'html.parser')
        except urllib.error.HTTPError as error:
            if error.code not in (429,500,502,503,504):raise
            retry=error.headers.get('Retry-After','')
            if retry.isdigit():wait=int(retry)
            elif retry:
                try:wait=max(1,math.ceil((email.utils.parsedate_to_datetime(retry)-datetime.datetime.now(datetime.timezone.utc)).total_seconds()))
                except (ValueError,TypeError):wait=60*(attempt+1)
            else:wait=60*(attempt+1)
            print(f'{title}: HTTP {error.code}; waiting {wait}s',flush=True)
            if attempt==3:raise
            
            if wait>600:raise RuntimeError(f'Wiki cooldown is {wait}s; keep the previous published catalog')
            time.sleep(wait)
    raise RuntimeError(title)

def fields_of(doc):
    result={}
    for row in doc.select('#infobox tr'):
        cells=row.find_all(['td','th'],recursive=False)
        if len(cells)==2:result[clean(cells[0])]=clean(cells[1])
    return result

def hero(doc):
    image=doc.select_one('#infobox-image figure img') or doc.select_one('#infobox-image img')
    return urllib.parse.urljoin('https://dreamlightvalleywiki.com',image['src']) if image else None

def windows(day,text):
    if text.lower()=='n/a':return []
    if text.lower()=='all day':return [{'day':day,'start':0,'end':1440}]
    matches=list(re.finditer(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',text,re.I))
    def minute(match):return (int(match[1])%12+(12 if match[3].lower()=='pm' else 0))*60+int(match[2] or 0)
    return [{'day':day,'start':minute(matches[i]),'end':minute(matches[i+1])} for i in range(0,len(matches)-1,2)]

def critters(doc):
    result={};species=[]; days=['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']
    aliases={'Crocodiles':'Crocodile','Foxes':'Fox','Geese':'Goose','Pegasi':'Pegasus','Baby Dragons':'Baby Dragon','Sweet Bees':'Sweet Bee'}
    for table in doc.select('table'):
        rows=table.select('tr');heads=[clean(c) for c in rows[0].find_all(['th','td'],recursive=False)] if rows else []
        if 'Favorite Food' in heads:
            for row in rows[1:]:
                cells=row.find_all('td',recursive=False)
                if len(cells)<len(heads):continue
                name=clean(cells[heads.index('Name')]);singular=aliases.get(name,name[:-1] if name.endswith('s') else name)
                species.append((singular,{'Favorite food:':clean(cells[heads.index('Favorite Food')]),'Liked food:':clean(cells[heads.index('Liked Food')]),'Feeding method:':clean(cells[heads.index('Feeding Method')])}))
        if 'Sunday' not in heads or 'Name' not in heads:continue
        for row in rows[1:]:
            cells=row.find_all('td',recursive=False)
            if len(cells)<len(heads):continue
            label=cells[heads.index('Name')].select_one('a[title]');name=label.get('title') if label else clean(cells[heads.index('Name')])
            raw={day:clean(cells[heads.index(day)]) for day in days};intervals=[];verified=True
            for day,text in raw.items():
                parsed=windows(days.index(day)+1,text);intervals+=parsed
                if text.lower()!='n/a' and not parsed:verified=False
            location=clean(cells[heads.index('Location')]);result[name]={'fields':{'Location:':location},'schedule':intervals,'companion':{'scheduled':True,'scheduleVerified':verified,'location':location,'weekly':raw},'metadataVersion':2}
    for name,data in result.items():
        match=next((values for singular,values in sorted(species,key=lambda pair:-len(pair[0])) if singular.lower() in name.lower()),None)
        if match:data['fields'].update(match)
    return result

def fish_details(title,doc,base):
    fields=fields_of(doc)
    paragraphs=[clean(p) for p in doc.select('.mw-parser-output > p') if clean(p)]
    # The lead paragraphs contain catch conditions; later recipe/placement/quest discussion is kept out of the condition panel.
    leads=[]
    for paragraph in paragraphs:
        if paragraph.startswith(('It can be consumed','Ingredients can be placed','Once collected')):break
        leads.append(paragraph)
    lead='\n\n'.join(leads[:5]);notes=base.get('notes','')
    location=fields.get('Found:',base.get('locations','Unknown'))
    weather=fields.get('Weather:') or ('Rain' if re.search(r'\brain(?:ing)?\b',lead+' '+notes,re.I) else 'No weather restriction listed')
    time_phrases=[clean(p) for p in doc.select('.mw-parser-output > p') if re.search(r'\d\s*(?:am|pm)|morning|evening|night|between.*(?:hour|time)',clean(p),re.I)]
    time_text=fields.get('Time:') or fields.get('Available:') or '\n'.join(time_phrases[:2]) or 'No time restriction listed'
    return {'fields':fields,'image':hero(doc),'blocks':[{'type':'p','text':p} for p in paragraphs[:8]],'links':[],'schedule':[],'summary':False,'metadataVersion':2,'fetchedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'fishing':{'ripples':fields.get('Ripple Color:',base.get('ripples','Unknown')),'weather':weather,'time':time_text,'locations':location,'conditions':'\n\n'.join(s for s in [notes,lead] if s),'source':'https://dreamlightvalleywiki.com/'+urllib.parse.quote(title.replace(' ','_'))}}

def fishing_index(doc):
    result={}
    for table in doc.select('table'):
        rows=table.select('tr');heads=[clean(c) for c in rows[0].find_all(['th','td'],recursive=False)] if rows else []
        if 'Ripples' not in heads or 'Name' not in heads:continue
        for row in rows[1:]:
            cells=row.find_all('td',recursive=False)
            if len(cells)<len(heads):continue
            link=cells[heads.index('Name')].select_one('a[title]')
            if not link:continue
            result[link['title']]={k.lower():clean(cells[heads.index(k)]) for k in ['Ripples','Locations','Notes'] if k in heads}
    return result

def build(refresh):
    snapshot=json.loads((ROOT/'assets/catalog.json').read_text(encoding='utf-8-sig'));records={r['id']:r for r in snapshot['records']}; failures=[]
    if refresh:
        hub=page('Collections');sources=[a['data-ct-section'] for a in hub.select('.ct-hub-card[data-ct-section]')]
        for source in sources:
            try:
                doc=page('Collections/'+source);items=doc.select('.ct-item[data-ct-pid]')
                if not items:raise ValueError('Unknown collection structure')
                for item in items:
                    key=item['data-ct-pid'];name=item['data-ct-name'];area=item.get('data-ct-area','Unknown');image=item.select_one('img');url=urllib.parse.urljoin('https://dreamlightvalleywiki.com',image['src']) if image else None
                    old=records.get(key);categories=set(json.loads(old['categories']) if old else []);categories.update([source,area])
                    details=json.loads(old['details']) if old else {'fields':{'Collection:':source,'Location / DLC:':area},'summary':True,'blocks':[],'links':[],'schedule':[]}
                    records[key]={'id':key,'title':name,'categories':json.dumps(sorted(categories)),'details':json.dumps(details),'image':url}
                print(source,len(items),flush=True)
            except Exception as error:failures.append(f'{source}: {error}')
        snapshot['sources']=sources
    info=critters(page('Critters'));fish=fishing_index(page('Fishing'))
    if len(info)<80 or len(fish)<60:raise RuntimeError('Activity tables changed; retain the previous published feed')
    crop_list=[dict(c,image=c.get('imageSource',c['image'])) for c in json.loads((ROOT/'assets/crops.json').read_text(encoding='utf-8'))]
    if refresh:
        crop_doc=page('Ingredients')
        discovered=[]
        for table in crop_doc.select('table'):
            rows=table.select('tr');heads=[clean(h).lower() for h in rows[0].find_all('th',recursive=False)] if rows else []
            if 'sources' not in heads or 'name' not in heads:continue
            for row in rows[1:]:
                cells=row.find_all('td',recursive=False)
                if len(cells)<len(heads):continue
                if not any(a.get('title','').endswith(' Seed') for a in cells[heads.index('sources')].select('a[title]')):continue
                link=cells[heads.index('name')].select_one('a[title]');image=cells[0].select_one('img')
                if link and image:discovered.append({'name':link['title'],'image':urllib.parse.urljoin('https://dreamlightvalleywiki.com',image['src']),'location':clean(cells[heads.index('location')]),'growth':clean(cells[heads.index('grow time')])})
        if not discovered:raise RuntimeError('Ingredient table changed')
        crop_list=discovered
        # Refresh at most five individual fish pages per run; all table sources plus this budget stay below the API's hourly quota.
        fish_rows=[r for r in records.values() if 'Fish' in json.loads(r['categories'])]
        fish_rows.sort(key=lambda r:json.loads(r['details']).get('fishRefreshedAt',''))
        for row in fish_rows[:5]:page(row['title'])
    snapshot['plantableCrops']=crop_list
    for row in records.values():
        details=json.loads(row['details']);name=row['title'];categories=json.loads(row['categories'])
        row.setdefault('image',details.get('image'))
        if name in info:
            addition=info[name];details.update({k:v for k,v in addition.items() if k!='fields'});details.setdefault('fields',{}).update(addition['fields'])
        elif 'Companions' in categories:
            details['companion']={'scheduled':False,'scheduleVerified':False,'location':'Not a scheduled wild critter','weekly':{}}
        if 'Fish' in categories:
            try:
                cached=CACHE/(re.sub(r'[^A-Za-z0-9_-]','_',name)+'.html')
                base=fish.get(name,{})
                if cached.exists():
                    details.update(fish_details(name,BeautifulSoup(cached.read_text(encoding='utf-8'),'html.parser'),base));details['fishRefreshedAt']=datetime.datetime.fromtimestamp(cached.stat().st_mtime,datetime.timezone.utc).isoformat()
                else:
                    notes=base.get('notes','')
                    previous=details.get('fishing',{})
                    details['fishing']={**previous,'ripples':base.get('ripples',previous.get('ripples','Unknown')),'locations':base.get('locations',previous.get('locations','Unknown')),'weather':'Rain' if re.search(r'\brain',notes,re.I) else previous.get('weather','No weather restriction listed'),'time':notes if re.search(r'\d\s*(?:am|pm)',notes,re.I) else previous.get('time','No time restriction listed'),'conditions':'\n\n'.join(dict.fromkeys(v for v in [notes,previous.get('conditions','')] if v)),'source':'https://dreamlightvalleywiki.com/Fishing'}
                    details['metadataVersion']=2
                fish_info=details['fishing']
                ranges=re.findall(r'(\d{1,2}(?::\d{2})?\s*(?:am|pm))\s*(?:-|–|to|and)\s*(\d{1,2}(?::\d{2})?\s*(?:am|pm))',fish_info.get('time',''),re.I)
                if ranges:fish_info['timeNotes']=fish_info['time'];fish_info['time']='; '.join(a+' – '+b for a,b in ranges)
                print('Fish conditions:',name,flush=True)
            except Exception as error:failures.append(f'{name}: {error}');details.setdefault('fishing',fish.get(name,{}))
        if name=='Acorn Lantern':
            try:
                cached=ROOT/'build/research-current/Acorn_Lantern.html'
                if cached.exists():details['image']=hero(BeautifulSoup(cached.read_text(encoding='utf-8-sig'),'html.parser'))
                details['metadataVersion']=2
            except Exception:pass
        row['details']=json.dumps(details,ensure_ascii=False)
    snapshot.update({'schemaVersion':2,'generatedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'failures':failures,'records':list(records.values())})
    enrich(snapshot,page)
    text=json.dumps(snapshot,ensure_ascii=False,separators=(',',':'))
    (ROOT/'assets/catalog.json').write_text(text,encoding='utf-8');(ROOT/'data').mkdir(exist_ok=True)
    with open(ROOT/'data/catalog.json.gz','wb') as output:output.write(gzip.compress(text.encode('utf-8'),mtime=0))
    print('Catalog:',len(records),'Scheduled companions:',len(info),'Fish:',sum('Fish' in json.loads(r['categories']) for r in records.values()),'Failures:',failures,flush=True)
    if failures:raise SystemExit('Incomplete source refresh; inspect source failures before publishing')

if __name__=='__main__':
    args=argparse.ArgumentParser();args.add_argument('--refresh-collections',action='store_true');build(args.parse_args().refresh_collections)
