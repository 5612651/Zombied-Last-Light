"""Record the actual source state used for a run or package."""
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import sys

root=Path(__file__).resolve().parents[1]
files=[root/"project.godot",root/"export_presets.cfg"]
for folder in ["scripts","shaders","data","scenes"]:
    files.extend(path for path in (root/folder).rglob("*") if path.is_file() and path.suffix!=".uid")
records={str(path.relative_to(root)).replace("\\","/"):hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(files) if path.exists()}
output=Path(sys.argv[1]) if len(sys.argv)>1 else root/"artifacts"/"source-manifest.json"
output.parent.mkdir(parents=True,exist_ok=True)
output.write_text(json.dumps({"recorded_at":datetime.now(timezone.utc).isoformat(),"sha256":records},indent=2),encoding="utf-8")
print(str(output))
