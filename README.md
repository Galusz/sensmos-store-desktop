# Sensmos Store — desktop

Encrypted backup onto the disks of other [Sensmos](https://sensmos.com) node owners, from
Windows, Linux or macOS. Every file is encrypted on this machine before it leaves it; the person
hosting it receives a blob with a random name, and so does the backend that relays the bytes.

![Sensmos Store on Windows: folder tree, file list, and a track playing with its cover and tags](https://sensmos.com/assets/store-desktop.png)

**Test builds — there is no official release yet.** They come straight off the build machine and
are unsigned, so Windows SmartScreen and macOS Gatekeeper will both object.

- [Windows x64](https://github.com/Galusz/sensmos-store-desktop/releases/latest/download/sensmos-store-win-x64.zip)
  — unpack anywhere and run `SensmosStore.exe`. No installer.
- [Linux x64](https://github.com/Galusz/sensmos-store-desktop/releases/latest/download/sensmos-store-linux-x64.tar.gz)
  — unpack and run `sensmos-store`.
- [macOS](https://github.com/Galusz/sensmos-store-desktop/releases/latest/download/sensmos-store-macos.zip)
  — unpack and move the app wherever you keep them; open it through right-click → Open the first time.

User documentation: [sensmos.com/docs/backup](https://sensmos.com/docs/backup/).

## What you need first

A Sensmos account with a Store package. The wallet lives **only in the phone app** — this program
never holds one and cannot create an account, buy GALU, or sign anything with a wallet.

Pair it once: the computer shows a ten-character code, you type that code into the phone under
**Settings → Paired devices**, and the phone seals a token and the file key to this computer's own
public key. The parcel travels through the backend, which has nothing to open it with. You choose
what the computer may do and you can revoke it later from the same screen.

## What it does

- **Folders** — back at the top, folders under it, files below, like a file manager. Drag and drop
  anywhere in the window.
- **Watched folders** — point it at any number of local folders and it keeps them backed up:
  encrypted, one way. Deleting something on your disk never deletes the copy.
- **Previews** — pictures, and music and video played in place. Cover art and tags are read out of
  the file that was fetched anyway, so they cost no extra transfer.
- **Duplicates by content** — both candidates are read and hashed before anything is selected for
  deletion. Same name and same size only means they *might* match.
- **Transfers and log** — what went where, and whether it went straight to the host or through the
  backend.
- **Buy or grow the package** without reaching for the phone.
- **Four languages** — English, Polish, German and Portuguese, picked from the system.

## Build from source

Flutter 3.10 or newer.

```bash
flutter pub get
flutter test
flutter build windows --release     # or: linux / macos
```

Linux also needs the GTK toolchain plus `libmpv-dev` (the player) and
`libayatana-appindicator3-dev` (the tray icon); the exact package list is in
[`.github/workflows/build.yml`](.github/workflows/build.yml).

Linux and macOS cannot be cross-built — Flutter refuses outright — so the workflow builds all
three on GitHub runners. Pushing a `v*` tag attaches the packages to the release.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/main.dart` | the window: file list, folder tree, toolbar, purchase and settings screens |
| `lib/pairing.dart` | pairing with the phone, and where the token and file key are kept |
| `lib/session.dart` | the connection to the relay: uploads, downloads, the in-flight journal |
| `lib/backup.dart` | watched folders and their indexes |
| `lib/media.dart` | audio and video playback, cover art and tags |
| `lib/i18n.dart` | the four-language dictionary, including Polish three-form plurals |
| `lib/tray.dart` | tray icon and window state |
| `lib/dziennik.dart` | the transfer log |
| `shared/sensmos_store/` | crypto and the relay client — **the same package the phone app uses**, not a copy of it |

Comments in the source are in Polish; everything a user sees is translated.

## Known limitations

- The pairing parcel — the account token and the file key — is stored through
  `shared_preferences`, which on every platform means a plain file in the user profile. Anyone who
  can copy that file gets the account and can decrypt the files. Encrypting it behind a password
  is on the list and not built.
- Revoking the token stops the computer from reaching the backend, which is where every file list
  and every wrapped key comes from. It does not take back the file key it already received, so
  anything already downloaded stays readable.
- The file list is not paginated here yet; the phone app is.
