#!/usr/bin/env python3
import pathlib,sys,zipfile,tarfile,io,shutil
root=pathlib.Path(sys.argv[1]);root.mkdir(parents=True,exist_ok=True)
for name in ['Documents','Images','Dossier vide']:(root/name).mkdir(exist_ok=True)
(root/'Documents'/'Bonjour.txt').write_text('Prévisualisation locale depuis un dossier.\n',encoding='utf8')
(root/'Documents'/'Informations.json').write_text('{"application":"Folder Preview Droplet","local":true}',encoding='utf8')
(root/'Images'/'Courbe.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="640" height="480"><rect width="640" height="480" rx="32" fill="#0d2340"/><path d="M60 340 C180 20 440 500 580 100" stroke="#65ceff" stroke-width="22" fill="none"/><circle cx="60" cy="340" r="25" fill="#ff887d"/></svg>')
(root/'Lisez-moi.txt').write_text('Utilisez Espace dans Finder. Le menu ⚙︎ en bas permet de basculer entre liste et icônes.\n')
(root/'Données.csv').write_text('nom,valeur\nAlpha,12\nBêta,24\n')
with zipfile.ZipFile(root/'Exemple.zip','w',compression=zipfile.ZIP_DEFLATED) as z:
 z.writestr('Documents/Bonjour.txt','Bonjour depuis une archive.');z.writestr('Images/Courbe.svg',(root/'Images'/'Courbe.svg').read_bytes());z.writestr('Lisez-moi.txt','Une archive peut aussi être affichée en liste ou en icônes.')
if '--tests' in sys.argv:
 with zipfile.ZipFile(root/'hostile.zip','w') as z:
  for name in ['../escape.txt','/absolute.txt','a/../../bad.txt','ok/fichier2.txt']:z.writestr(name,'test')
  z.writestr('large.txt',b'A'*(51*1024*1024),compress_type=zipfile.ZIP_DEFLATED)
 sample=root/'sample';sample.mkdir(exist_ok=True)
 (sample/'fichier2.txt').write_text('deux');(sample/'fichier10.txt').write_text('dix');(sample/'.hidden').write_text('masqué');(sample/'Sous-dossier').mkdir(exist_ok=True)
 (sample/'Sous-dossier'/'enfant.txt').write_text('enfant')
 if not (sample/'cycle').is_symlink():(sample/'cycle').symlink_to('.')
 for kind,mode in [('Exemple.tar','w'),('Exemple.tar.gz','w:gz'),('Exemple.tar.bz2','w:bz2'),('Exemple.tar.xz','w:xz')]:
  with tarfile.open(root/kind,mode) as archive:
   data=b'tar sample';info=tarfile.TarInfo('demo/texte.txt');info.size=len(data);archive.addfile(info,io.BytesIO(data))

for source,name in [("Images/Couleurs.png","Couleurs.png"),("Images/Courbe.svg","Courbe.svg"),("Documents/Exemple.pdf","Document.pdf"),("Documents/Exemple.rtf","Texte enrichi.rtf"),("Images/Video.mp4","Vidéo.mp4")]:
 if (root/source).exists():shutil.copy2(root/source,root/name)
