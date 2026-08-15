# Windows Remote Server Skill 鎿嶄綔娴佺▼

杩欎唤娴佺▼鐢ㄤ簬鎶?`windows-remote-server` skill 鏀惧埌 GitHub锛屽悓鏃堕伩鍏嶆妸 SSH銆佸瘑鐮併€佺閽ョ瓑鏁忔劅淇℃伅鍐欒繘鑱婂ぉ妗嗘垨浠撳簱銆?
## 1. 鐩綍缁撴瀯

GitHub 閲屽簲璇ユ彁浜よ繖浜涙枃浠讹細

```text
skills/windows-remote-server/
  SKILL.md
  agents/openai.yaml
  references/operation-flow.md
  scripts/
    save_remote_profile.ps1
    invoke_remote.ps1
    transfer_remote.ps1
    remote_profile.ps1
    remote_exec.py
    transfer.py
```

涓嶈鎻愪氦杩欎簺鏈湴鏂囦欢锛?
```text
.codex-remote/
.env
*.pem
*.key
id_rsa*
*.credential.xml
```

## 2. 绗竴娆″噯澶?
鍦?Windows PowerShell 閲岃繘鍏ヤ綘鐨勪粨搴撴牴鐩綍锛?
```powershell
cd F:\codingmcp
```

瀹夎 Paramiko锛?
```powershell
python -m pip install --user paramiko
```

鍒涘缓涓€涓湰鍦版湇鍔″櫒 profile锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\save_remote_profile.ps1 -Profile my-server
```

鑴氭湰浼氳浣犲湪鏈満杈撳叆锛?
- SSH host
- SSH port
- SSH user
- 榛樿杩滅▼鐩綍锛屽彲鐣欑┖
- SSH private key path锛屽彲鐣欑┖
- 濡傛灉娌℃湁濉閽ワ紝浼氬脊鍑?Windows 鍑嵁杈撳叆妗嗚緭鍏?SSH 瀵嗙爜

淇濆瓨鍚庝細鐢熸垚锛?
```text
.codex-remote/profiles/my-server.env
.codex-remote/secrets/my-server.credential.xml
```

瀵嗙爜涓嶄細鍐欒繘 Markdown銆佽亰澶╂鎴?GitHub銆俙credential.xml` 浣跨敤 Windows 褰撳墠鐢ㄦ埛鐨?DPAPI 鍔犲瘑锛屽彧鑳芥湰鏈哄綋鍓嶇敤鎴疯В瀵嗐€?
## 3. 浠ュ悗鎬庝箞鍦ㄨ亰澶╅噷璋冪敤

浠ュ悗涓嶈鎶?SSH 鍜屽瘑鐮佸彂鍒拌亰澶╂銆傚彧闇€瑕佸憡璇?Codex锛?
```text
浣跨敤 $windows-remote-server
profile: my-server
浠诲姟: 杩涘叆榛樿鐩綍锛屽厛杩愯 pwd銆亀hoami銆乭ostname銆乴s -la锛岀劧鍚庡憡璇夋垜椤圭洰鍦ㄥ摢涓枃浠跺す
```

濡傛灉瑕佹寚瀹氳繙绋嬬洰褰曪細

```text
浣跨敤 $windows-remote-server
profile: my-server
remote dir: /data/USER_NAME/RankIR
浠诲姟: 鏌ョ湅鐩綍缁撴瀯锛屽垽鏂€庝箞瀹夎鐜
```

Codex 搴旇杩愯绫讳技鍛戒护锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "pwd && whoami && hostname && ls -la"
```

## 4. 鎵ц杩滅▼鍛戒护

鍩虹妫€鏌ワ細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "pwd && ls -la"
```

杩涘叆鏌愪釜鐩綍鎵ц锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "cd /data/project && pwd && ls -la"
```

闀垮懡浠ゅ缓璁啓鎴愭湰鍦板懡浠ゆ枃浠讹紝鍐嶆墽琛岋細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -CommandFile .\remote-command.sh
```

