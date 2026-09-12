import AppKit

let application = NSApplication.shared
let delegate = AppDelegate(arguments: Array(CommandLine.arguments.dropFirst()))
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
