# Phone (rust-connect) for Omarchy

An Omarchy bar widget for your phone. It talks to
[rust-connect](https://github.com/georgeglarson/rust-connect), a headless
KDE Connect–compatible daemon, so it works with the stock KDE Connect app on
your phone.

- Phone icon and battery level in the bar (highlighted for a pairing request or low battery)
- Pairing requests with the verification code and Accept/Decline, plus a desktop notification
- Ring the phone, ping it, send files (desktop file chooser), send the clipboard
- Phone notifications in the panel: dismiss (also on the phone), clear all, and reply where the app supports it
- Device list with Pair/Unpair
- On/off switch for the rust-connect service

Clipboard sync, desktop popups for phone notifications, and received files
are handled by the daemon itself. To stop notifications from a phone app,
turn them off per app in the KDE Connect app's notification sync settings.

## Requirements

1. **rust-connect** running as a user service:
   ```sh
   git clone https://github.com/georgeglarson/rust-connect.git
   cd rust-connect && packaging/install-user-service.sh
   ```
2. **Firewall:** KDE Connect uses ports 1714–1764. On Omarchy (ufw):
   ```sh
   sudo ufw allow 1714:1764/udp && sudo ufw allow 1714:1764/tcp
   ```
3. `curl`, `jq` and `wl-clipboard` (already on Omarchy).
4. Don't run KDE Connect or Valent at the same time; they take the same ports.

## Install

```sh
omarchy plugin add https://github.com/tudisco/omarchy-rust-connect.git --enable
```

Then open KDE Connect on your phone (same network), pick this computer,
and accept the request from the bar panel.

## Usage

| Bar icon | Action |
|---|---|
| Left click | Open the panel |
| Right click | Send files to the connected phone |
| Middle click | Ring the phone |

In the panel: `R` ring, `F` send files, `C` send clipboard, `P` ping.

Shell IPC, for Hyprland binds:

```sh
omarchy-shell rconnect.panel toggle
omarchy-shell rconnect.panel ring
omarchy-shell rconnect.panel sendFiles
omarchy-shell rconnect.panel sendClipboard
omarchy-shell rconnect.panel status
omarchy-shell rconnect.panel notifications   # how many are listed
```

`bin/rconnect-api` is the small client the panel uses. It also works on its
own (`bin/rconnect-api get /api/v1/devices`). It reads the API key from
`~/.local/share/rust-connect/api_key` and passes it to curl through a file
descriptor, so the key never appears in the process list.

## Settings

- **Show phone battery in the bar** (`showBattery`, default on)
- **Desktop notification for pairing requests** (`notifyPairRequests`, default on)

Override the API location with `RCONNECT_API_URL` (default
`http://127.0.0.1:9090`) and `RCONNECT_API_KEY_FILE`.

## Development

```sh
ln -sfn "$PWD" ~/.config/omarchy/plugins/rconnect-panel
omarchy-shell shell rescanPlugins
omarchy plugin enable rconnect.panel
node tests/model.test.mjs
omarchy plugin validate .
```

The shell only hot-reloads plugin folders that live inside `~/.config`. With
the symlink above, run `omarchy restart shell` after editing.

## License

MIT. rust-connect itself is GPL-2.0+ and is not included here; this plugin
only talks to its local HTTP API.
