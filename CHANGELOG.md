# Changelog

## 0.1

First public release of DarkShot for macOS.

- Native Swift/AppKit app with Apple Silicon support and ScreenCaptureKit capture.
- Global capture shortcut with recording, persistence, and conflict feedback.
- Drag-to-select capture with crop movement, resizing, and Retina-resolution export.
- Compact annotation toolbar with pen, line, arrow, rectangle, ellipse, highlighter, and text.
- Annotation undo/redo, color selection, and stroke-width controls.
- Copy to clipboard as PNG/TIFF, or save a PNG.
- Launch at login using macOS’s built-in login-item support.
- Local-only workflow: no accounts, analytics, or uploads.
- 78 automated geometry, rendering, interaction, and settings checks.

### Requirements and distribution

- macOS 14 or later.
- The prebuilt ZIP is for Apple Silicon (`arm64`).
- The app is ad-hoc signed, **not Developer ID signed or notarized**.
  macOS Gatekeeper may block a downloaded copy. Only approve it if you trust
  its source, or build it locally using the instructions in the README.
- Screen Recording permission is required for capture.
- Windows and a prebuilt Intel/universal app are not included.
