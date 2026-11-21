# DarkShot

A small, native macOS screenshot app inspired by Lightshot’s workflow:

**Shortcut → drag an area → annotate → copy or save.**

Built from scratch in Swift/AppKit, using ScreenCaptureKit. No Electron, Rosetta,
third-party dependencies, accounts, analytics, or upload servers. LiveShot and
Lightshot are workflow references; their code and artwork are not included.

## Run

Clone the repository and build the app locally:

```sh
git clone https://github.com/briggsyuk/DarkShot.git
cd DarkShot
zsh scripts/build-app.sh
open dist/DarkShot.app
```

The generated app is at **`dist/DarkShot.app`**; build output is not committed.
See [Build](#build) for requirements and signing details.

It lives in the menu bar. On first launch, a short welcome window explains the
controls. Closing that window does not quit the app.

For a permanent installation, quit DarkShot and move the app into `/Applications`
**before granting screen capture permission**. Keep just one installed copy to
avoid confusion in macOS’s permission list.

### Screen Recording permission

The first capture requests macOS permission. Enable DarkShot under:

**System Settings → Privacy & Security → Screen & System Audio Recording**

(On some macOS versions this is called **Screen Recording**.)

macOS may require quitting and reopening DarkShot after granting permission.
Use DarkShot’s menu-bar item to open the relevant settings page.
No Accessibility, microphone, camera, or input-monitoring access is needed.
Despite the settings page’s name, DarkShot does not capture audio.

## Capture

1. Press **Control–Option–D** (`⌃⌥D`) by default, or choose **Capture an Area** in the menu bar.
2. Drag a rectangle on a display. The screen is frozen while you annotate.
3. Choose drawing tools from the inline toolbar or use their letter shortcuts.
4. Press **⌘C / Return** to copy the image, or **⌘S** to save a PNG.
5. Press **Esc** to cancel. The global shortcut also dismisses an active capture.

| Key | Action |
| --- | --- |
| V | Move the crop by dragging inside it |
| P | Freehand pen |
| L | Line |
| A | Arrow |
| R | Rectangle |
| O | Ellipse |
| H | Translucent highlighter |
| T | Text; click, type, then Return to commit |
| Shift while drawing | Square/circle, or snap line/arrow angle |
| − / + | Stroke width |
| ⌘Z / ⇧⌘Z | Undo / redo annotations |
| Delete | Undo the last annotation |
| Arrow keys | Nudge crop by one logical point |
| Shift + arrows | Resize crop |
| Option + arrows | Ten-point steps; combines with Shift |
| N | Clear annotations and reselect, including on another display |
| Esc | Cancel text editing, or cancel the capture if not editing |

Drag the eight crop handles to resize. Moving/resizing changes the crop over the
frozen display; existing annotations stay anchored to the screen. Color and
width controls apply to subsequent annotations. The native color well opens
macOS’s color picker.

The dimension badge shows **output pixels**, including Retina scaling.
The clipboard contains PNG and TIFF for compatibility with other apps.
Save remembers the last folder. Cancelling Save returns to the editor.

### Settings

Choose **DarkShot’s menu-bar icon → Settings…** (or **⌘,** while DarkShot is active).

- **Capture shortcut:** Click the combination, then press a new one. Include
  Control, Option, or Command, or use an F-key such as F13 on its own. Escape
  cancels recording. Conflicting/reserved combinations are rejected; the
  previous shortcut is retained. **Reset to Default** restores `⌃⌥D`.
- **Launch DarkShot at login:** Starts the app quietly in the menu bar when
  you sign in. Uses macOS’s built-in ServiceManagement support, with no helper
  daemon or custom launch scripts. If macOS requires approval, use **Open macOS
  Login Items…** and enable DarkShot there. Turning this off unregisters startup.

The capture menu, menu-bar tooltip, and welcome window reflect your chosen
shortcut. Keep the app in a permanent location before enabling login startup;
moving or rebuilding a locally signed app can require re-approval.

## Build

Requires macOS 14+ and Swift 6+ (Apple Command Line Tools are sufficient).
The build targets the current Mac’s architecture; on Apple Silicon it produces
an **arm64** app, not an Intel app running through Rosetta.

```sh
zsh scripts/build-app.sh
```

Open `Package.swift` in Xcode if you prefer an IDE. Run the packaged `.app`
for normal use so macOS can associate permissions with its bundle identifier.

The build script ad-hoc signs the app for **local development**. This is not a
notarized distribution release. Screen Recording permission may need to be
granted again after rebuilds. For distribution, use a stable Developer ID
signing identity, notarization, and stapling; those require an Apple developer
account and are not configured here. The script accepts `SIGN_IDENTITY` for a
signing identity you already have.

## Checks

```sh
zsh scripts/test.sh
```

The runner uses only the macOS SDK, not XCTest or full Xcode. It checks:

- Crop bounds, reversed drags, all resize axes, boundary clamping, Retina
  scaling, and fractional-pixel rounding.
- Image orientation, crop origins, annotation translation/scaling, PNG/TIFF
  encoding, and rendering every drawing tool.
- Synthetic pointer/keyboard interaction: selection, drawing, export,
  undo/redo, moving/resizing, inline text, reselecting, and cancellation.
- Compact toolbar dimensions, unclipped controls, and icon-button export.
- Shortcut validation, persistence, F-keys, recording, conflict feedback, and
  cancelling/recovering when Settings loses focus or closes.
- Rendering the native annotation UI into a synthetic-image preview at
  `.build/checks/annotation-preview.png`.

These checks do **not** capture your desktop, change your clipboard, save any
real screenshots, grant permissions, or change your login items.

### Live checks still needed

- First-run permission grant, denial, and restarting after approval.
- Global shortcut alongside your usual apps.
- Real clipboard paste into your preferred destinations.
- Save, cancel Save, and an unwritable destination.
- Mixed-scale multiple displays, displays with negative origins, full-screen
  Spaces, and display disconnects.
- Actual shortcut-to-overlay latency on your machine.
- Your chosen shortcut after relaunch, and login startup after signing out/in.

## Scope of this first version

This is a working local-development build, not a completed commercial release.
It supports one rectangular crop on one display per capture session. All
connected displays are captured concurrently before overlays appear; choose the
display by starting your drag there.

Not yet included: Windows, annotation object selection/editing, blur/redaction, scrolling captures, OCR,
uploading/sharing links, or screenshot history. Protected/DRM content may be
blank due to macOS capture restrictions.

Only the remembered save directory, capture shortcut, and first-launch flag are stored in app
preferences. Captures and annotations are kept in memory until the capture
session ends. Images leave the app only when you explicitly copy or save them;
the system clipboard and saved files persist afterward.
