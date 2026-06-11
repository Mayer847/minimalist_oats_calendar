# Run Command Update

Replace your current helper scripts with these files:

```text
scripts/run_web_server.ps1
scripts/run_chrome.ps1
```

## Web server command now used

```powershell
flutter run -d web-server --web-port 8800 --dart-define=GOOGLE_CLIENT_ID=462452343506-csg26cgk1uvr2m4qf4p80l9kair8jf48.apps.googleusercontent.com
```

## Run helper

```powershell
powershell -ExecutionPolicy Bypass -File .\scriptsun_web_server.ps1
```
