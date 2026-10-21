#!/usr/bin/python3
"""Render mock authentication states on an isolated, headless compositor."""
from pathlib import Path
import os, shutil, subprocess, tempfile
source=Path(__file__).resolve().parent
trial=Path(tempfile.mkdtemp(prefix='polkit-dialog-preview-'))
home=trial/'home'; home.mkdir(); runtime=trial/'run';runtime.mkdir(mode=0o700)
qml=(source/'PolkitAgent.qml').read_text()
a=qml.index('  PolkitAgent {');b=qml.index('\n  Connections {',a)
qml=qml[:a]+'  QtObject { id: polkitAgent; property var flow: null }\n'+qml[b:]
a=qml.index('  FileView {');b=qml.index('\n  Process {',a);qml=qml[:a]+qml[b:]
qml=qml.replace('readonly property bool dialogVisible: polkitAgent.isActive || closing','readonly property bool dialogVisible: true')
qml=qml.replace('property string currentMessage: ""','property string currentMessage: "Authentication is required to install software as administrator."')
commands=[]
for mode in ('fingerprint','password','error'):
 d=home/mode;d.mkdir()
 (d/'Commons').symlink_to('/usr/share/omarchy/shell/Commons');(d/'Ui').symlink_to('/usr/share/omarchy/shell/Ui')
 shutil.copy2(source/'PolkitModel.js',d/'PolkitModel.js')
 s=qml.replace('property bool fingerprintConfigured: false','property bool fingerprintConfigured: '+str(mode=='fingerprint').lower()).replace('property bool responseRequired: false','property bool responseRequired: '+str(mode!='fingerprint').lower()).replace('property bool errorFlash: false','property bool errorFlash: '+str(mode=='error').lower())
 (d/'Auth.qml').write_text(s);(d/'shell.qml').write_text('import Quickshell\nShellRoot { Auth {} }\n')
 commands.append(f'quickshell --no-color -p "$HOME/{mode}" >"$HOME/{mode}.log" 2>&1 & p=$!; sleep 2; grim "$HOME/{mode}.png"; kill "$p"; wait "$p" || true')
(home/'run.sh').write_text('#!/bin/sh\n'+'\n'.join(commands)+'\nswaymsg exit\n')
(home/'sway.conf').write_text('output * mode 1280x800\nexec /bin/sh "$HOME/run.sh"\n')
env=os.environ.copy();env.update(QT_QPA_PLATFORM='wayland',QT_QUICK_BACKEND='software',XDG_CURRENT_DESKTOP='sway',WLR_BACKENDS='headless',WLR_RENDERER='pixman',WLR_LIBINPUT_NO_DEVICES='1')
for key in ('DBUS_SESSION_BUS_ADDRESS','WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE'):env.pop(key,None)
cmd=['timeout','18','bwrap','--ro-bind','/','/','--bind',str(home),str(Path.home()),'--bind',str(runtime),env['XDG_RUNTIME_DIR'],'--tmpfs','/tmp','--tmpfs','/run/dbus','--proc','/proc','--dev','/dev','--unshare-pid','--unshare-net','--die-with-parent','dbus-run-session','--','sway','-c',str(Path.home()/'sway.conf')]
r=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);(trial/'compositor.log').write_text(r.stdout)
print(trial)
for mode in ('fingerprint','password','error'):
 log=(home/(mode+'.log')).read_text()
 bad=[l for l in log.splitlines() if any(t in l for t in ('TypeError:','ReferenceError:','Failed to load','caused by @'))]
 assert not bad,bad
 assert (home/(mode+'.png')).is_file(),mode
assert r.returncode==0,r.returncode
