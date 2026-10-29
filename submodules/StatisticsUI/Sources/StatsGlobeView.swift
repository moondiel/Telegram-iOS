import Foundation
import UIKit
import SceneKit
import Display
import UIKitRuntimeUtils
import TelegramPresentationData
import TelegramStringFormatting

// Subscriber Globe: the globe itself, a dotted Earth in the theme's colours. See
// docs/subscriber-globe/README.md.
//
// It is drawn with SceneKit, as Telegram's Premium star is (`PremiumStarComponent`): a sphere for the
// sea, a small disc on its surface for every dot of land (`StatsGlobeLand.swift`), and a disc in the
// accent colour for every country, with a ring that pings outward. The camera is orthographic, so the
// globe's size on screen is exactly `radius` points. Country labels are ordinary views laid over it,
// placed where SceneKit projects their marker and faded out as the marker turns away.

/// The colours of the globe, from the theme.
struct StatsGlobeColors: Equatable {
    /// What the globe sits on, so its edge can fade into it.
    let background: UIColor
    let sea: UIColor
    let land: UIColor
    let accent: UIColor
    let labelBackground: UIColor
    let labelText: UIColor
    let labelSecondaryText: UIColor

    /// `background` is what the globe sits on: the statistics card by default, or the sheet.
    init(theme: PresentationTheme, background: UIColor? = nil) {
        let background = background ?? theme.list.itemBlocksBackgroundColor
        let accent = theme.list.itemAccentColor
        self.background = background
        self.accent = accent
        if theme.overallDarkAppearance {
            self.sea = background.mixedWith(accent, alpha: 0.14)
            self.land = background.mixedWith(theme.list.itemPrimaryTextColor, alpha: 0.45)
        } else {
            self.sea = background.mixedWith(accent, alpha: 0.07)
            self.land = background.mixedWith(accent, alpha: 0.42)
        }
        self.labelBackground = theme.list.plainBackgroundColor
        self.labelText = theme.list.itemPrimaryTextColor
        self.labelSecondaryText = theme.list.itemSecondaryTextColor
    }
}

/// Where the globe is turned: the latitude and longitude at its centre, in radians.
struct StatsGlobeOrientation: Equatable {
    var latitude: CGFloat
    var longitude: CGFloat
}

private let maxLatitude: CGFloat = 70.0 * CGFloat.pi / 180.0
/// Radians per second of the slow turn while nobody touches the globe.
private let idleSpinSpeed: CGFloat = 0.12
/// How long the globe waits after a touch before it starts turning on its own again.
private let idleSpinDelay: Double = 2.0

private func unitVector(latitude: Float, longitude: Float) -> SIMD3<Float> {
    return SIMD3<Float>(cos(latitude) * sin(longitude), sin(latitude), cos(latitude) * cos(longitude))
}

/// Flat discs lying on the unit sphere, one per centre, as one geometry: thousands of dots cost one
/// draw call.
private func makeSurfaceDiscs(centers: [SIMD3<Float>], radius: Float, elevation: Float, segments: Int) -> SCNGeometry {
    var vertices: [SCNVector3] = []
    vertices.reserveCapacity(centers.count * (segments + 1))
    var indices: [UInt32] = []
    indices.reserveCapacity(centers.count * segments * 3)

    for center in centers {
        // East and north at the dot. No dot sits exactly on a pole.
        let east = simd_normalize(SIMD3<Float>(center.z, 0.0, -center.x))
        let north = simd_cross(center, east)
        let base = UInt32(vertices.count)
        let middle = center * elevation
        vertices.append(SCNVector3(middle.x, middle.y, middle.z))
        for segment in 0 ..< segments {
            let angle = Float(segment) / Float(segments) * 2.0 * Float.pi
            let point = middle + (east * cos(angle) + north * sin(angle)) * radius
            vertices.append(SCNVector3(point.x, point.y, point.z))
        }
        for segment in 0 ..< segments {
            indices.append(base)
            indices.append(base + 1 + UInt32(segment))
            indices.append(base + 1 + UInt32((segment + 1) % segments))
        }
    }

    let source = SCNGeometrySource(vertices: vertices)
    let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    return SCNGeometry(sources: [source], elements: [element])
}

