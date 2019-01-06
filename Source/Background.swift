import Cocoa

class Background: NSView {
    override var isFlipped: Bool { return true }
    override var acceptsFirstResponder: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let context = NSGraphicsContext.current?.cgContext
        let path = CGMutablePath()
        path.addRect(bounds)
        context?.setFillColor(NSColor.darkGray.cgColor)
        context?.addPath(path)
        context?.drawPath(using:.fill)
    }
    
    override func keyDown(with event: NSEvent) {
        super.keyDown(with: event)
        
        if event.keyCode == 53 { NSApplication.shared.terminate(self) } // esc key
        
        let keyCode = event.charactersIgnoringModifiers!.uppercased()
        switch keyCode {
        case "1" : vc.changeIsoValue(-0.001)
        case "2" : vc.changeIsoValue(+0.001)
        case "V" : control.drawStyle = Int32(1 - control.drawStyle)
        default : break
        }
    }
}
