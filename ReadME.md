# Tappy

Turn your phone into a wireless mouse and keyboard for your laptop  no cables, no accounts, works entirely over your local Wi-Fi.

## Download

👉 **[tappyremote.vercel.app](https://tappyremote.vercel.app/)** — get the Windows server and Android app from here.

<details>
<summary>Direct file links (v1.0.0)</summary>

| Platform | File |
|---|---|
| 🖥️ Windows | [server.exe](https://github.com/Adtkre/tappy/releases/download/v1.0.0/server.exe) |
| 📱 Android | [app-release.apk](https://github.com/Adtkre/tappy/releases/download/v1.0.0/app-release.apk) |

</details>

## How it works

1. **Run `server.exe` on your laptop.** A small window pops up showing your laptop's local IP and a status message. Keep it open.
2. **Open the Tappy app on your phone.** It listens for laptops broadcasting on the same Wi-Fi network and lists them automatically — or you can enter the IP shown on the laptop window manually.
3. **Tap to connect.** Once connected, your phone becomes a trackpad and keyboard for the laptop. Move, click, scroll, and type from across the room.
4. **Disconnect anytime** — either from the phone, the "Disconnect" button on the laptop window, or by just closing the laptop app.

Only one phone can be connected at a time, and the laptop is never controllable unless the desktop app is open and running.

## Architecture

```
┌────────────────────┐        Wi-Fi (LAN only)        ┌──────────────────────┐
│   Android App       │ ───────────────────────────── │   Windows Server      │
│   (Flutter)          │   UDP broadcast: discovery    │   (Python + Flask)    │
│                      │   HTTP: /connect /move /click │                       │
│                      │         /scroll /type          │  pyautogui → OS input │
└────────────────────┘        /disconnect /ping        └──────────────────────┘
```

- **Desktop server** (`server.py`): a Flask HTTP server paired with a small Tkinter status window. It broadcasts its presence over UDP (`TAPPY_SERVER:<ip>|<hostname>`) every 2 seconds on port `5051`, and exposes HTTP routes on port `5000` for connecting, moving the cursor, clicking, scrolling, and typing. Mouse/keyboard actions are performed with `pyautogui`.
- **Mobile app** (`remote_control_app/`): a Flutter app that discovers laptops on the LAN, connects to the chosen one, and sends touch/gesture input to the server's HTTP routes.

## Running from source

**Server**
```bash
cd remote_server
pip install -r requirements.txt
python server.py
```

**Mobile app**
```bash
cd remote_server/remote_control_app
flutter pub get
flutter run
```

To build the Windows executable yourself:
```bash
pyinstaller server.spec
```

## Requirements

- Laptop and phone must be on the **same Wi-Fi network**.
- Windows Defender / Firewall may prompt to allow `server.exe` network access on first run - allow it, or the app won't be discoverable.
- Android device with the APK installed (enable "install from unknown sources" if prompted, since it's not from the Play Store).

## Notes

- All communication stays on your local network nothing is sent to the internet.
- Closing the laptop window immediately ends the session; the phone will show as disconnected on its next action.

## License

Personal project — use at your own discretion.