/// The land, built once: every globe draws a copy, which shares the vertices and has its own colour.
private let landGeometry: SCNGeometry = {
    let centers = statsGlobeLandDots.map { unitVector(latitude: $0.latitude, longitude: $0.longitude) }
    // A third of the space between dots, so the grid reads as dots and not as a mesh.
    return makeSurfaceDiscs(centers: centers, radius: 0.0105, elevation: 1.002, segments: 6)
}()

private func flatMaterial(color: UIColor) -> SCNMaterial {
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = color
    material.isDoubleSided = true
    return material
}

/// A country's label: a dot in the country's colour, as in the chart's legend, its name and share.
private final class GlobeLabelView: UIView {
    private let dotView: UIView
    private let label: UILabel
    /// Whether the label has room, eased so labels do not pop when they start to overlap.
    var visibility: CGFloat = 0.0

    override init(frame: CGRect) {
        self.dotView = UIView()
        self.dotView.layer.cornerRadius = 4.0
        self.label = UILabel()
        self.label.numberOfLines = 1

        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        self.layer.shadowRadius = 4.0
        self.layer.shadowOpacity = 0.18
        self.layer.shadowColor = UIColor.black.cgColor
        self.addSubview(self.dotView)
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(name: String, share: Int, color: UIColor, colors: StatsGlobeColors) {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: name, attributes: [.font: Font.medium(12.0), .foregroundColor: colors.labelText]))
        text.append(NSAttributedString(string: "  \(share)%", attributes: [.font: Font.regular(12.0), .foregroundColor: colors.labelSecondaryText]))
        self.label.attributedText = text
        self.dotView.backgroundColor = color

        let textSize = self.label.sizeThatFits(CGSize(width: 240.0, height: 40.0))
        let size = CGSize(width: ceil(textSize.width) + 8.0 + 6.0 + 9.0, height: 22.0)
        self.dotView.frame = CGRect(x: 8.0, y: floor((size.height - 8.0) / 2.0), width: 8.0, height: 8.0)
        self.label.frame = CGRect(origin: CGPoint(x: 8.0 + 8.0 + 6.0, y: floor((size.height - textSize.height) / 2.0)), size: textSize)
        self.backgroundColor = colors.labelBackground
        self.layer.cornerRadius = size.height / 2.0
        self.bounds = CGRect(origin: CGPoint(), size: size)
        // A fixed path, so the moving labels do not render their shadow off-screen every frame.
        self.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: CGPoint(), size: size), cornerRadius: size.height / 2.0).cgPath
    }
}

/// The globe: drag to turn it, and in the sheet pinch or double-tap to zoom.
final class StatsGlobeView: UIView, UIGestureRecognizerDelegate {
    let countries: ChannelStatsCountries
    private(set) var colors: StatsGlobeColors
    /// In the sheet the globe zooms and drags go any way. In the card it only takes horizontal
    /// drags, so the list still scrolls over it.
    let isExpanded: Bool

    /// Called on a tap; the card opens the globe sheet.
    var tapped: (() -> Void)?

    private let glowLayer: CAGradientLayer
    private let sceneView: SCNView
    private let shadeLayer: CAGradientLayer
    private let labelsView: UIView
    private var labelViews: [GlobeLabelView] = []
    private var labelNames: [String] = []

    private let globeNode: SCNNode
    private let seaNode: SCNNode
    private let landNode: SCNNode
    private var markerNodes: [SCNNode] = []
    private var ringNodes: [SCNNode] = []
    private let cameraNode: SCNNode

    /// Points from the globe's centre to its edge at zoom 1.
    var radius: CGFloat = 100.0 {
        didSet {
            self.setNeedsLayout()
        }
    }
    private(set) var zoom: CGFloat = 1.0

    var orientation: StatsGlobeOrientation
    private var velocity = CGPoint()
    private var isTracking = false
    private var lastInteraction: Double = 0.0
    private var spinFactor: CGFloat = 1.0
    private var zoomAtPinchStart: CGFloat = 1.0
    private var zoomAnimation: (from: CGFloat, to: CGFloat, start: Double)?
    private var turnAnimation: (from: StatsGlobeOrientation, to: StatsGlobeOrientation, start: Double, duration: Double)?

    private var displayLink: SharedDisplayLinkDriver.Link?
    /// The globe's circle the halo and the edge shading were last laid out for.
    private var shadedGlobeFrame: CGRect?

    /// Stops the globe, for example while a sheet with another globe covers it.
    var isPaused = false {
        didSet {
            if self.isPaused != oldValue {
                self.updateIsRunning()
            }
        }
    }

