import XCTest
import SwiftGraph
@testable import ZTronObservation


final class MSATests: XCTestCase {
    func testMSAMediator() throws {
        let mediator = MSAMediator()
        
        let gallery = GalleryComponent(initialGallery: "cosmic way")
        let galleryInteractions = GalleryInteractionsManager(owner: gallery, mediator: mediator)
        gallery.delegate = galleryInteractions

        
        let topbar = TopbarComponent()
        let topbarInteractions = TopbarInteractionsManager(owner: topbar, mediator: mediator)
        topbar.delegate = topbarInteractions
        
        topbar.setCurrentGallery(to: 3)
        
        topbar.delegate?.detach()
        gallery.delegate?.detach()
    }
}

// MARK: TEST SUBCLASSING

fileprivate class TopbarComponent: Component {
    static func == (lhs: TopbarComponent, rhs: TopbarComponent) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    var id: String = "topbar"
    var delegate: (any InteractionsManager)? {
        willSet {
            guard let delegate = self.delegate else { return }
            delegate.detach()
        }
    
        didSet {
            guard let delegate = self.delegate else { return }
            delegate.setup()
        }
    }
    
    private let subgalleries = ["cosmic way", "journey into space", "astrocade", "polar peak", "underground", "kepler", "astrocade"]
    private var currentGallery: Int = 0
    
    
    init(delegate: (any MSAInteractionsManager)? = nil) {
        self.delegate = delegate
    }
    
    func getCurrentGallery() -> Int {
        return self.currentGallery
    }
    
    func getCurrentGalleryID() -> String {
        return self.subgalleries[self.currentGallery]
    }
    
    func setCurrentGallery(to nextGallery: Int) {
        assert(nextGallery >= 0 && nextGallery < self.subgalleries.count)
        
        self.currentGallery = nextGallery
        self.delegate?.pushNotification(eventArgs: BroadcastArgs(source: self))
    }
    
    deinit {
        self.delegate?.detach()
    }
}


fileprivate class TopbarInteractionsManager: MSAInteractionsManager {
    weak var owner: TopbarComponent?
    weak var mediator: MSAMediator?
    
    required init(owner: TopbarComponent, mediator: MSAMediator) {
        self.owner = owner
        self.mediator = mediator
    }
    
    func notify(args: BroadcastArgs) {
        guard let owner = self.owner else { return }
        print("\(owner.id) received notification")
    }
        
    func willCheckout(args: BroadcastArgs) {
        print("Another component left the subsystem")
    }
    
    func peerDiscovered(eventArgs: ZTronObservation.BroadcastArgs) {  
        print("\(String(describing: Self.self)): \(#function) with arg of type \(String(describing: type(of: eventArgs.getSource())))")

    }
    
    func peerDidAttach(eventArgs: ZTronObservation.BroadcastArgs) {
        print("\(String(describing: Self.self)): \(#function) with arg of type \(String(describing: type(of: eventArgs.getSource())))")

    }
}



fileprivate class GalleryComponent: Component {
    fileprivate let id: String
    fileprivate var imagesInThisGallery = [String].init()
    fileprivate var delegate: (any InteractionsManager)? {
        willSet {
            guard let delegate = self.delegate else { return }
            delegate.detach()
        }
    
        didSet {
            guard let delegate = self.delegate else { return }
            delegate.setup()
        }
    }
    
    
    init(initialGallery: String, delegate: (any MSAInteractionsManager)? = nil) {
        self.id = "gallery \(initialGallery)"
        self.delegate = delegate
    }
    
    static func == (lhs: GalleryComponent, rhs: GalleryComponent) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    
    func setImages(to images: [String]) {
        self.imagesInThisGallery = images
        
        print("Images changed to ")
        print(images)
    }
    
    deinit {
        self.delegate?.detach()
    }
}


fileprivate class GalleryInteractionsManager: MSAInteractionsManager {
    weak var owner: GalleryComponent?
    weak var mediator: MSAMediator?
    
    let imagesByGalleries: [String: [String]] = [
        "afterlife": [
            "AfterlifeDoor"
        ],
        
        "astrocade": [
            "AstrocadeClaw1",
            "AstrocadeLamppost",
            "AstrocadeSign",
            "AstrocadeTicketVendorShelf",
            "AstrocadeUFO"
        ],
        
        "cosmic way": [
            "CraterCakes",
            "SpaceDepot",
            "SpawnPolice",
            "SpawnShutter",
            "SpawnSpacelandSign"
        ],
        
        "journey into space": [
            "AstrocadeSpaceman",
            "BlueBolts",
            "CarTrapLocation1",
            "MoonShakeLocation2",
            "MoonShakeTerrace",
            "TuffNuff1",
            "TuffNuff2"
        ],
        
        "kepler": [
            "Chromosphere1",
            "Chromosphere2",
            "ConeLord",
            "KeplerDJBooth",
            "OctonianHunter",
            "SpaceChomp"
        ],
        
        "polar peak": [
            "Hyperslopes",
            "Hyperslopes2",
            "PolarA01",
            "PolarA01Location2",
            "PolarCounter",
            "PolarDragonBreathTrap",
            "PolarEntranceCave",
            "PolarEntranceYeti",
            "PolarFountains",
            "PolarPortal",
            "PolarRollerCoasterEmployeeOfTheMonth",
            "PolarRollerCoasterTrashcan",
            "PolarYeti",
            "PolarYeti1",
            "PortalCookies"
        ],
        
        "underground": [
            "UndergroundAlienShutter",
            "UndergroundArcadeShutters",
            "UndergroundAstronautCutter",
            "UndergroundCeiling",
            "UndergroundEmployeeOnlyRacing",
            "UndergroundEmployeesChair1",
            "UndergroundEmployeesOnlyDesk",
            "UndergroundFountains",
            "UndergroundKeplerLadder1",
            "UndergroundMurales",
            "UndergroundRedPipe",
            "UndergroundShredder2",
            "UndergroundShredderShelf",
            "UndergroundYeti"
        ]
    ]
    
    init(owner: GalleryComponent, mediator: MSAMediator) {
        self.owner = owner
        self.mediator = mediator
    }
    
    func notify(args: BroadcastArgs) {
        guard let owner = self.owner else { return }
        
        if let topbar = (args.getSource() as? TopbarComponent) {
            guard let images = self.imagesByGalleries[topbar.getCurrentGalleryID()] else { return }
            
            self.owner?.setImages(to: images)
        }
    }
    
    func willCheckout(args: ZTronObservation.BroadcastArgs) {
        print("Another component left the subsystem")
    }
    
    func peerDiscovered(eventArgs: ZTronObservation.BroadcastArgs) {
        print("\(String(describing: Self.self)): \(#function) with arg of type \(String(describing: type(of: eventArgs.getSource())))")
        guard let owner = self.owner else { fatalError() }
        
        if let component = (eventArgs.getSource() as? TopbarComponent) {
            self.mediator?.signalInterest(owner, to: component)
        }
    }
    
    func peerDidAttach(eventArgs: ZTronObservation.BroadcastArgs) {
        print("\(String(describing: Self.self)): \(#function)")

        guard let owner = self.owner else { fatalError() }
        
        if let topbar = (eventArgs.getSource() as? TopbarComponent) {
            guard let imagesSet = self.imagesByGalleries[topbar.getCurrentGalleryID()] else { fatalError() }
            owner.setImages(to: imagesSet)
        }
        
    }
}

