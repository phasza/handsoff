import SwiftUI
import AppKit
import Carbon
import Foundation

let lockQueue = DispatchQueue(label: "com.handsoff.lockqueue")

@main
struct HandsOffApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // No window needed
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var lockMenuItem: NSMenuItem?
    
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    
    private var _isLocked = false
    var isLocked: Bool {
        get { lockQueue.sync { _isLocked } }
        set { lockQueue.sync { _isLocked = newValue } }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            Logger.shared.log("Uncaught exception: \(exception)")
        }
        
        checkAccessibilityPermissions()
        setupStatusItem()
        updateMenu()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        cleanupEventTap()
    }
    
    @objc func toggleLock() {
        isLocked.toggle()
        updateMenu()
    }
    
    @objc func showMenu() {
        // The menu will automatically show when the icon is clicked
    }
    
    @objc func updateMenu() {
        let iconName = isLocked ? "lock.fill" : "lock.open"
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Lock Input")
        }
        
        lockMenuItem?.title = isLocked ? "Unlock Me!" : "Lock Me!"
    }
    
    @objc func exitApp() {
        NSApplication.shared.terminate(self)
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.action = #selector(showMenu)
        }
        
        let menu = NSMenu()
        lockMenuItem = NSMenuItem(title: "Lock Me!", action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(lockMenuItem!)
        menu.addItem(NSMenuItem(title: "Exit", action: #selector(exitApp), keyEquivalent: ""))
        statusItem?.menu = menu
    }

    private func setupEventTap() {
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let eventTap = eventTap else {
            Logger.shared.log("Failed to create event tap.")
            showErrorAlert(message: "Failed to create event tap.")
            return
        }
        
        Logger.shared.log("Successfully created event tap.")
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func cleanupEventTap() {
        guard let runLoopSource = runLoopSource else { return }
                
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        self.runLoopSource = nil
        
        guard let eventTap = eventTap else { return }
                
        CGEvent.tapEnable(tap: eventTap, enable: false)
        self.eventTap = nil
        Logger.shared.log("Cleaned up event tap.")
    }
    
    private func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options)
        
        Logger.shared.log("Checking accessibility permissions. Trusted: \(isTrusted)")
        
        if !isTrusted {
            Logger.shared.log("App is not trusted. Prompting user for permissions.")
            showErrorAlert(message: "Accessibility permissions are required to lock/unlock the keyboard. Please grant access in System Preferences > Security & Privacy > Accessibility.")
            waitForAccessibilityPermissions()
        }
    }
    
    private func waitForAccessibilityPermissions() {
        Logger.shared.log("Waiting for accessibility permissions...")
        
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let isTrusted = AXIsProcessTrusted()
            Logger.shared.log("Accessibility permissions check. Trusted: \(isTrusted)")
            
            
            if isTrusted {
                timer.invalidate()
                Logger.shared.log("Permissions granted. Setting up event tap.")
                self.setupEventTap()
            }
        }
    }
    
    private func showErrorAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}

func handleKeyCombination(_ instance: AppDelegate, _ keyCode: Int64, _ flags: UInt64) -> Bool {
    let commandKeyPressed = (flags & CGEventFlags.maskCommand.rawValue) != 0
    let keyL = keyCode == kVK_ANSI_L
    let keyQ = keyCode == kVK_ANSI_Q
    
    if commandKeyPressed && keyL {
        instance.toggleLock()
        return true
    } else if commandKeyPressed && keyQ {
        instance.exitApp()
        return true
    }
    
    return false
}

func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let instance = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()
    
    // Check for Command + L key combination
    if type == .keyDown {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let handled = handleKeyCombination(instance, keyCode, flags)
        if handled {
            return nil
        }
    }
    
    return instance.isLocked ? nil : Unmanaged.passUnretained(event)
}
