# wac_ · by wasil

A floating edge widget for macOS. A slim caret tab lives flush on the right
edge of your screen — click it (or press **⌃⌥W**) and a drawer slides out with
your daily tools. Built in pure AppKit, no dependencies.

## Features

**Actions**
- 📸 **Screenshot** (⌃⌥S) — interactive capture, then straight into the built-in
  annotator: pen, highlighter, arrow, line, shapes, pixelate/blur, text,
  color well, undo/redo. Saves at original resolution or copies to clipboard.
- 🎥 **Record** (⌃⌥R) — screen recording with options: region select, mic,
  visualized clicks, and a Loom-style **camera bubble** (size/shape/corner,
  draggable mid-recording). The edge tab becomes a stop button with a live
  elapsed timer. Every recording opens in a filmstrip **trim editor**
  (QuickTime-style handles, scrubbing, pixelate regions) before you keep it.
- 🎙 **Audio** — mic-only recordings (m4a).
- 📝 **Notes** — quick notes with full CRUD and draft autosave.
- ✏️ **Draw** — blank canvas with all annotator tools.
- 💧 **Pick Color** — screen eyedropper, hex lands on your clipboard.
- ⬇️ **Downloads** — your latest ~/Downloads, open/rename/drag/trash.
- ⏰ **Alarm & Timer** — countdown timers and clock alarms with a looping
  chime and dismiss banner; they survive relaunches.

**Clips** — clipboard history (last 100, text *and* images). Click to copy
and auto-paste into the app you came from; drag any clip out.

**Files** — every capture (screenshots, recordings, audio, drawings) grouped
by date, with thumbnails, inline rename, drag-out, edit and trash.

**Extras** — theme picker (rosé pine / terminal / violet / slate), launch at
login, world clocks + system glance in the footer, toast feedback on every
action, global hotkeys with zero permission prompts.

## Build & run

```sh
./build.sh        # compiles Sources/*.swift into wac.app
open wac.app
```

Requires macOS 13+ and Xcode Command Line Tools (`xcode-select --install`).

**Recommended (one time):** `./setup-signing.sh` creates a stable self-signed
codesigning identity so macOS permission grants survive rebuilds. Without it,
builds are ad-hoc signed and TCC re-asks after every rebuild.

## Permissions

wac asks only when you first use a feature — never at launch:

| Permission | Needed for | Asked when |
|---|---|---|
| Screen Recording | screenshots & recordings | first capture |
| Microphone | recording audio | first recording with mic |
| Camera | the camera bubble | first recording with camera |
| Accessibility | auto-paste of clips (⌘V) | first clip click |

After granting Screen Recording, relaunch wac once (macOS requirement).

## Where things go

- Captures: `~/Pictures/wac/{screenshots,recordings,audio,drawings}`
- Data (clips, notes): `~/Library/Application Support/wac/`

## Layout

```
Sources/
  main.swift         app shell: edge panel, expand/collapse, hotkey wiring
  Drawer.swift       everything inside the drawer (tabs, sections)
  Views.swift        shared UI components (tab, cards, pills, buttons)
  Theme.swift        switchable color palettes
  Annotator.swift    image annotation editor
  VideoEditor.swift  filmstrip trim + blur editor
  Recorder.swift     screen & audio recording
  CameraOverlay.swift  Loom-style camera bubble
  RegionSelector.swift region drag-select overlay
  Alarm.swift        timers & alarms
  Stores.swift       clipboard history + notes persistence
  Media.swift        capture library + downloads
  SysInfo.swift      footer stats & world clocks
  Toast.swift        floating feedback HUD
  Hotkeys.swift      global shortcuts (Carbon, no permissions)
build.sh             build + bundle + sign
gen-icon.swift       app icon generator
setup-signing.sh     one-time stable signing identity
```
