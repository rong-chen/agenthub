import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let width = min(1440.0, screenFrame.width * 0.90)
      let height = min(920.0, screenFrame.height * 0.90)
      let x = screenFrame.origin.x + (screenFrame.width - width) / 2.0
      let y = screenFrame.origin.y + (screenFrame.height - height) / 2.0
      self.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    } else {
      self.setFrame(NSRect(x: 100, y: 100, width: 1440, height: 900), display: true)
    }
    self.center()
    self.minSize = NSSize(width: 960, height: 600)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
