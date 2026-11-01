#!/usr/bin/env python3
"""Integration check: run after installing/enabling the companion extension."""
import pathlib,subprocess,datetime,time,json,sys
root=pathlib.Path(__file__).resolve().parents[1]
cases=[('Demo',11),('Demo/Documents',4),('Demo/Exemple.zip',3)]
results=[]
for relative,expected in cases:
    started=datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    process=subprocess.Popen(['qlmanage','-p',str(root/relative)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    passed=False
    try:
        for attempt in range(16):
            time.sleep(0.5)
            log=subprocess.run(['/usr/bin/log','show','--start',started,'--style','compact','--predicate','subsystem == "be.nicolasdellim.folderpreviewdroplet" AND category == "preview"'],capture_output=True,text=True,timeout=10)
            if f'Preview ready: {expected} direct items' in log.stdout:
                passed=True;break
    finally:
        process.terminate()
        try:process.wait(timeout=3)
        except subprocess.TimeoutExpired:process.kill();process.wait()
    results.append(dict(fixture=relative,expected=expected,passed=passed))
    print(('PASS' if passed else 'FAIL')+': Quick Look '+relative)
if len(sys.argv)>1:pathlib.Path(sys.argv[1]).write_text(json.dumps(results,indent=2))
sys.exit(0 if all(item['passed'] for item in results) else 1)
