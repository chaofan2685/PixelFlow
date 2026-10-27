# PixelFlow

Transfer files and text between devices using QR codes. **Fully local, no server involved** — built for offline, air-gapped, or account-averse situations.

- **Sender**: web page (any modern browser, runs on a computer)
- **Receiver**: native iOS app (recommended) or the web page (localhost / HTTPS only)

---

## Layout

```
PixelFlow/
├── send.html               # Sender (multi-code grid)
├── index.html              # Receiver · web fallback
├── qrcode.min.js           # QR generation (node-qrcode browser build)
├── sha256.js               # SHA-256 (pure JS, shared by both pages)
├── html5-qrcode.min.js     # Web scanning, vendored for offline use
└── PixelFlowReceiver/      # Receiver · native iOS app
    ├── PixelFlowReceiver.xcodeproj
    └── PixelFlowReceiver/
        ├── PixelFlowApp.swift
        ├── Protocol/PF2Frame.swift       # Frame parsing
        ├── Protocol/TransferStore.swift  # Chunk accumulation, verification, state
        ├── Camera/CameraController.swift # Multi-code detection
        ├── Camera/CameraPreview.swift    # Preview + detection boxes
        └── Views/                        # UI and export
```

## Quick start

### 1. Sender

Open `send.html` in a browser (no camera needed, `file://` is fine).

1. Pick **File** or **Text** mode
2. Choose grid size: `1×1` or `2×2` (default)
3. Hit **Autoplay** and point the phone at the screen

Keyboard shortcuts (when focus is not in an input):

| Key | Action |
| --- | --- |
| `digits` + `letter/Enter` | Jump straight to that chunk (type `12`, then press any letter key or Enter); it also auto-jumps after 2 s |
| `0` | Back to the meta step (first step) |
| `Esc` | Cancel the chunk number being typed |
| `←` / `→` | Previous / next step |
| `Space` | Play / pause |
| `Home` | Back to the first step |

The jump toast appears at the top of the page, so it never covers the QR codes. An out-of-range number shows "no chunk #N" and leaves the current step untouched.

### 2. Receiver · iOS app

Requires macOS with Xcode 26+, iPhone on iOS 17+. **Xcode must not be older than the phone’s iOS** — this project is verified on Xcode 27.1 / macOS 27.0.1 / iOS 27.2; see “Building on another Mac” below for older setups.

```bash
open PixelFlowReceiver/PixelFlowReceiver.xcodeproj
```

1. Select the project → **Signing & Capabilities** → **Team** → pick your Apple ID (a free account works)
2. Change **Bundle Identifier** to something unique, e.g. `com.yourname.pixelflow`
3. Connect your iPhone, select it in the toolbar, press **⌘R**
4. On first launch, trust the developer certificate in **Settings → General → VPN & Device Management**

Or run the one-shot script (build + install + launch):

```bash
cd PixelFlowReceiver
./install-to-device.sh
```

**First launch: “Untrusted Developer”**

iOS blocks the very first launch with “*Untrusted Developer — Your device management settings do not allow using apps from developer “Apple Development: you@example.com (XXXXXXXXXX)” on this iPhone*”. The app is installed fine; the phone simply has not trusted your certificate yet:

1. **Settings → General → VPN & Device Management** (⚠️ not “Privacy & Security → Developer”)
2. Under **Developer App**, tap `Apple Development: your@email`
3. Tap **Trust**, then **Trust** again in the dialog
4. Relaunch PixelFlow

This is a one-time step — reinstalling within the 7-day window (renewal) does not require trusting again. If the **Developer App** section is missing, make sure you opened the one under **General**, then replug or reboot the phone so it can validate the certificate online.

> Free Apple ID signatures expire after **7 days** — reconnect to Xcode and press ⌘R again to renew.

**Building on another Mac**

Nothing in the project is tied to this machine, so any macOS + Xcode box can build it — provided the box qualifies:

| | Requirement |
| --- | --- |
| Chip | **Apple silicon**. Xcode 27 is Apple-silicon-only; Intel Macs top out at Xcode 26.x |
| OS | Xcode 27 needs **macOS Tahoe 26.6+**; Xcode 26.0–26.3 needs macOS 15.6+ (26.4+ needs macOS 26.2+) |
| Xcode | **Must not be older than the phone’s iOS.** iOS 27 phone → Xcode 27; iOS 26 phone → Xcode 26 is fine |

Check the phone under **Settings → General → About → iOS Version**. An Xcode older than the phone’s OS cannot connect to it (“device OS not supported”) — there is no workaround.

Four things to set up — and **don't** copy `build/` over (80 MB of local build artifacts, signed by the previous machine, useless on the new one):

1. **Get the project**: `git clone <url>` if you have a remote; otherwise
   `rsync -av --exclude build --exclude .git ./ user@newmac.local:~/PixelFlow/`
2. **Install Xcode and accept the license**
   ```bash
   xcode-select --install                       # CLT; the script needs /usr/bin/python3
   sudo xcode-select -s /Applications/Xcode.app # otherwise xcodebuild refuses to run
   sudo xcodebuild -license accept              # unaccepted license breaks every build
   xcodebuild -version
   ```
3. **Sign in with the same Apple ID** on that Mac: Xcode → Settings (⌘,) → Accounts → “+”.
   **Certificates do not travel with the project files** — generate one on this machine by opening the project and pressing **⌘B** once; Xcode then creates the Apple Development certificate and provisioning profile. Developer Mode on the phone is device-level, so it stays on; but the new Mac must be trusted on the phone (“Trust This Computer”).
