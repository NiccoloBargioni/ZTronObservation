import XCTest
import SwiftGraph
@testable import ZTronObservation



final class ZTronFrameWorkTests: XCTestCase {
    func testBroadcastMediator() throws {
        let mediator = BroadcastMediator()
        
        let topbar = TopbarComponent()
        let topbarInteractions = TopbarInteractionsManager(owner: topbar, mediator: mediator)
        topbar.delegate = topbarInteractions
        
        let gallery = GalleryComponent(initialGallery: "cosmic way")
        let galleryInteractions = GalleryInteractionsManager(owner: gallery, mediator: mediator)
        gallery.delegate = galleryInteractions
        
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
    
    
    init(delegate: (any InteractionsManager)? = nil) {
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
    
    func getDelegate() -> (any InteractionsManager)? {
        return self.delegate
    }
    
    func setDelegate(_ interactionsManager: (any ZTronObservation.InteractionsManager)?) {
        if let delegate = self.delegate {
            delegate.detach()
        }
        
        self.delegate = interactionsManager
        
        if let interactionsManager = interactionsManager {
            interactionsManager.setup()
        }
    }
}


fileprivate final class TopbarInteractionsManager: InteractionsManager, @unchecked Sendable {
    weak private var owner: TopbarComponent?
    weak private var mediator: BroadcastMediator?
    
    required init(owner: TopbarComponent, mediator: BroadcastMediator) {
        self.owner = owner
        self.mediator = mediator
    }
    
    func notify(args: BroadcastArgs) {
        guard let owner = self.owner else { return }
        print("\(owner.id) received notification")
    }
    
    func setup() {
        guard let owner = self.owner else { return }
        print("Topbar will register")
        self.mediator?.register(owner)
    }
    
    func willCheckout(args: BroadcastArgs) {
        print("Another component left the subsystem")
    }
    
    func getOwner() -> (any ZTronObservation.Component)? {
        return self.owner
    }
    
    func getMediator() -> (any ZTronObservation.Mediator)? {
        return self.mediator
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
    
    
    init(initialGallery: String, delegate: (any InteractionsManager)? = nil) {
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
    
    func setDelegate(_ interactionsManager: (any ZTronObservation.InteractionsManager)?) {
        if let delegate = self.delegate {
            delegate.detach()
        }
        
        self.delegate = interactionsManager
        
        if let interactionsManager = interactionsManager {
            interactionsManager.setup()
        }
    }
    
    func getDelegate() -> (any InteractionsManager)? {
        return self.delegate
    }
}


fileprivate class GalleryInteractionsManager: InteractionsManager, @unchecked Sendable {
    weak private var owner: GalleryComponent?
    weak private var mediator: BroadcastMediator?
    
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
    
    init(owner: GalleryComponent, mediator: BroadcastMediator) {
        self.owner = owner
        self.mediator = mediator
    }
    
    func notify(args: BroadcastArgs) {
        guard let owner = self.owner else { return }
        print("\(owner.id) received notification")
        
        if let topbar = (args.getSource() as? TopbarComponent) {
            print("\(owner.id) received notification from \(topbar.id)")
            guard let images = self.imagesByGalleries[topbar.getCurrentGalleryID()] else { return }
            
            self.owner?.setImages(to: images)
        }
    }
    
    func setup() {
        guard let owner = self.owner else { return }
        print("\(owner.id) will register")
        self.mediator?.register(owner)
    }
    
    func willCheckout(args: ZTronObservation.BroadcastArgs) {
        print("Another component left the subsystem")
    }
    
    func getOwner() -> (any ZTronObservation.Component)? {
        return self.owner
    }
    
    func getMediator() -> (any ZTronObservation.Mediator)? {
        return self.mediator
    }    
}

