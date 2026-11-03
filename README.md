# trackpad-edge-scroll

> **Credit:** this is an open-source imitation of **[EdgeBar](https://edgebar.xyz/)**, the original app.
> The idea, the gesture and the design all come from EdgeBar. I rebuilt it from scratch to learn how it works.
> If you want the real, polished product, get it at **[edgebar.xyz](https://edgebar.xyz/)**.
> This project is not affiliated with or endorsed by EdgeBar.

A small macOS menu bar app that turns the edges of a MacBook trackpad into sliders.

- **Left edge:** slide one finger up or down to change the screen brightness.
- **Right edge:** slide one finger up or down to change the volume.

The whole app is one Swift file, about 480 lines, with no Xcode project and no dependencies.

## Features

- **Slide, don't tap.** A touch on an edge only counts once it moves up or down a little. Taps, light touches and sideways moves stay normal pointer use.
- **Relative control.** The level changes by how far you slide, not by where your finger lands, so it never jumps. One full trackpad height covers 0–100%.
- **The pointer stays put** while you slide.
- **Liquid Glass on-screen display** at the top center of the screen, modeled on the macOS 26 volume display. It shows the output device name (for example "MacBook Pro Speakers") or "Built-in Display", with a slider.
- **Haptic feedback:** a light click under your finger at each of 16 steps. Choose Off, Weak, Medium or Strong from the menu bar icon; the choice is remembered.
- **Palm rejection:** palm-sized contacts are ignored, so a resting palm doesn't block or start a slide.
- **Never in the way:** only single-finger slides count, so two-finger scrolling and other gestures are unaffected.
- **Sliding up unmutes** the sound.
- **Menu bar only:** no Dock icon.
- **Open at Login** from the menu bar icon.

## Requirements

- A Mac with a Force Touch trackpad (built-in or Magic Trackpad). Haptics need Force Touch.
- macOS 26 Tahoe or later, for Liquid Glass.
- The Xcode Command Line Tools, for `swiftc`. Install them with `xcode-select --install`.

## Install

```sh
git clone https://github.com/j1mmy2hang/trackpad-edge-scroll.git
cd trackpad-edge-scroll
./build.sh install
```

This builds `build/EdgeBar.app`, copies it to `/Applications` and opens it. The icon (three vertical sliders) appears in the menu bar. To start it automatically, choose **Open at Login** from its menu. To quit, choose **Quit EdgeBar**.

`./build.sh` alone only builds the app, without installing it.

No permissions are needed: reading the trackpad, setting brightness and volume, and the haptic motor all work without Accessibility access.

To uninstall, quit it and delete `/Applications/EdgeBar.app`.

## Settings

The app's menu has **Haptic Feedback ▸ Off / Weak / Medium / Strong** and **Open at Login**. Everything else is a constant at the top of `Sources/EdgeBar.swift`. Run `./build.sh install` again after changing one.

| Setting | Default | Meaning |
|---|---|---|
| `edgeWidth` | `0.12` | How much of each side counts as the edge, as a fraction of the trackpad's width |
| `sensitivity` | `1.0` | `1.0` means one full trackpad height covers 0–100% |
| `slideStart` | `0.05` | How far a finger must move up or down, as a fraction of the trackpad's height, before it counts as a slide |
| `palmSize` | `16` | A contact longer than this (`majorAxis`) is treated as a palm |

To tune `palmSize` or the other values, run with debug output. Each touch is printed with its position and size:

```sh
./build.sh
EDGEBAR_DEBUG=1 build/EdgeBar.app/Contents/MacOS/EdgeBar
```

## How it works

| Part | How |
|---|---|
| Finger positions | `MultitouchSupport.framework` (private): raw touches from the trackpad, about 100 frames a second |
| Brightness | `DisplayServices.framework` (private): sets the built-in display's brightness, even when an external display is the main one |
| Volume | CoreAudio (public): the default output device's main volume. Each change takes about 8 ms, so it runs on its own queue and always applies the newest value; the touch handling never waits for it |
| Pointer freeze | `CGWarpMouseCursorPosition` (public): on every frame of a slide, the pointer is moved back to where the touch began |
| On-screen display | `NSGlassEffectView` (public, macOS 26) in a non-activating panel. The panel becomes the key window without activating the app, which is what makes the full Liquid Glass look appear. Your current app stays in front |
| Haptics | The trackpad's own motor through `MultitouchSupport` (`MTActuatorActuate`). The public `NSHapticFeedbackManager` only works for the frontmost app, and EdgeBar never is |

### The gesture

Each single-finger touch goes through these phases:

1. **Idle:** no finger is down.
2. **Waiting:** the finger landed on an edge but hasn't moved far enough yet.
3. **Sliding:** the finger moved up or down at least `slideStart`, and more than twice as far vertically as sideways. From here, the level follows the finger.
4. **Ignored:** the touch is a normal one (it started in the middle, moved sideways, or a second finger joined). It's left alone until every finger lifts.

## Known limitations

- **Private frameworks.** MultitouchSupport and DisplayServices are not public API. A future macOS update could change or break them, and an app that uses them can't go on the Mac App Store.
- **The pointer can shake slightly while sliding.** macOS moves the pointer before any app sees the movement, so EdgeBar can only move it back afterwards.
- **The keyboard goes to the display while it's visible** (during a slide and about one second after). It hands the keyboard back as soon as it fades out.
- **Ad-hoc signed, not notarized.** Built on your own Mac, it runs fine. A copy downloaded from someone else would be blocked by Gatekeeper.
- **`palmSize` is an estimate.** It may need tuning for your hands; see [Settings](#settings).
- **A touch that starts on an edge won't move the pointer once it becomes a slide.** Start pointer movements away from the edges, or narrow `edgeWidth`.

## Project structure

```
Sources/EdgeBar.swift    the whole app
Resources/Info.plist     app bundle settings (menu bar only, bundle ID)
Resources/AppIcon.icns   app icon
Tools/make-icon.swift    draws the icon: swift Tools/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
build.sh                 builds build/EdgeBar.app; "install" copies it to /Applications
```

## License

MIT, for this code only. See [LICENSE](LICENSE). The name EdgeBar and the original design belong to [edgebar.xyz](https://edgebar.xyz/).
