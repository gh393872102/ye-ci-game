"""Render approved input records; keep all private material on the ephemeral runner."""
import base64
import time
import concurrent.futures
import functools
import json
import os
import re
import runpy
import subprocess
import sys
import threading
from pathlib import Path
from PIL import Image
ROOT = Path(os.environ["RUNNER_TEMP"])
IN = ROOT / "inputs"
OUT = ROOT / "results"
CLI = Path("tools/wan-style-pilot/image_gen.py").resolve()
LOCK = threading.Lock()
HALT = threading.Event()

def checkpoint():
    with LOCK:
        statuses = list(OUT.glob("*.status"))
        print(f"Checked {len(statuses)} records", flush=True)

def call_image(name, ref, prompt, dest, size, fmt, quality, identity=None):
    promptfile = ROOT / (name + ".prompt")
    promptfile.write_text(prompt)
    args = [sys.executable, __file__, "cli", "edit", "--image", str(ref), "--prompt-file", str(promptfile), "--model", "gpt-image-2", "--size", size, "--quality", quality, "--output-format", fmt, "--no-augment", "--out", str(dest)]
    if identity is not None:
        args.extend(["--image",str(identity)])
    if fmt == "jpeg":
        args.extend(["--output-compression", "95"])
    for delay in (0, 65, 130):
        if delay:
            time.sleep(delay)
        log = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if log.returncode == 0 or not ("429" in log.stdout and "rate_limit_exceeded" in log.stdout and "insufficient_quota" not in log.stdout):
            break
    if log.returncode:
        tags = re.findall(r"Error code: \d{3}|insufficient_quota|billing_hard_limit_reached|rate_limit_exceeded|moderation_blocked|invalid_image|invalid_api_key|model_not_found|invalid_size|unsupported_value|organization_verification_required|Request timed out", log.stdout, flags=re.I)
        reason = ",".join(dict.fromkeys(tags)) or "render_failed"
        if not tags or any(t in reason for t in ["401","403","429","billing","quota","invalid_size","unsupported_value","model_not_found","timed out"]):
            HALT.set()
        raise RuntimeError(reason)
    with Image.open(dest) as im:
        im.load()
        if im.size != tuple(map(int,size.split("x"))):
            raise RuntimeError("unexpected_dimensions")

def cut_sprite(source, target, height):
    im = Image.open(source).convert("RGBA")
    pixels=[]
    for r,g,b,a in im.getdata():
        if g > 64 and g - max(r,b) > 32:
            pixels.append((0,0,0,0))
        else:
            pixels.append((r,g,b,255))
    im.putdata(pixels)
    box=im.getbbox()
    if not box or (box[2]-box[0])>im.width*.99 or (box[3]-box[1])>im.height*.99:
        raise RuntimeError("sprite_matte_needs_review")
    im=im.crop(box)
    im=im.resize((max(1,round(height*im.width/im.height)),height),Image.Resampling.LANCZOS)
    mask=im.getchannel("A").point(lambda a: 255 if a>=140 else 0)
    rgb=im.convert("RGB").quantize(colors=36,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert("RGBA")
    rgb.putalpha(mask)
    canvas=Image.new("RGBA",(max(round(144*height/80),rgb.width+4),height+4))
    canvas.alpha_composite(rgb,((canvas.width-rgb.width)//2,2))
    canvas.save(target)

def render(row):
    code=row["id"]
    if not re.fullmatch(r"[HGTP]\d{2,3}",code):
        raise ValueError("record id invalid")
    status=OUT/(code+".status")
    art=OUT/(code+".jpg")
    raw=ROOT/(code+"-source.png")
    try:
        if HALT.is_set():
            raise RuntimeError("not_started")
        art_prompt=(IN/"art.txt").read_text()+"\n"+row["kind"]+" | "+row["name"]+" | "+row["brief"]
        identity=None
        if row.get("guide"):
            identity=ROOT/(code+"-guide.jpg")
            identity.write_bytes(base64.b64decode(row["guide"],validate=True))
            art_prompt+=" First image sets painting medium, lighting and palette only. The second image supplies this unit's own identity: preserve gender, face or ghost anatomy, signature prop, age group, and adapt clothing to the new painting. Omit interface, existing emblems and old framing."
        call_image(code+"-a",IN/"style.jpg",art_prompt,art,"2160x3840","jpeg","high",identity)
        if HALT.is_set():
            raise RuntimeError("sprite_not_started")
        sprite_prompt=(IN/"sprite.txt").read_text()+"\n"+row["name"]+" | "+row["brief"]
        ref=ROOT/(code+"-ref.jpg")
        with Image.open(art) as im:
            im.thumbnail((900,1400))
            im.save(ref,quality=90)
        call_image(code+"-s",ref,sprite_prompt,raw,"1024x1024","png","medium")
        cut_sprite(raw,OUT/(code+".png"),row["height"])
        result="ok"
    except Exception as e:
        if raw.is_file() and not (OUT/(code+".png")).exists():
            raw.rename(OUT/(code+"-matte.png"))
        result=str(e) if isinstance(e,RuntimeError) else type(e).__name__
    status.write_text(result)
    checkpoint()
    return result

if __name__=="__main__":
    if len(sys.argv)>1 and sys.argv[1]=="cli":
        import openai
        openai.OpenAI=functools.partial(openai.OpenAI,max_retries=0,timeout=600)
        sys.argv=[str(CLI),*sys.argv[2:]]
        runpy.run_path(str(CLI),run_name="__main__")
    else:
        OUT.mkdir(exist_ok=True)
        rows=json.loads((IN/"jobs.json").read_text())
        if not 1<=len(rows)<=24 or len({r["id"] for r in rows})!=len(rows):
            sys.exit(2)
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            results=list(pool.map(render,rows))
        print("Records OK",results.count("ok"),"of",len(rows))
        for msg in sorted(set(results)-{"ok"}):
            print("Outcome",msg)
        sys.exit(0 if all(x=="ok" for x in results) else 1)
