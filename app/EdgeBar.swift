// EdgeBar: slide one finger along the left edge of the trackpad for brightness,
// along the right edge for volume. While sliding, the cursor stays put and an
// on-screen display shows the level, and the trackpad ticks at each step. A menu bar icon with Quit.
//
// Build: swiftc -O EdgeBar.swift -o EdgeBar
// Run:   ./EdgeBar                   (EDGEBAR_DEBUG=1 ./EdgeBar prints every touch)

import Cocoa
import CoreAudio
import AudioToolbox

// MARK: - Settings

let edgeWidth: Float = 0.12     // how much of each side counts as the edge (0...1 of trackpad width)
let sensitivity: Float = 1.0    // 1.0 = sliding the full height of the trackpad covers 0% to 100%
let slideStart: Float = 0.05    // how far (0...1 of trackpad height) a finger must move up or down before it counts as a slide
let palmSize: Float = 16        // a contact longer than this (majorAxis) is a palm, not a finger

let debug = ProcessInfo.processInfo.environment["EDGEBAR_DEBUG"] != nil

// MARK: - Raw trackpad touches (private MultitouchSupport framework)

// One finger on the trackpad, as MultitouchSupport reports it (96 bytes).
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32       // stays the same for one contact from landing to lifting
    var state: Int32            // 4 = touching the glass
    var fingerID: Int32
    var handID: Int32
    var x: Float                // 0 = left, 1 = right
    var y: Float                // 0 = bottom, 1 = top
    var vx: Float
    var vy: Float
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float        // length of the contact: small for a fingertip, large for a palm
    var minorAxis: Float
    var absX: Float
    var absY: Float
    var absVX: Float
    var absVY: Float
    var zero2: (Int32, Int32)
    var unknown: Float
}

// The touches arrive as a raw pointer (C can't name a Swift struct) and are read as MTTouch
typealias MTContactCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
let MTDeviceCreateList = unsafeBitCast(dlsym(mt, "MTDeviceCreateList"), to: (@convention(c) () -> Unmanaged<CFArray>).self)
let MTRegisterContactFrameCallback = unsafeBitCast(dlsym(mt, "MTRegisterContactFrameCallback"), to: (@convention(c) (UnsafeMutableRawPointer, MTContactCallback) -> Void).self)
let MTDeviceStart = unsafeBitCast(dlsym(mt, "MTDeviceStart"), to: (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void).self)
let MTDeviceGetDeviceID = unsafeBitCast(dlsym(mt, "MTDeviceGetDeviceID"), to: (@convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32).self)
let MTActuatorCreateFromDeviceID = unsafeBitCast(dlsym(mt, "MTActuatorCreateFromDeviceID"), to: (@convention(c) (UInt64) -> Unmanaged<AnyObject>?).self)
let MTActuatorOpen = unsafeBitCast(dlsym(mt, "MTActuatorOpen"), to: (@convention(c) (UnsafeMutableRawPointer) -> Int32).self)
let MTActuatorActuate = unsafeBitCast(dlsym(mt, "MTActuatorActuate"), to: (@convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32).self)

// MARK: - Brightness (private DisplayServices framework)

let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
let DisplayServicesGetBrightness = unsafeBitCast(dlsym(ds, "DisplayServicesGetBrightness"), to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
let DisplayServicesSetBrightness = unsafeBitCast(dlsym(ds, "DisplayServicesSetBrightness"), to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)

// The MacBook's own screen, even when an external display is the main one.
func builtInDisplay() -> CGDirectDisplayID {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &count)
    return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
}

func getBrightness() -> Float {
    var value: Float = 0.5
    _ = DisplayServicesGetBrightness(builtInDisplay(), &value)
    return value
}

func setBrightness(_ value: Float) {
    _ = DisplayServicesSetBrightness(builtInDisplay(), value)
}

// MARK: - Volume (CoreAudio, default output device)

func outputDevice() -> AudioDeviceID {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
    return id
}

// e.g. "MacBook Pro Speakers", shown as the title of the on-screen display
func deviceName(_ id: AudioDeviceID) -> String {
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                          mScope: kAudioObjectPropertyScopeGlobal,
                                          mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name)
    return name?.takeRetainedValue() as String? ?? "Sound"
}

var volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                               mScope: kAudioDevicePropertyScopeOutput,
                                               mElement: kAudioObjectPropertyElementMain)
var muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                             mScope: kAudioDevicePropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)

// Looked up once per slide, not on every frame
var audioDevice = AudioDeviceID(0)
var audioMuted: UInt32 = 2      // 2 = not known yet

// Called once when a volume slide starts
func getVolume() -> Float {
    audioDevice = outputDevice()
    audioMuted = 2
    var value: Float32 = 0.5
    var size = UInt32(MemoryLayout<Float32>.size)
    AudioObjectGetPropertyData(audioDevice, &volumeAddress, 0, nil, &size, &value)
    return value
}

func setVolume(_ value: Float) {
    var v = Float32(value)
    AudioObjectSetPropertyData(audioDevice, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    // Sliding up should be heard, so unmute; only touch mute when it changes
    var mute: UInt32 = value > 0 ? 0 : 1
    if mute != audioMuted {
        AudioObjectSetPropertyData(audioDevice, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        audioMuted = mute
    }
}

// Setting the volume waits on the audio system, so it runs on its own queue and the trackpad
// never waits for it. Only the newest value is applied, so a fast slide never queues up behind itself.
let volumeQueue = DispatchQueue(label: "volume")
let volumeLock = NSLock()
var wantedVolume: Float = 0
var volumeBusy = false

func requestVolume(_ value: Float) {
    volumeLock.lock()
    wantedVolume = value
    let start = !volumeBusy
    volumeBusy = true
    volumeLock.unlock()
    guard start else { return }

    volumeQueue.async {
        while true {
            volumeLock.lock(); let v = wantedVolume; volumeLock.unlock()
            setVolume(v)
            volumeLock.lock()
            if v == wantedVolume { volumeBusy = false; volumeLock.unlock(); return }
            volumeLock.unlock()
        }
    }
}

// MARK: - Gesture: one finger that lands on an edge and slides up or down

enum Side { case left, right }

enum Phase {
    case idle               // no finger down
    case waiting(Side)      // landed on an edge, not yet moved far enough to be a slide
    case sliding(Side)      // adjusting brightness or volume
    case ignored            // an ordinary touch; left alone until every finger lifts

    var isIdle: Bool { if case .idle = self { return true } else { return false } }
}

var phase = Phase.idle
var fingerID: Int32 = -1        // the one finger being followed
var palms = Set<Int32>()        // contacts that have been palm-sized; ignored until they lift
var startX: Float = 0, startY: Float = 0
var lastY: Float = 0
var level: Float = 0            // the brightness or volume being adjusted
var title = ""                  // the on-screen display's title

let onTouches: MTContactCallback = { _, touches, count, _, _ in
    let all = (0..<Int(count)).compactMap { touches?.load(fromByteOffset: $0 * 96, as: MTTouch.self) }
    if debug {
        for t in all { print(String(format: "id %d  state %d  x %.2f  y %.2f  size %.2f  major %.1f  minor %.1f",
                                    t.identifier, t.state, t.x, t.y, t.size, t.majorAxis, t.minorAxis)) }
    }

    // Palm rejection: a contact that has ever been palm-sized is ignored until it lifts
    palms.formIntersection(all.map(\.identifier))
    for t in all where t.majorAxis > palmSize { palms.insert(t.identifier) }
    let fingers = all.filter { $0.state == 4 && !palms.contains($0.identifier) }

    // A touch ends when its finger lifts, turns out to be a palm, or another finger joins
    if !phase.isIdle && (fingers.count != 1 || fingers[0].identifier != fingerID) {
        if case .sliding = phase {
            releaseCursor()
            DispatchQueue.main.async { hud.hideSoon() }
        }
        phase = fingers.isEmpty ? .idle : .ignored
        return 0
    }

    // Only a single finger counts, so two-finger scrolling never changes anything
    guard fingers.count == 1 else {
        if !fingers.isEmpty { phase = .ignored }
        return 0
    }
    let t = fingers[0]

    switch phase {
    case .idle:
        // A new touch can only become a slide if it lands on an edge
        fingerID = t.identifier
        if t.x < edgeWidth { phase = .waiting(.left) }
        else if t.x > 1 - edgeWidth { phase = .waiting(.right) }
        else { phase = .ignored; return 0 }
        startX = t.x; startY = t.y
        frozenAt = cursorLocation()     // where the pointer goes back to if this becomes a slide

    case .waiting(let side):
        // A slide is a clear move up or down; a tap or a sideways move stays an ordinary touch
        let dx = abs(t.x - startX), dy = abs(t.y - startY)
        if dy >= slideStart && dy > dx * 2 {
            phase = .sliding(side)
            if side == .left { level = getBrightness(); title = "Built-in Display" }
            else { level = getVolume(); title = deviceName(audioDevice) }
            lastY = t.y
            lastStep = Int(level * 16)
            holdCursor()
            let shown = level, text = title
            DispatchQueue.main.async { hud.show(side, shown, text) }
        } else if dx >= slideStart {
            phase = .ignored
        }

    case .sliding(let side):
        // Move the level by how far the finger moved since the last frame
        level = min(1, max(0, level + (t.y - lastY) * sensitivity))
        lastY = t.y
        if side == .left { setBrightness(level) } else { requestVolume(level) }
        // A light tick each time the level passes one of the 16 steps
        let step = Int(level * 16)
        if step != lastStep { lastStep = step; tick() }
        holdCursor()
        let shown = level, text = title
        DispatchQueue.main.async { hud.show(side, shown, text) }

    case .ignored:
        break
    }
    return 0
}

func startTrackpad() {
    precondition(MemoryLayout<MTTouch>.stride == 96, "MTTouch layout mismatch")
    let devices = MTDeviceCreateList().takeRetainedValue() as [AnyObject]
    for device in devices {
        let ref = Unmanaged.passUnretained(device).toOpaque()
        MTRegisterContactFrameCallback(ref, onTouches)
        MTDeviceStart(ref, 0)
        openActuator(ref)
    }
}

// MARK: - Haptics: the trackpad's own motor, which (unlike NSHapticFeedbackManager) works for a background app

var actuator: UnsafeMutableRawPointer?
var lastStep = 0                // the step the level was on at the last tick

func openActuator(_ device: UnsafeMutableRawPointer) {
    var id: UInt64 = 0
    guard actuator == nil, MTDeviceGetDeviceID(device, &id) == 0,
          let created = MTActuatorCreateFromDeviceID(id) else { return }
    let ref = created.toOpaque()        // kept open for the app's lifetime
    if MTActuatorOpen(ref) == 0 { actuator = ref }
}

// The trackpad motor's built-in clicks; 0 means haptics are off. Chosen in the menu, remembered between launches.
let hapticStrengths: [(name: String, id: Int32)] = [("Off", 0), ("Weak", 3), ("Medium", 4), ("Strong", 6)]
var hapticID = Int32(UserDefaults.standard.object(forKey: "hapticID") as? Int ?? 3)

func tick() {
    if let actuator, hapticID != 0 { _ = MTActuatorActuate(actuator, hapticID, 0, 0, 0) }
}

// MARK: - Cursor freeze: while a finger slides on an edge, keep putting the pointer back where it was

var frozenAt = CGPoint.zero

func cursorLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

// Runs on every trackpad frame of a slide, so the pointer never gets far
func holdCursor() {
    CGWarpMouseCursorPosition(frozenAt)
}

func releaseCursor() {
    CGWarpMouseCursorPosition(frozenAt)
    CGAssociateMouseAndMouseCursorPosition(1)    // ends the short pause macOS adds after a warp
}

// MARK: - On-screen display: a Liquid Glass panel at the top centre, like the macOS 26 volume HUD

// The glass only draws its full Liquid Glass look (the lensing rim) in a key window. A non-activating
// panel can be key without making EdgeBar the active app, so the app you're in stays in front.
class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class HUD {
    // Sizes measured from the macOS 26 volume HUD
    let width: CGFloat = 295, height: CGFloat = 70
    let trackX: CGFloat = 30, trackW: CGFloat = 223, trackMid: CGFloat = 25    // the slider's centre line, from the bottom
    let panel: NSPanel
    let titleLabel = NSTextField(labelWithString: "")
    let lowIcon = NSImageView(), highIcon = NSImageView()
    let track = CALayer(), fill = CALayer()
    var dots: [CALayer] = []
    var hideWork: DispatchWorkItem?

    init() {
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver                       // above everything, full screen apps too
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let glass = NSGlassEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        glass.cornerRadius = 22
        glass.style = .clear                             // the see-through glass of the system HUD
        glass.tintColor = NSColor(white: 0, alpha: 0.3)  // a darker shade, so white text reads on any background
        let content = NSView(frame: glass.bounds)
        content.wantsLayer = true
        glass.contentView = content
        panel.contentView = glass

        // The glass is shaded dark, so everything on it is white, in light and dark mode alike
        titleLabel.frame = NSRect(x: 16, y: 38, width: width - 32, height: 17)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        content.addSubview(titleLabel)

        lowIcon.frame = NSRect(x: 11.5, y: trackMid - 8, width: 16, height: 16)
        lowIcon.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        highIcon.frame = NSRect(x: trackX + trackW + 4, y: trackMid - 10, width: 26, height: 20)
        highIcon.symbolConfiguration = .init(pointSize: 14, weight: .semibold)
        for icon in [lowIcon, highIcon] {
            icon.contentTintColor = .white
            content.addSubview(icon)
        }

        // The slider: a faint track, a solid fill, and a row of small dots underneath
        track.frame = CGRect(x: trackX, y: trackMid - 1.5, width: trackW, height: 3)
        track.cornerRadius = 1.5
        track.backgroundColor = NSColor(white: 1, alpha: 0.25).cgColor
        fill.frame = CGRect(x: trackX, y: trackMid - 1.5, width: 0, height: 3)
        fill.cornerRadius = 1.5
        fill.backgroundColor = NSColor.white.cgColor
        content.layer?.addSublayer(track)
        content.layer?.addSublayer(fill)
        for i in 0..<17 {
            let dot = CALayer()
            dot.frame = CGRect(x: trackX + CGFloat(i) * trackW / 16 - 0.75, y: trackMid - 5.75, width: 1.5, height: 1.5)
            dot.cornerRadius = 0.75
            dot.backgroundColor = NSColor(white: 1, alpha: 0.35).cgColor
            content.layer?.addSublayer(dot)
            dots.append(dot)
        }
        panel.alphaValue = 0
    }

    func show(_ side: Side, _ level: Float, _ title: String) {
        hideWork?.cancel()
        titleLabel.stringValue = title
        let low = side == .left ? "sun.min.fill" : (level == 0 ? "speaker.slash.fill" : "speaker.fill")
        let high = side == .left ? "sun.max.fill" : "speaker.wave.3.fill"
        lowIcon.image = NSImage(systemSymbolName: low, accessibilityDescription: nil)
        highIcon.image = NSImage(systemSymbolName: high, accessibilityDescription: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)            // the fill follows the finger, no lag from animation
        fill.frame.size.width = trackW * CGFloat(level)
        CATransaction.commit()

        if panel.alphaValue < 1 {
            // Top centre of the screen the pointer is on, just under the menu bar
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - width / 2, y: area.maxY - height - 8))
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        }
    }

    // Lingers a moment after the finger lifts, then fades, like macOS
    func hideSoon() {
        let work = DispatchWorkItem { [panel] in
            // Once faded, close it so the keyboard goes back to the window you were in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                                 completionHandler: { if panel.alphaValue == 0 { panel.orderOut(nil) } })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }
}

var hud: HUD!

// MARK: - Menu bar app

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "EdgeBar")
        let menu = NSMenu()

        // Haptic Feedback ▸ Off / Weak / Medium / Strong
        let haptics = NSMenu()
        for option in hapticStrengths {
            let item = NSMenuItem(title: option.name, action: #selector(setHaptics(_:)), keyEquivalent: "")
            item.target = self
            item.tag = Int(option.id)
            item.state = option.id == hapticID ? .on : .off
            haptics.addItem(item)
        }
        let hapticsItem = NSMenuItem(title: "Haptic Feedback", action: nil, keyEquivalent: "")
        hapticsItem.submenu = haptics
        menu.addItem(hapticsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit EdgeBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        hud = HUD()
        startTrackpad()
    }

    @objc func setHaptics(_ sender: NSMenuItem) {
        hapticID = Int32(sender.tag)
        UserDefaults.standard.set(sender.tag, forKey: "hapticID")
        for item in sender.menu?.items ?? [] { item.state = item == sender ? .on : .off }
        tick()      // a sample of the new strength
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
app.run()
