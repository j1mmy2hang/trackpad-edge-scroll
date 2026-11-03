# trackpad-edge-scroll

> An open-source copy of **[EdgeBar](https://edgebar.xyz/)**. The idea and design are theirs; I rebuilt it to learn how it works. For the real app, go to [edgebar.xyz](https://edgebar.xyz/). Not affiliated with EdgeBar.

Slide one finger along the edge of your MacBook trackpad:

- **Left edge** → brightness
- **Right edge** → volume

## Download

1. Get `EdgeBar-x.x.zip` from [Releases](https://github.com/j1mmy2hang/trackpad-edge-scroll/releases/latest).
2. Unzip it and drag **EdgeBar.app** into Applications.
3. Open it. An icon appears in the menu bar.

Needs macOS 26 or later and a Force Touch trackpad. No permissions to grant.

## Using it

- Slide up or down on an edge. Taps and normal pointer moves still work.
- The pointer stays still while you slide, and a Liquid Glass display shows the level.
- The trackpad clicks softly at each step.
- Menu bar icon: **Haptic Feedback** strength, **Open at Login**, **Quit**.

## Build it yourself

```sh
git clone https://github.com/j1mmy2hang/trackpad-edge-scroll.git
cd trackpad-edge-scroll
./build.sh install     # builds and copies EdgeBar.app to /Applications
```

Needs the Xcode Command Line Tools (`xcode-select --install`).

Tuning values (edge width, sensitivity, palm size) are constants at the top of `Sources/EdgeBar.swift`. To see every touch: `EDGEBAR_DEBUG=1 build/EdgeBar.app/Contents/MacOS/EdgeBar`.

## How it works

- **Touches:** read straight from the trackpad with Apple's private `MultitouchSupport` framework.
- **Brightness:** private `DisplayServices` framework.
- **Volume:** CoreAudio.
- **Haptics:** the trackpad's own motor, through `MultitouchSupport`.

Because it uses private frameworks, a future macOS update could break it, and it can't go on the App Store.

## Files

```
Sources/EdgeBar.swift   the whole app, one file
Resources/              Info.plist and icon
Tools/make-icon.swift   draws the icon
build.sh                build (and install) locally
release.sh              sign, notarize, publish a GitHub release
```

## License

MIT, for this code. The EdgeBar name and design belong to [edgebar.xyz](https://edgebar.xyz/).