4. **Run the script**: `cd PixelFlowReceiver && ./install-to-device.sh` (step 0 verifies Xcode version, license, `xcode-select` target and python3, and tells you exactly what is missing)
   If the keychain holds several development certificates (multiple Apple IDs), the script takes the first one and may sign for the wrong Team; pin it with `PF_IDENTITY=email PF_TEAM=TeamID ./install-to-device.sh`.

Do I need to trust the app again? A new Mac generates a **new** Apple Development certificate for the same Apple ID. Overwriting the install on the same iPhone usually just works; if “Untrusted Developer” shows up again, tap Trust once more (two identically named entries may appear under **Developer App** — trust both).

To avoid it entirely: on the old Mac open **Keychain Access** → find `Apple Development: your@email` → right-click → **Export** as `.p12` (with a password) → double-click it on the new Mac. Both machines then sign with the same certificate.

If an overwrite install fails with `ApplicationVerificationFailed`, delete the old PixelFlow on the phone first, or unify the certificate as described above. The first device connection on a new Mac downloads the Developer Disk Image, so expect a few extra minutes.

**After the transfer completes**

Once every frame is in, the app verifies SHA-256 and shows the result sheet:

- Files: **Save to Files** (opens the system document picker directly) or **Share…** (the system share sheet with AirDrop, Copy to app, etc.)
- Text: **Copy** or **Share text**

Both export paths are presented through UIKit (`UIActivityViewController` / `UIDocumentPickerViewController`). The share sheet cannot be hosted as a child controller inside a SwiftUI `.sheet` — doing so renders an empty grey window.

### 3. Receiver · web fallback

Browsers only grant camera access in a secure context:

```bash
cd PixelFlow
python3 -m http.server 8000
# then open http://localhost:8000/index.html
```

Opening via `file://` or over a LAN IP with plain HTTP **will be refused**. On a phone this means the native app is effectively the only option — which is exactly why it exists.

---

## PF2 protocol

A custom pipe-delimited text protocol.

| Frame | Format |
| --- | --- |
| Meta | `PF2\|M\|<kind>\|<total>\|<chunkSize>\|<b64len>\|<sha256>\|<grid>\|<name>` |
| Data | `PF2\|D\|<idx>\|<payload>` |

| Field | Meaning |
| --- | --- |
| `kind` | `f` file / `t` text |
| `total` | Number of data chunks |
| `chunkSize` | Characters per chunk |
| `b64len` | Length of the full base64 string |
| `sha256` | SHA-256 of the original bytes (hex), `-` disables verification |
| `grid` | Grid size K (1 / 4) |
| `name` | File name, **always the last field** |

Design notes:

- **Delimiter safety**: payloads are base64 (`A-Za-z0-9+/=`), which never contains `|`. The file name lives last and is reconstructed from the remaining fields, so a name containing `|` cannot corrupt the protocol.
- **Integrity**: the receiver checks `b64len`, then compares SHA-256 against the meta frame. Corrupt data is rejected loudly instead of producing a silently broken file.
- **Chunk parameters live in the meta frame**: changing chunk size mid-transfer can no longer mis-splice already-received chunks.
- **Multi-code grid**: in multi-code mode the meta code (**M**) always holds the top-left cell and is re-broadcast on every step, so the receiver can re-sync at any moment and a phone aimed mid-loop still joins; the remaining cells carry data codes (3 per step on 2×2).
- **Tail step is padded**: the last step usually holds only 2 codes, leaving half the screen white. The camera is most sensitive to a sudden brightening (auto-exposure pulls the frame down), and that step appears only once per loop — which made the tail codes the ones most likely to be missed. The empty cells are now filled by cycling the last few chunks of the round (the **M** in the top-left never moves), and the tail step dwells 2.2× longer (200 ms → 440 ms by default). Seeing a repeated code on the last step is expected, not a glitch.
- **Resume semantics**: seeing a different `sha256` prompts and auto-switches to the new transfer — no manual reset.

## Performance

Net throughput ≈ `(K−1) × chunkSize × 0.75 ÷ step interval` (the top-left cell is taken by the meta code; K=1 is not a grid and counts as one code; the tail step dwells 2.2× longer, costing roughly 3% per loop). Estimates below (real-world typically 70–85% of theoretical):

| Config | Throughput | 100 KB | 1 MB |
| --- | --- | --- | --- |
| 1×1 · 700 B · 200 ms | ~2.6 KB/s | ~39 s | ~6.6 min |
| 2×2 · 700 B · 200 ms (default) | ~7.6 KB/s | ~13 s | ~2.3 min |
| 2×2 · 700 B · 400 ms (safe) | ~3.8 KB/s | ~26 s | ~4.5 min |

The previous version used a single code at 300 ms, landing around 0.3–1.2 KB/s in practice — that is the root cause of the "painfully slow on phone" experience.

Tuning tips:

- Hold the phone **15–25 cm** from the screen, max brightness, avoid reflections
- Pinch to zoom on the phone
- Below 200 ms (the slider goes down to 50 ms) most phones cannot decode all 4 codes within one step, so more chunks go missing; use 300–600 ms in poor light or at distance
- Switching 2×2 down to 1×1 makes every code larger and easier to read, at one third of the throughput
- The receiver lists missing chunk indices; tap those numbers on the sender to re-send them directly

## Dependencies

| Library | Purpose | License |
| --- | --- | --- |
| [node-qrcode](https://github.com/soldair/node-qrcode) | QR generation | MIT |
| [html5-qrcode](https://github.com/mebjas/html5-qrcode) | Web scanning | Apache-2.0 |

The iOS app uses system frameworks only (`AVCaptureMetadataOutput`), no third-party code.

## License

MIT