## 5. 涓婁紶鏂囦欢鍒版湇鍔″櫒

涓婁紶鍗曚釜鏂囦欢锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action upload -Local ".\local-file.txt" -Remote "/data/project/local-file.txt"
```

涓婁紶鏂囦欢澶癸細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action upload -Local ".\my-folder" -Remote "/data/project/my-folder"
```

瑕嗙洊杩滅▼鏂囦欢鍓嶏紝鍏堟鏌ヨ繙绋嬬洰鏍囷細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "ls -la /data/project"
```

## 6. 浠庢湇鍔″櫒涓嬭浇鏂囦欢

涓嬭浇鍗曚釜鏂囦欢锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action download -Remote "/data/project/result.txt" -Local ".\downloads\result.txt"
```

涓嬭浇鏂囦欢澶癸細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action download -Remote "/data/project/results" -Local ".\downloads\results"
```

澶ф枃浠跺す寤鸿鍏堝湪鏈嶅姟鍣ㄦ墦鍖咃細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "tar -czf /tmp/results.tgz -C /data/project results"
```

鐒跺悗涓嬭浇鍘嬬缉鍖咃細

```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\transfer_remote.ps1 -Profile my-server -Action download -Remote "/tmp/results.tgz" -Local ".\downloads\results.tgz"
```

## 7. 杩滅▼瀹夎鐜

鍏堟鏌ョ郴缁熷拰椤圭洰鏂囦欢锛?
```powershell
powershell -ExecutionPolicy Bypass -File .\skills\windows-remote-server\scripts\invoke_remote.ps1 -Profile my-server -Command "pwd && ls -la && uname -a && cat /etc/os-release 2>/dev/null || true && command -v python3 || true && command -v conda || true && command -v nvidia-smi || true"
```

Python `requirements.txt`锛?
```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -U pip
pip install -r requirements.txt
```

Conda `environment.yml`锛?
```bash
conda env create -f environment.yml
```

Node `package-lock.json`锛?
```bash
npm ci
```

涓嶈鐩存帴璁?Codex 鍋?`sudo apt install`銆侀噸鍚湇鍔″櫒銆佸垹闄ょ洰褰曟垨鏀归槻鐏銆傞渶瑕佽繖浜涙搷浣滄椂锛屽厛璁?Codex璇存槑椋庨櫓鍜屽叿浣撳懡浠わ紝鍐嶄汉宸ョ‘璁ゃ€?
## 8. 涓婁紶鍒?GitHub 鍓嶆鏌?
杩愯锛?
```powershell
git status --short
```

纭娌℃湁杩欎簺鏂囦欢鍑虹幇鍦ㄥ緟鎻愪氦鍒楄〃锛?
```text
.codex-remote/
.env
*.pem
*.key
id_rsa*
*.credential.xml
```

鍐嶆悳绱竴娆″父瑙佹晱鎰熶俊鎭細

```powershell
rg -n "REMOTE_PASSWORD|credential.xml|BEGIN OPENSSH PRIVATE KEY|BEGIN RSA PRIVATE KEY|password\s*=" .
```

濡傛灉鎼滅储缁撴灉鍙嚭鐜板湪璇存槑鏂囦欢鎴栬剼鏈彉閲忓悕閲岋紝涓嶅寘鍚湡瀹炲瘑鐮佹垨鐪熷疄绉侀挜鍐呭锛屾墠鍙互鎻愪氦銆?
## 9. 瀹夎鍒?Codex

濡傛灉杩欎釜 skill 鏄粠 GitHub 涓嬭浇涓嬫潵鐨勶紝鎶婃暣涓洰褰曞鍒跺埌 Codex skills 鐩綍锛?
```powershell
Copy-Item -Recurse -Force .\skills\windows-remote-server "$env:USERPROFILE\.codex\skills\windows-remote-server"
```

涔嬪悗鍦ㄦ柊瀵硅瘽閲岀洿鎺ヨ锛?
```text
浣跨敤 $windows-remote-server
profile: my-server
浠诲姟: ...
```

