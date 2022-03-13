//
//  ContentView.swift
//  TODO: Change Name
//  Grid_Template
//
//  Created by Rajshree Saraf on 19/01/22.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

// MARK: - View model for handling communication between the UI and ARView.
class ViewModel: ObservableObject {
    let uiSignal = PassthroughSubject<UISignal, Never>()
    @Published var gridShow = false

    enum UISignal {
        case grid
        case resetAnchor

    }
}

struct ContentView : View {
    @StateObject var viewModel: ViewModel
    
    var body: some View {
        
        ZStack {
            // AR View.
            ARViewContainer(viewModel: viewModel)
            
            // UI.
            Button {
                viewModel.uiSignal.send(.grid)
            } label: {
                Label("Layout grid", systemImage: "lock")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
                    .opacity(viewModel.gridShow ? 1.0 : 0.35)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding()
            
            
            Button {
                viewModel.uiSignal.send(.resetAnchor)
            } label: {
                Label("Reset", systemImage: "gobackward")
                    .font(.system(.title))
                    .foregroundColor(.white)
                    .labelStyle(IconOnlyLabelStyle())
                    .frame(width: 44, height: 44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding()
            
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}

struct ARViewContainer: UIViewRepresentable {
    let viewModel: ViewModel
    
    func makeUIView(context: Context) -> ARView {
        SimpleARView(frame: .zero, viewModel: viewModel)
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}

class SimpleARView: ARView, ARSessionDelegate {
    var viewModel: ViewModel
    var arView: ARView { return self }
    var subscriptions = Set<AnyCancellable>()
    
    // Dictionary for tracking image anchors.
   // var imageAnchorToEntity: [ARImageAnchor: AnchorEntity] = [:]
    
    // TODO: Declare Materials for Array if any
    
    // TODO: Declare entities
    var gridEntity: gridObject!
    var layoutOne: layoutEntityOne!

    
    var parentEntity: Entity?
    var planeAnchor: AnchorEntity?
    
    var lastUpdateTime = Date()
    
    init(frame: CGRect, viewModel: ViewModel) {
        self.viewModel = viewModel
        super.init(frame: frame)
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: CGRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        setupScene()
    }
    
    func setupScene() {
        // Setup world tracking and plane detection.
        let configuration = ARWorldTrackingConfiguration()
        let configuration1 = ARWorldTrackingConfiguration()
        arView.renderOptions = [.disableDepthOfField, .disableMotionBlur]
        
        
        configuration.environmentTexturing = .automatic
        
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
            configuration.frameSemantics.insert(.personSegmentationWithDepth)
            print("✨✨✨✨✨✨✨✨")
        } else {
            print("ARWorldTrackingConfiguration: Does not support sceneReconstruction.🟥🟥🟥🟥")
        }
        
        
        
       var set = Set<ARReferenceImage>()
        
        // Setup target image A.
        if let detectionImage = makeDetectionImage(named: "seventeen_infinity-01.png",
                                                   referenceName: "IMAGE_ALPHA",
                                                   physicalWidth: 0.2) {
            set.insert(detectionImage)
        }
        
        // Setup target image B.
        //        if let detectionImage = makeDetectionImage(named: "zero_template-01.png",
        //                                                   referenceName: "IMAGE_ART",
        //                                                   physicalWidth: 0.2) {
        //            set.insert(detectionImage)
        //        }
        
        
        // Add target images to configuration.
        configuration1.detectionImages = set
        configuration1.maximumNumberOfTrackedImages = 1
        configuration.planeDetection = [.horizontal, .vertical]
        
        // Run configuration.
         arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
      // use below for image anchor
        //  arView.session.run(configuration1, options: [.resetTracking, .removeExistingAnchors])
        
        
        
        // Called every frame.
        scene.subscribe(to: SceneEvents.Update.self) { event in
            // Call renderLoop method on every frame.
            self.renderLoop()
        }.store(in: &subscriptions)
        
        // Process UI signals.
        viewModel.uiSignal.sink { [weak self] in
            self?.processUISignal($0)
        }.store(in: &subscriptions)
        
        // Respond to collision events.
        arView.scene.subscribe(to: CollisionEvents.Began.self) { event in

            print("💥 Collision with \(event.entityA.name) & \(event.entityB.name)")

        }.store(in: &subscriptions)
        
        
        // Set session delegate.
        arView.session.delegate = self
        
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
       // arView.debugOptions = [.showSceneUnderstanding]
        configuration.frameSemantics.insert(.personSegmentationWithDepth)
        
        // Setup tap gesture.
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        
        // TODO: hide/show physics colliders
      //  arView.debugOptions = [.showPhysics]
        
    }
    
    func makeDetectionImage(named: String, referenceName: String, physicalWidth: CGFloat) -> ARReferenceImage? {
        guard let targetImage = UIImage(named: named)?.cgImage else {
            print("❗️ Error loading target image:", named)
            return nil
        }
        
        let arReferenceImage  = ARReferenceImage(targetImage, orientation: .up, physicalWidth: physicalWidth)
        arReferenceImage.name = referenceName
        
        return arReferenceImage
    }
    
    func processUISignal(_ signal: ViewModel.UISignal) {
        
        // UI cases
        switch signal {
        case .grid:
            viewModel.gridShow.toggle()
            setupGrid(anchorEntity: planeAnchor!)
            
        case .resetAnchor:
            resetPlaneAnchor()
            

        }
        
    }
    
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        anchors.compactMap { $0 as? ARImageAnchor }.forEach {
            
            guard let referenceImageName = $0.referenceImage.name else { return }
            
            let anchorEntity = AnchorEntity(world: $0.transform)
            arView.scene.addAnchor(anchorEntity)

            parentEntity = makeBoxMarker(color: .clear)
            parentEntity?.transform = Transform.identity
            anchorEntity.addChild(parentEntity!);

    
            
        }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer? = nil) {
        guard let touchInView = sender?.location(in: self),
              let hitEntity = arView.entity(at: touchInView) else { return }

        print("👇 Did tap \(hitEntity.name)")
        print("MOVE TRUE")
       
        // Respond to tap event.
       // hitEntity.scale *= [1.2, 1.2, 1.2]
    }
    
    func setupEntities(anchorEntity: Entity) {
        
       
        
        let scale: Float = 2.5
        // TODO: Change name and add more, if any
     
        layoutOne     = layoutEntityOne(name: "layoutOne")

        
        
        // layoutOne.animate(true)
        layoutOne.scale = [scale, scale, scale]
        arView.installGestures([.translation, .scale, .rotation], for: layoutOne)


        anchorEntity.addChild(layoutOne)


        // TODO: Setup Grid model
        gridEntity = gridObject(name: "grid")
        
    }
    
    func setupGrid(anchorEntity: Entity) {
        
        if viewModel.gridShow == true {
           // anchorEntity.addChild(gridEntity!)
            layoutOne?.animate(true)
            print ("ADDED ✨ LINE TWO")
        }
        else {
           // gridEntity?.removeFromParent()
            layoutOne?.animate(false)
            print ("REMOVED 🚧 LINE TWO")
        }
        
    }
    
    
    func resetPlaneAnchor() {
        
        planeAnchor = AnchorEntity(plane: [.horizontal, .vertical])
        arView.scene.addAnchor(planeAnchor!)
        
        setupEntities(anchorEntity: planeAnchor!)
        
    }
    
    
    func renderLoop() {
     
      
        
    }
    
    func makeBoxMarker(color: UIColor) -> Entity {
        let boxMesh   = MeshResource.generateBox(size: 0.025, cornerRadius: 0.002)
        let material  = SimpleMaterial(color: color, isMetallic: false)
        return ModelEntity(mesh: boxMesh, materials: [material])
    }
    
    func map(minRange:Float, maxRange:Float, minDomain:Float, maxDomain:Float, value:Float) -> Float {
        return minDomain + (maxDomain - minDomain) * (value - minRange) / (maxRange - minRange)
    }
    
}

// TODO: Make copy of class for more layout pieces
class layoutEntityOne: Entity, HasModel, HasCollision {
    let model: Entity
    let model1: Entity
    
    init(name: String) {
        // TODO: Change Model
        model = try! Entity.load(named: "57newnew_animation2")
        model1 = try! Entity.load(named: "57deets")
        model.name = name
        model.generateCollisionShapes(recursive: true)
        model1.generateCollisionShapes(recursive: true)
        
        //model.position.y =
        let boxMesh = MeshResource.generateBox(size: 0.23)
        let material = OcclusionMaterial()
        //let material  = SimpleMaterial(color: .red, isMetallic: false)
        let occlusionBox1 = ModelEntity(mesh: boxMesh, materials: [material])

               occlusionBox1.name = "Occlusion1"
               occlusionBox1.position.y = -0.115
    
        
        
        print(model.availableAnimations.count, "animation availale 🧠👀🧠👀🧠👀🧠");
        
        super.init()
        
    self.addChild(model)
        self.addChild(model1)
        self.addChild(occlusionBox1)
        
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
    // Play or stop animation.
    func animate(_ animate: Bool) {
        if animate {
                model.playAnimation((model.availableAnimations.first?.repeat())!)
        
                           } else {
                               model.stopAllAnimations()
                           }
    }
}



// TODO: Add animation from layout if required
class gridObject: Entity, HasModel, HasCollision {
    let model: Entity
    
    init(name: String) {
        // TODO: Change Model
        model = try! Entity.load(named: "57deets.usdz")
        model.name = name
        model.generateCollisionShapes(recursive: true)
        
        super.init()
        
        self.addChild(model)
    }
    
    required init() {
        fatalError("init() has not been implemented")
    }
    
}
