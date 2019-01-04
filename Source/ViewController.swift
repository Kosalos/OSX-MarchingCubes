import AppKit

@objc(VCDelegate)
protocol VCDelegate: NSObjectProtocol {
    func update(_ controller: ViewController)
    func viewController(_ viewController: ViewController, willPause pause: Bool)
}

@objc(ViewController)
class ViewController: NSViewController {
    
    @IBOutlet var instructions: NSTextField!
    
    weak var delegate: VCDelegate?
    private(set) var timeSinceLastDraw: TimeInterval = 0.0
    
    var interval: Int = 0
    var _displayLink: CVDisplayLink?
    var _displaySource: DispatchSourceUserDataAdd?
    private var _firstDrawOccurred: Bool = false
    private var _timeSinceLastDrawPreviousTime: CFTimeInterval = 0.0
    private var _gameLoopPaused: Bool = false
    private var _renderer: Renderer!
    
    deinit {
        if _displayLink != nil {
            self.stopGameLoop()
        }
    }
    
    private let dispatchGameLoop: CVDisplayLinkOutputCallback = {
        displayLink, now, outputTime, flagsIn, flagsOut, displayLinkContext in
        
        let source = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        source.add(data: 1)
        return kCVReturnSuccess
    }
    
    private func initCommon() {
        _renderer = Renderer()
        self.delegate = _renderer
     
        _displaySource = DispatchSource.makeUserDataAddSource(queue: DispatchQueue.main)
        _displaySource!.setEventHandler {[weak self] in
            self?.gameloop()
        }
        _displaySource!.resume()
        
        var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink)
        assert(cvReturn == kCVReturnSuccess)
        
        cvReturn = CVDisplayLinkSetOutputCallback(_displayLink!, dispatchGameLoop, Unmanaged.passUnretained(_displaySource!).toOpaque())
        assert(cvReturn == kCVReturnSuccess)
        
        cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink!, CGMainDisplayID () )
        assert(cvReturn == kCVReturnSuccess)
        
        interval = 1
    }
    
    @objc func _windowWillClose(_ notification: Notification) {
        if notification.object as AnyObject? === self.view.window {
            CVDisplayLinkStop(_displayLink!)
            _displaySource!.cancel()
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.initCommon()
    }
    
    @IBOutlet weak var renderView: AAPLView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        renderView.delegate = _renderer
        _renderer.configure(renderView)
        CVDisplayLinkStart(_displayLink!)
    }
    
    @objc func gameloop() {
        delegate?.update(self)
        renderView.display()
    }
    
    func stopGameLoop() {
        if _displayLink != nil {
            CVDisplayLinkStop(_displayLink!)
            _displaySource!.cancel()
            
            _displayLink = nil
            _displaySource = nil
        }
    }
    
    var paused: Bool {
        set(pause) {
            if _gameLoopPaused == pause {
                return
            }
            
            if _displayLink != nil {
                // inform the delegate we are about to pause
                delegate?.viewController(self, willPause: pause)
                
                if pause {
                    CVDisplayLinkStop(_displayLink!)
                } else {
                    CVDisplayLinkStart(_displayLink!)
                }
            }
        }
        
        get {
            return _gameLoopPaused
        }
    }
    
    @objc func didEnterBackground(_ notification: Notification) {
        self.paused = true
    }
    
    @objc func willEnterForeground(_ notification: Notification) {
        self.paused = false
    }
}
