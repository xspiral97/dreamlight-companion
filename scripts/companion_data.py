"""Verified feeding and acquisition metadata from wiki tables and page revisions."""
import re,json,urllib.parse,datetime
from bs4 import BeautifulSoup
BASE='https://dreamlightvalleywiki.com'

def clean(value):
    clone=BeautifulSoup(str(value),'html.parser')
    for node in clone.select('sup.reference,.mw-editsection'):node.decompose()
    return re.sub(r'\s+',' ',clone.get_text(' ',strip=True)).strip()

def expand_rows(table):
    carried={}
    for row in table.select('tr'):
        cells=[];position=0;next_carried={}
        def carry():
            nonlocal position
            node,left=carried[position];cells.append(node)
            if left>1:next_carried[position]=(node,left-1)
            position+=1
        for cell in row.find_all(['td','th'],recursive=False):
            while position in carried:carry()
            cells.append(cell)
            if int(cell.get('rowspan','1'))>1:next_carried[position]=(cell,int(cell['rowspan'])-1)
            position+=1
        while position in carried:carry()
        carried=next_carried
        yield cells

def feeding_data(doc):
    result={}
    aliases={'Crocodiles':'Crocodile','Foxes':'Fox','Geese':'Goose','Pegasi':'Pegasus','Baby Dragons':'Baby Dragon','Sweet Bees':'Sweet Bee'}
    for table in doc.select('table'):
        rows=list(expand_rows(table))
        heads=[clean(c) for c in rows[0]] if rows else []
        if not {'Name','Favorite Food','Liked Food','Feeding Method'}.issubset(heads):continue
        for cells in rows[1:]:
            if len(cells)!=len(heads):raise ValueError('Feeding table changed')
            name=clean(cells[heads.index('Name')]);singular=aliases.get(name,name[:-1] if name.endswith('s') else name)
            result[singular]={'favorite':clean(cells[heads.index('Favorite Food')]),'liked':clean(cells[heads.index('Liked Food')]),'feedingMethod':clean(cells[heads.index('Feeding Method')]),'foodSource':BASE+'/Critters'}
    return result

def wiki_text(value):
    value=value.replace('{{!}}','|')
    for _ in range(8):
        def template(m):
            parts=m[1].split('|');name=parts[0].strip().lower()
            if name in ['name','quest','event','collection']:return parts[1] if len(parts)>1 else ''
            if name=='price':return parts[1] if len(parts)>1 else ''
            return ''
        updated=re.sub(r'\{\{([^{}]*)\}\}',template,value)
        if updated==value:break
        value=updated
    value=re.sub(r'\[\[(?:[^\]|]*\|)?([^\]]+)\]\]',r'\1',value)
    return clean(value.replace("'''",'').replace("''",''))

def acquisition(content):
    # Only the infobox and lead determine acquisition; ignore navigation/history/reward discussions.
    lead=re.split(r'^==',content,maxsplit=1,flags=re.M)[0]
    box=re.search(r'\{\{infobox\b(.*?)^\}\}',lead,re.I|re.S|re.M)
    fields=dict((m[1].lower(),m[2].strip()) for m in re.finditer(r'^\|([A-Za-z]\w*)=(.*?)(?=^\|[A-Za-z]\w*=|\Z)',box[1],re.M|re.S)) if box else {}
    source=fields.get('from','');description=wiki_text(source)
    tags=[]
    if 'premium shop' in source.lower():tags.append('Premium')
    if 'star path' in source.lower():tags.append('Star Path')
    if re.search(r'Edition|Founder.s Pack|Charity Bundle',source,re.I):tags.append('Premium · Edition / Bundle')
    if not tags:
        if fields.get('craftingcategory'):tags=['Crafting'];description='Craft at a Timebending Table' if 'Timebending Table' in lead else 'Crafting'
        elif fields.get('unlockquest') or '{{quest|' in fields.get('reward','').lower() or 'quest companion' in wiki_text(lead).lower() or 'quest_reward_companions' in lead.lower():
            tags=['Quest'];description=wiki_text(fields.get('unlockquest') or fields.get('reward') or fields.get('found','')) or 'Quest reward'
        elif 'exhibition' in fields.get('reward','').lower():tags=['Quest'];description=wiki_text(fields['reward'])
        elif source:tags=['Event / Promotion']
        else:tags=['Unknown'];description='Unknown'
    return {'tags':tags,'description':description or 'Unknown'}

def gardening_data(doc):
    result=[]
    for table in doc.select('table'):
        rows=table.select('tr');heads=[clean(c) for c in rows[0].find_all(['td','th'],recursive=False)] if rows else []
        if not {'Name','Native Biome','Grow Time','Seed Price'}.issubset(heads):continue
        for row in rows[1:]:
            cells=row.find_all(['td','th'],recursive=False)
            if len(cells)<len(heads):continue
            image=cells[0].select_one('img');name=clean(cells[heads.index('Name')])
            if not image:raise ValueError('Missing crop image: '+name)
            result.append({'name':name,'image':urllib.parse.urljoin(BASE,image['src']),'imageSource':urllib.parse.urljoin(BASE,image['src']),'source':BASE+'/Gardening','location':clean(cells[heads.index('Native Biome')]),'growth':clean(cells[heads.index('Grow Time')]),'availability':clean(cells[heads.index('Availablility')]) if 'Availablility' in heads else 'Regular crop'})
    if len(result)<58 or len({r['name'] for r in result})!=len(result):raise ValueError('Incomplete or duplicated gardening table')
    return result

def enrich_companions(snapshot,critters_doc,revisions):
    foods=feeding_data(critters_doc);counts={};now=datetime.datetime.now(datetime.timezone.utc).isoformat()
    for row in snapshot['records']:
        if 'Companions' not in json.loads(row['categories']):continue
        details=json.loads(row['details']);info=details.setdefault('companion',{});fields=details.setdefault('fields',{})
        if info.get('scheduled'):
            match=next((v for n,v in sorted(foods.items(),key=lambda p:-len(p[0])) if n.lower() in row['title'].lower()),None)
            if not match:raise ValueError('No verified food for '+row['title'])
            info.update(match);fields.update({'Favorite food:':match['favorite'],'Liked food:':match['liked'],'Feeding method:':match['feedingMethod']})
            method={'tags':['Base game' if 'Dreamlight Valley' in json.loads(row['categories']) else 'DLC'],'description':'Unlock by feeding this wild critter'}
        else:
            content=revisions.get(row['title'],'')
            method=acquisition(content)
            if method['tags']==['Unknown']:raise ValueError('Unknown acquisition source: '+row['title'])
        method['source']=BASE+'/'+urllib.parse.quote(row['title'].replace(' ','_'));method['updatedAt']=now
        info['acquisition']=method;fields['How to obtain:']=method['description'];details['metadataVersion']=5
        counts[method['tags'][0]]=counts.get(method['tags'][0],0)+1
        row['details']=json.dumps(details,ensure_ascii=False)
    snapshot['referenceVersion']=5
    print('Verified companion acquisition:',counts,flush=True)
    return snapshot
