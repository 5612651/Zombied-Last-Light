"""Create an immutable local playtest ZIP from the exported files, without QA claims."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

parser=argparse.ArgumentParser()
parser.add_argument('--name',default='Zombied_Chapter01_Playtest_v2.zip')
args=parser.parse_args()
if Path(args.name).name!=args.name or not args.name.lower().endswith('.zip'):
    parser.error('--name must be a ZIP filename')
root=Path(__file__).resolve().parents[1]
folder=root/'builds/playtest-windows'
archive=root/'builds'/args.name
if archive.exists():
    raise FileExistsError(f'Preserving existing package: {archive}. Choose a new versioned name.')
names=['Zombied.exe','Zombied.pck','README.txt','FEEDBACK.txt','EXTERNAL_PLAYTEST.md',
       'Performance Test.cmd','GODOT_LICENSE.txt','GODOT_COPYRIGHT.txt',
       'package-hashes.json','source-manifest.json']
if (folder/'FONT_OFL.txt').exists():
    names.append('FONT_OFL.txt')
if (folder/'Weapon Lab.cmd').exists():
    names.append('Weapon Lab.cmd')
for name in names:
    if not (folder/name).is_file():
        raise FileNotFoundError(folder/name)
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as output:
    for name in names:
        output.write(folder/name,'Zombied_Playtest/'+name)
with zipfile.ZipFile(archive) as output:
    assert output.testzip() is None
    assert len(output.namelist())==len(names)
with archive.open('rb') as stream:
    digest=hashlib.file_digest(stream,'sha256').hexdigest()
report={'path':str(archive),'bytes':archive.stat().st_size,'sha256':digest,'files':names,
        'pack_sha256':hashlib.sha256((folder/'Zombied.pck').read_bytes()).hexdigest(),
        'scope':'Packaging and archive integrity only. Runtime, chapter and external-player acceptance require separate evidence.'}
(root/'artifacts'/(archive.stem+'-report.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report))
