import os, sys, json, datetime
sys.path.insert(0, os.path.dirname(__file__))
from scrape import scrape_all
from summarize import summarize
from genre import add_genres
root=os.path.join(os.path.dirname(__file__),"..","data")
os.makedirs(os.path.join(root,"archive"),exist_ok=True)
now=datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)+datetime.timedelta(hours=8)
sites=scrape_all(sys.argv[1:] or None)
summarize(sites, os.path.join(root,"cache.json"))
add_genres(sites, os.path.join(root,"genre_cache.json"))
for s in sites:
    for l in s["lists"]:
        for b in l["books"]: b.pop("abstract_in_page",None)
doc={"updated":now.strftime("%Y-%m-%d %H:%M")+" (北京时间)","sites":sites}
for p in ("latest.json", f"archive/{now:%Y-%m-%d}.json"):
    json.dump(doc,open(os.path.join(root,p),"w"),ensure_ascii=False,indent=1)