    init(countries: ChannelStatsCountries, colors: StatsGlobeColors, strings: PresentationStrings, isExpanded: Bool, orientation: StatsGlobeOrientation? = nil) {
        self.countries = countries
        self.colors = colors
        self.isExpanded = isExpanded

        // The globe opens over the largest audience.
        if let orientation {
            self.orientation = orientation
        } else if let top = countries.countries.first {
            self.orientation = StatsGlobeOrientation(latitude: max(-maxLatitude, min(maxLatitude, CGFloat(top.latitude * Double.pi / 180.0) - 0.15)), longitude: CGFloat(top.longitude * Double.pi / 180.0))
        } else {
            self.orientation = StatsGlobeOrientation(latitude: 0.5, longitude: 0.5)
        }

        self.glowLayer = CAGradientLayer()
        self.glowLayer.type = .radial
        self.glowLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.glowLayer.endPoint = CGPoint(x: 1.0, y: 1.0)

        self.sceneView = SCNView(frame: CGRect(), options: nil)
        self.sceneView.backgroundColor = .clear
        self.sceneView.isOpaque = false
        self.sceneView.antialiasingMode = .multisampling4X
        self.sceneView.preferredFramesPerSecond = 60
        self.sceneView.isUserInteractionEnabled = false

        self.shadeLayer = CAGradientLayer()
        self.shadeLayer.type = .radial
        self.shadeLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.shadeLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.shadeLayer.masksToBounds = true

        self.labelsView = UIView()
        self.labelsView.isUserInteractionEnabled = false

        let scene = SCNScene()
        self.globeNode = SCNNode()
        scene.rootNode.addChildNode(self.globeNode)

        let sea = SCNSphere(radius: 1.0)
        sea.segmentCount = 72
        self.seaNode = SCNNode(geometry: sea)
        self.seaNode.renderingOrder = 0
        self.globeNode.addChildNode(self.seaNode)

        self.landNode = SCNNode(geometry: landGeometry.copy() as? SCNGeometry)
        self.landNode.renderingOrder = 1
        self.globeNode.addChildNode(self.landNode)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.zNear = 0.1
        camera.zFar = 10.0
        self.cameraNode = SCNNode()
        self.cameraNode.camera = camera
        self.cameraNode.position = SCNVector3(0.0, 0.0, 3.0)
        scene.rootNode.addChildNode(self.cameraNode)

        super.init(frame: CGRect())

        self.clipsToBounds = true
        self.layer.addSublayer(self.glowLayer)
        self.addSubview(self.sceneView)
        self.layer.addSublayer(self.shadeLayer)
        self.addSubview(self.labelsView)

        self.addMarkers(strings: strings)
        self.applyColors()

        // SceneKit uploads the geometry and compiles its shaders off the main thread first, so
        // opening the sheet or scrolling to the card does not stall on it; the globe fades in.
        self.sceneView.alpha = 0.0
        self.labelsView.alpha = 0.0
        let cameraNode = self.cameraNode
        self.sceneView.prepare([scene], completionHandler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.sceneView.scene = scene
                self.sceneView.pointOfView = cameraNode
                self.updateIsRunning()
                UIView.animate(withDuration: 0.2, animations: {
                    self.sceneView.alpha = 1.0
                    self.labelsView.alpha = 1.0
                })
            }
        })

        let pan = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        pan.delegate = self
        self.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:)))
        self.addGestureRecognizer(tap)
        if isExpanded {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(self.pinchGesture(_:)))
            self.addGestureRecognizer(pinch)
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(self.doubleTapGesture(_:)))
            doubleTap.numberOfTapsRequired = 2
            self.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)
        } else {
            // The back swipe keeps the screen's left edge, as on Telegram's map screens.
            self.interactiveTransitionGestureRecognizerTest = { point in
                return point.x > 44.0
            }
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    deinit {
        self.displayLink?.invalidate()
    }

    private func addMarkers(strings: PresentationStrings) {
        let total = max(1, self.countries.total)
        let locale = localeWithStrings(strings)
        for (index, country) in self.countries.countries.enumerated() {
            let color = channelStatsCountryColor(at: index)
            let center = unitVector(latitude: Float(country.latitude * Double.pi / 180.0), longitude: Float(country.longitude * Double.pi / 180.0))
            let orientation = simd_quatf(from: SIMD3<Float>(0.0, 1.0, 0.0), to: center)
            // Bigger audiences get bigger dots, by area.
            let share = Double(country.followers) / Double(total)
            let markerRadius = CGFloat(0.022 + 0.034 * sqrt(share))

            let ring = SCNNode(geometry: SCNCylinder(radius: markerRadius, height: 0.0005))
            ring.simdPosition = center * 1.003
            ring.simdOrientation = orientation
            ring.renderingOrder = 2
            ring.runAction(SCNAction.repeatForever(SCNAction.sequence([
                SCNAction.wait(duration: Double(index) * 0.23),
                SCNAction.group([
                    SCNAction.scale(to: 2.6, duration: 1.8),
                    SCNAction.fadeOut(duration: 1.8)
                ]),
                SCNAction.run { node in
                    node.scale = SCNVector3(1.0, 1.0, 1.0)
                    node.opacity = 0.55
                },
                SCNAction.wait(duration: Double(self.countries.countries.count - index) * 0.23)
            ])))
            ring.opacity = 0.55
            self.globeNode.addChildNode(ring)
            self.ringNodes.append(ring)

            let marker = SCNNode(geometry: SCNCylinder(radius: markerRadius, height: 0.0005))
            marker.simdPosition = center * 1.005
            marker.simdOrientation = orientation
            marker.renderingOrder = 3
            self.globeNode.addChildNode(marker)
            self.markerNodes.append(marker)

            let labelView = GlobeLabelView()
            let name = locale.localizedString(forRegionCode: country.code) ?? country.code
            labelView.update(name: name, share: Int((share * 100.0).rounded()), color: color, colors: self.colors)
            labelView.alpha = 0.0
            self.labelNames.append(name)
            self.labelsView.addSubview(labelView)
            self.labelViews.append(labelView)
        }
    }

    private func applyColors() {
        let colors = self.colors
        self.seaNode.geometry?.materials = [flatMaterial(color: colors.sea)]
        self.landNode.geometry?.materials = [flatMaterial(color: colors.land)]
        // Each country in its colour from the chart.
        for (index, node) in self.markerNodes.enumerated() {
            node.geometry?.materials = [flatMaterial(color: channelStatsCountryColor(at: index))]
        }
        for (index, node) in self.ringNodes.enumerated() {
            let material = flatMaterial(color: channelStatsCountryColor(at: index))
            material.writesToDepthBuffer = false
            node.geometry?.materials = [material]
        }
        // A soft halo around the globe, and the globe's edge fading into the card, so it reads as
        // a ball rather than a disc.
        self.glowLayer.colors = [colors.accent.withAlphaComponent(0.2).cgColor, colors.accent.withAlphaComponent(0.0).cgColor]
        self.shadeLayer.colors = [colors.background.withAlphaComponent(0.0).cgColor, colors.background.withAlphaComponent(0.0).cgColor, colors.background.withAlphaComponent(0.5).cgColor]
        self.shadeLayer.locations = [0.0, 0.6, 1.0]
    }

    func updateColors(_ colors: StatsGlobeColors) {
        if self.colors == colors {
            return
        }
        self.colors = colors
        self.applyColors()
        let total = max(1, self.countries.total)
        for (index, labelView) in self.labelViews.enumerated() where index < self.countries.countries.count {
            let share = Int((Double(self.countries.countries[index].followers) * 100.0 / Double(total)).rounded())
            labelView.update(name: self.labelNames[index], share: share, color: channelStatsCountryColor(at: index), colors: colors)
        }
        self.shadedGlobeFrame = nil
    }

    // MARK: Layout

    /// The globe's circle in this view's coordinates, at the current zoom.
    var globeFrame: CGRect {
        let radius = self.radius * self.zoom
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2.0, height: radius * 2.0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if self.sceneView.frame != self.bounds {
            self.sceneView.frame = self.bounds
        }
        self.labelsView.frame = self.bounds
        self.updateGeometry()
    }

    private func updateGeometry() {
        let size = self.bounds.size
        guard size.width > 0.0, size.height > 0.0 else {
            return
        }
        let radius = max(1.0, self.radius * self.zoom)

        // An orthographic scale is half the visible height, in scene units: the sphere's radius of 1
        // comes out at exactly `radius` points.
        if let camera = self.cameraNode.camera {
            let scale = Double(size.height / 2.0 / radius)
            if camera.orthographicScale != scale {
                camera.orthographicScale = scale
            }
        }

        // The gradients are redrawn whenever they are touched, so only when the globe moves or
        // grows, not on every frame of its turn.
        let globeFrame = self.globeFrame
        if self.shadedGlobeFrame != globeFrame {
            self.shadedGlobeFrame = globeFrame
            let glowRadius = radius * 1.2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.glowLayer.frame = CGRect(x: globeFrame.midX - glowRadius, y: globeFrame.midY - glowRadius, width: glowRadius * 2.0, height: glowRadius * 2.0)
            self.glowLayer.locations = [NSNumber(value: Double(radius / glowRadius)), 1.0]
            self.shadeLayer.frame = globeFrame
            self.shadeLayer.cornerRadius = radius
            CATransaction.commit()
        }

        self.globeNode.simdOrientation = simd_quatf(angle: Float(self.orientation.latitude), axis: SIMD3<Float>(1.0, 0.0, 0.0)) * simd_quatf(angle: Float(-self.orientation.longitude), axis: SIMD3<Float>(0.0, 1.0, 0.0))

        self.updateLabels()
    }

    private func updateLabels() {
        let globeFrame = self.globeFrame
        let radius = globeFrame.width / 2.0
        let rotation = simd_quatf(angle: Float(self.orientation.latitude), axis: SIMD3<Float>(1.0, 0.0, 0.0)) * simd_quatf(angle: Float(-self.orientation.longitude), axis: SIMD3<Float>(0.0, 1.0, 0.0))

        var taken: [CGRect] = []
        for (index, labelView) in self.labelViews.enumerated() where index < self.countries.countries.count {
            let country = self.countries.countries[index]
            let point = rotation.act(unitVector(latitude: Float(country.latitude * Double.pi / 180.0), longitude: Float(country.longitude * Double.pi / 180.0)) * 1.005)
            let screenPoint = CGPoint(x: globeFrame.midX + CGFloat(point.x) * radius, y: globeFrame.midY - CGFloat(point.y) * radius)
            let size = labelView.bounds.size
            let frame = CGRect(x: screenPoint.x - size.width / 2.0, y: screenPoint.y - size.height - 7.0 - radius * 0.03, width: size.width, height: size.height)

            // Fades out as the marker turns towards the edge, before it goes round the back.
            let facing = max(0.0, min(1.0, (CGFloat(point.z) - 0.2) / 0.25))
            // The larger audience keeps its label when two would overlap; countries come sorted.
            let hasRoom = facing > 0.0 && !taken.contains(where: { $0.insetBy(dx: -2.0, dy: -2.0).intersects(frame) })
            if hasRoom {
                taken.append(frame)
            }
            let target: CGFloat = hasRoom ? 1.0 : 0.0
            labelView.visibility += (target - labelView.visibility) * 0.25
            if abs(labelView.visibility - target) < 0.01 {
                labelView.visibility = target
            }
            labelView.center = CGPoint(x: frame.midX, y: frame.midY)
            labelView.alpha = facing * labelView.visibility
        }
    }

    // MARK: Motion

    override func didMoveToWindow() {
        super.didMoveToWindow()

        self.updateIsRunning()
    }

    /// The globe turns and renders only while it is on screen, its scene is ready and nothing
    /// paused it.
    private func updateIsRunning() {
        let isRunning = self.window != nil && !self.isPaused && self.sceneView.scene != nil
        if isRunning {
            self.sceneView.isPlaying = true
            if self.displayLink == nil {
                self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60), { [weak self] deltaTime in
                    self?.tick(deltaTime: deltaTime)
                })
            }
        } else {
            self.sceneView.isPlaying = false
            self.displayLink?.invalidate()
            self.displayLink = nil
        }
    }

    private func tick(deltaTime: CGFloat) {
        let deltaTime = min(deltaTime, 1.0 / 20.0)
        let now = CACurrentMediaTime()

        if let zoomAnimation = self.zoomAnimation {
            let t = min(1.0, CGFloat((now - zoomAnimation.start) / 0.35))
            let eased = 1.0 - pow(1.0 - t, 3.0)
            self.zoom = zoomAnimation.from + (zoomAnimation.to - zoomAnimation.from) * eased
            if t >= 1.0 {
                self.zoomAnimation = nil
            }
        }

        if let turnAnimation = self.turnAnimation {
            let t = min(1.0, CGFloat((now - turnAnimation.start) / turnAnimation.duration))
            let eased = 1.0 - pow(1.0 - t, 3.0)
            self.orientation = StatsGlobeOrientation(
                latitude: turnAnimation.from.latitude + (turnAnimation.to.latitude - turnAnimation.from.latitude) * eased,
                longitude: turnAnimation.from.longitude + (turnAnimation.to.longitude - turnAnimation.from.longitude) * eased
            )
            if t >= 1.0 {
                self.turnAnimation = nil
            }
            self.noteInteraction()
        } else if !self.isTracking {
            // Coasting after a flick.
            if abs(self.velocity.x) > 0.001 || abs(self.velocity.y) > 0.001 {
                self.orientation.longitude += self.velocity.x * deltaTime
                self.orientation.latitude = max(-maxLatitude, min(maxLatitude, self.orientation.latitude + self.velocity.y * deltaTime))
                let decay = exp(-3.5 * deltaTime)
                self.velocity = CGPoint(x: self.velocity.x * decay, y: self.velocity.y * decay)
            } else {
                self.velocity = CGPoint()
            }
            // Then the slow turn, eased back in.
            if now - self.lastInteraction > idleSpinDelay {
                self.spinFactor = min(1.0, self.spinFactor + deltaTime * 0.5)
                self.orientation.longitude += idleSpinSpeed * self.spinFactor * deltaTime / max(1.0, self.zoom)
            }
        }
        if self.orientation.longitude > CGFloat.pi {
            self.orientation.longitude -= 2.0 * CGFloat.pi
        } else if self.orientation.longitude < -CGFloat.pi {
            self.orientation.longitude += 2.0 * CGFloat.pi
        }

        self.updateGeometry()
    }

    /// Turns the globe the last part of a turn into place, so it arrives spinning and settles.
    func spinIn() {
        let target = self.orientation
        let from = StatsGlobeOrientation(latitude: target.latitude, longitude: target.longitude - 1.1)
        self.velocity = CGPoint()
        self.orientation = from
        self.turnAnimation = (from, target, CACurrentMediaTime(), 0.9)
        self.setNeedsLayout()
    }

    private func noteInteraction() {
        self.lastInteraction = CACurrentMediaTime()
        self.spinFactor = 0.0
    }

    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        // A drag across the globe's width turns it about half a turn, whatever the zoom.
        let scale = max(1.0, self.radius * self.zoom)
        switch recognizer.state {
        case .began:
            self.isTracking = true
            self.turnAnimation = nil
            self.velocity = CGPoint()
            self.noteInteraction()
        case .changed:
            let translation = recognizer.translation(in: self)
            recognizer.setTranslation(CGPoint(), in: self)
            self.orientation.longitude -= translation.x / scale
            self.orientation.latitude = max(-maxLatitude, min(maxLatitude, self.orientation.latitude + translation.y / scale))
            self.noteInteraction()
        case .ended, .cancelled:
            self.isTracking = false
            let velocity = recognizer.velocity(in: self)
            self.velocity = CGPoint(x: max(-6.0, min(6.0, -velocity.x / scale)), y: max(-6.0, min(6.0, velocity.y / scale)))
            self.noteInteraction()
        default:
            break
        }
    }

    @objc private func pinchGesture(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            self.zoomAnimation = nil
            self.zoomAtPinchStart = self.zoom
            self.noteInteraction()
        case .changed:
            self.zoom = max(0.85, min(3.0, self.zoomAtPinchStart * recognizer.scale))
            self.noteInteraction()
        case .ended, .cancelled:
            // Settles back into the range it can rest in.
            let settled = max(1.0, min(2.5, self.zoom))
            if settled != self.zoom {
                self.zoomAnimation = (self.zoom, settled, CACurrentMediaTime())
            }
            self.noteInteraction()
        default:
            break
        }
    }

    @objc private func doubleTapGesture(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            self.zoomAnimation = (self.zoom, self.zoom > 1.4 ? 1.0 : 2.0, CACurrentMediaTime())
            self.noteInteraction()
        }
    }

    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            self.tapped?()
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else {
            return true
        }
        if pan.view !== self {
            // UIKit also asks the touched view about its ancestors' drags, as UISlider uses it. In
            // the sheet a drag that starts on the globe turns it rather than dragging the sheet down;
            // in the card the list's scroll stays as it is.
            return !self.isExpanded
        }
        if !self.isExpanded {
            // In the card only sideways drags turn the globe; the rest scroll the list.
            let velocity = pan.velocity(in: self)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return self.isExpanded && otherGestureRecognizer is UIPinchGestureRecognizer
    }
}
