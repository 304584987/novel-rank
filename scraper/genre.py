"""统一题材归类：用 AI 按书名+故事核批量归入统一题材，写入 book['genre']，缓存在 data/genre_cache.json。"""
import os, json, requests
from summarize import BASE, MODEL, KEY, bkey
GENRES=["都市","玄幻","仙侠","武侠","历史","科幻","悬疑","奇幻","游戏","同人衍生","古言","现言","纯爱","其他"]
def classify(books):
    lines="\n".join(f"{i}. {b['title']}｜{b.get('cat') or ''}｜{(b.get('core') or b.get('intro') or '')[:120]}" for i,b in enumerate(books))
    prompt=(f"把下列小说各归入一个题材，只能从这些里选：{'、'.join(GENRES)}。女频古代言情选古言、现代言情选现言、男男选纯爱。"
            '只输出 JSON 对象，如 {"0":"都市","1":"玄幻"}。\n'+lines)
    r=requests.post(BASE.rstrip("/")+"/chat/completions",headers={"Authorization":f"Bearer {KEY}"},timeout=180,
        json={"model":MODEL,"temperature":0,"response_format":{"type":"json_object"},"messages":[{"role":"user","content":prompt}]})
    r.raise_for_status(); return json.loads(r.json()["choices"][0]["message"]["content"])
def add_genres(sites, cache_path):
    cache=json.load(open(cache_path)) if os.path.exists(cache_path) else {}
    todo={}
    for s in sites:
        for l in s["lists"]:
            for b in l["books"]:
                if b.get("title") and bkey(b) not in cache: todo[bkey(b)]=b
    items=list(todo.items())
    if KEY:
        for i in range(0,len(items),40):
            chunk=items[i:i+40]
            try:
                res=classify([b for _,b in chunk])
                for j,(k,_) in enumerate(chunk):
                    g=res.get(str(j)); cache[k]=g if g in GENRES else "其他"
            except Exception as e: print("题材归类失败",e)
    for s in sites:
        for l in s["lists"]:
            for b in l["books"]:
                if b.get("title"): b["genre"]=cache.get(bkey(b)) or "其他"
    json.dump(cache,open(cache_path,"w"),ensure_ascii=False,indent=0)
    print("题材归类新增",len(items) if KEY else 0)
if __name__=="__main__":  # 给现有数据补题材
    import glob
    root=os.path.join(os.path.dirname(__file__),"..","data")
    for p in [os.path.join(root,"latest.json")]+glob.glob(os.path.join(root,"archive","*.json")):
        d=json.load(open(p)); add_genres(d["sites"],os.path.join(root,"genre_cache.json"))
        json.dump(d,open(p,"w"),ensure_ascii=False,indent=1)
