import Cocoa

class Background: NSView {
    
    @IBOutlet var instructions: NSTextField!
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let context = NSGraphicsContext.current?.cgContext
        let path = CGMutablePath()
        path.addRect(bounds)
        context?.setFillColor(NSColor.darkGray.cgColor)
        context?.addPath(path)
        context?.drawPath(using:.fill)
    }
    
    override func viewDidMoveToWindow() {
        instructions!.stringValue =
        "1,2, scrollWheel+RMB :  Change flux level\n" +
        "Arrows, Left Mouse : Rotate\n" +
        "PgUp, PgDn, scrollWheel : Distance\n" +
        "V: Draw Style"
    }
}
