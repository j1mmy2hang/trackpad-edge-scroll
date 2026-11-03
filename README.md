# trackpad-edge-scroll

> An open-source copy of **[EdgeBar](https://edgebar.xyz/)**. The idea and design are theirs; I rebuilt it to learn how it works. For the real app, go to [edgebar.xyz](https://edgebar.xyz/). Not affiliated with EdgeBar.

Slide one finger along the edge of your MacBook trackpad:

- **Left edge** → brightness
- **Right edge** → volume

## Install

```sh
git clone https://github.com/j1mmy2hang/trackpad-edge-scroll.git
cd trackpad-edge-scroll
./build.sh install     # builds and copies EdgeBar.app to /Applications
```

An icon appears in the menu bar. Needs macOS 26 or later, a Force Touch trackpad, and the Xcode Command Line Tools (`xcode-select --install`). No permissions to grant.

There's no download: the app isn't notarized, so a copy built on someone else's Mac would be blocked by macOS. Building it yourself takes a few seconds.

Tuning values (edge width, sensitivity, palm size) are constants at the top of `Sources/EdgeBar.swift`. To see every touch: `EDGEBAR_DEBUG=1 build/EdgeBar.app/Contents/MacOS/EdgeBar`.

## Using it

- Slide up or down on an edge. Taps and normal pointer moves still work.
- The pointer stays still while you slide, and a Liquid Glass display shows the level.
- The trackpad clicks softly at each step.
- Menu bar icon: **Haptic Feedback** strength, **Open at Login**, **Quit**.

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
build.sh                build (and install)
```

## License

MIT, for this code. The EdgeBar name and design belong to [edgebar.xyz](https://edgebar.xyz/).
