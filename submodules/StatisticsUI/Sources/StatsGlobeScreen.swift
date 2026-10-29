import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData

// Subscriber Globe: the globe opened from the card, filling the screen. See
// docs/subscriber-globe/README.md.
//
// Opening it dives into the card's globe: the card's globe hides, and the fullscreen globe starts
// at its place, size and turn, then grows to fill the screen. Closing it shrinks it back onto the
// card, which carries on from wherever it was turned to.

final class StatsGlobeScreen: ViewController {
    private let presentationData: PresentationData
    private let countries: ChannelStatsCountries
    private weak var sourceView: StatsGlobeView?
    private var animatedIn = false

    private var controllerNode: StatsGlobeScreenNode {
        return self.displayNode as! StatsGlobeScreenNode
    }

    init(presentationData: PresentationData, sourceView: StatsGlobeView) {
        self.presentationData = presentationData
        self.countries = sourceView.countries
        self.sourceView = sourceView

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadDisplayNode() {
        self.displayNode = StatsGlobeScreenNode(presentationData: self.presentationData, countries: self.countries, sourceView: self.sourceView)
        self.controllerNode.close = { [weak self] in
            self?.dismiss()
        }
        self.displayNodeDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !self.animatedIn {
            self.animatedIn = true
            self.controllerNode.animateIn()
        }
    }

    override func dismiss(completion: (() -> Void)? = nil) {
        self.controllerNode.animateOut(completion: { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
            completion?()
        })
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, transition: transition)
    }
}

private final class StatsGlobeScreenNode: ASDisplayNode {
    private let presentationData: PresentationData
    private weak var sourceView: StatsGlobeView?

    private let backgroundNode: ASDisplayNode
    private let globeView: StatsGlobeView
    private let titleNode: ImmediateTextNode
    private let closeButton: HighlightableButtonNode

    var close: (() -> Void)?

    private var validLayout: ContainerViewLayout?
    /// The globe's size and place once open; the dive runs between these and the card's.
    private var restingRadius: CGFloat = 100.0
    private var restingOffset = CGPoint()
    private var diveAnimator: DisplayLinkAnimator?
    private var isDiving = false
    private var isClosing = false

    init(presentationData: PresentationData, countries: ChannelStatsCountries, sourceView: StatsGlobeView?) {
        self.presentationData = presentationData
        self.sourceView = sourceView

        let colors = StatsGlobeColors(theme: presentationData.theme)

        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.backgroundColor = colors.background

        self.globeView = StatsGlobeView(countries: countries, colors: colors, strings: presentationData.strings, isFullscreen: true, orientation: sourceView?.orientation)

        self.titleNode = ImmediateTextNode()
        self.titleNode.attributedText = NSAttributedString(string: presentationData.strings.ChannelStats_Countries_ScreenTitle, font: Font.semibold(17.0), textColor: presentationData.theme.list.itemPrimaryTextColor)
        self.titleNode.maximumNumberOfLines = 1

        self.closeButton = HighlightableButtonNode()
        self.closeButton.setTitle(presentationData.strings.Common_Close, with: Font.regular(17.0), with: presentationData.theme.list.itemAccentColor, for: .normal)
        self.closeButton.hitTestSlop = UIEdgeInsets(top: -8.0, left: -8.0, bottom: -8.0, right: -8.0)

        super.init()

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.titleNode)
        self.addSubnode(self.closeButton)

        self.closeButton.addTarget(self, action: #selector(self.closePressed), forControlEvents: .touchUpInside)

        // Nothing shows until the dive starts, which places the globe over the card first.
        for node in [self.backgroundNode, self.titleNode, self.closeButton] as [ASDisplayNode] {
            node.alpha = 0.0
        }
        self.globeView.alpha = 0.0
    }

    override func didLoad() {
        super.didLoad()

        self.view.insertSubview(self.globeView, aboveSubview: self.backgroundNode.view)
    }

    @objc private func closePressed() {
        self.close?()
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        self.validLayout = layout
        let size = layout.size

        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: size))

        let topInset = max(layout.statusBarHeight ?? 0.0, layout.safeInsets.top)
        let barHeight: CGFloat = 44.0
        let sideInset: CGFloat = 16.0 + max(layout.safeInsets.left, layout.safeInsets.right)

        let closeSize = self.closeButton.measure(CGSize(width: 200.0, height: barHeight))
        transition.updateFrame(node: self.closeButton, frame: CGRect(origin: CGPoint(x: sideInset, y: topInset + floor((barHeight - closeSize.height) / 2.0)), size: closeSize))

        let titleSize = self.titleNode.updateLayout(CGSize(width: size.width - (sideInset + closeSize.width + 12.0) * 2.0, height: barHeight))
        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floor((size.width - titleSize.width) / 2.0), y: topInset + floor((barHeight - titleSize.height) / 2.0)), size: titleSize))

        let bottomInset = max(layout.intrinsicInsets.bottom, layout.safeInsets.bottom) + 16.0

        // The globe takes the space between the bar and the note, with room for its halo.
        let top = topInset + barHeight
        let bottom = size.height - bottomInset
        let available = CGRect(x: 0.0, y: top, width: size.width, height: max(0.0, bottom - top))
        self.restingRadius = floor(max(60.0, min(available.width - 48.0, available.height - 48.0) / 2.0))
        self.restingOffset = CGPoint(x: available.midX - size.width / 2.0, y: available.midY - size.height / 2.0)

        self.globeView.frame = CGRect(origin: CGPoint(), size: size)
        if !self.isDiving && !self.isClosing {
            self.globeView.radius = self.restingRadius
            self.globeView.centerOffset = self.restingOffset
        }
    }

    /// Where the card's globe is, in this node's coordinates.
    private func sourceCircle() -> (center: CGPoint, radius: CGFloat)? {
        guard let sourceView = self.sourceView, sourceView.window != nil, self.isNodeLoaded else {
            return nil
        }
        let frame = self.view.convert(sourceView.globeFrame, from: sourceView)
        let visible = self.view.bounds.intersects(frame)
        if !visible {
            return nil
        }
        return (CGPoint(x: frame.midX, y: frame.midY), frame.width / 2.0)
    }

    private func runDive(from: (center: CGPoint, radius: CGFloat), to: (center: CGPoint, radius: CGFloat), duration: Double, overshoot: Bool, completion: @escaping () -> Void) {
        let size = self.view.bounds.size
        self.diveAnimator?.invalidate()
        self.diveAnimator = DisplayLinkAnimator(duration: duration, from: 0.0, to: 1.0, update: { [weak self] t in
            guard let self else {
                return
            }
            // Ease out; opening overshoots a little, the "dive" past the screen's edge and back.
            let eased: CGFloat
            if overshoot {
                let s: CGFloat = 1.2
                let u = t - 1.0
                eased = 1.0 + u * u * ((s + 1.0) * u + s)
            } else {
                eased = 1.0 - pow(1.0 - t, 3.0)
            }
            let radius = from.radius + (to.radius - from.radius) * eased
            let center = CGPoint(x: from.center.x + (to.center.x - from.center.x) * eased, y: from.center.y + (to.center.y - from.center.y) * eased)
            self.globeView.radius = max(1.0, radius)
            self.globeView.centerOffset = CGPoint(x: center.x - size.width / 2.0, y: center.y - size.height / 2.0)
        }, completion: { [weak self] in
            self?.diveAnimator = nil
            completion()
        })
    }

    func animateIn() {
        let size = self.view.bounds.size
        let target = (center: CGPoint(x: size.width / 2.0 + self.restingOffset.x, y: size.height / 2.0 + self.restingOffset.y), radius: self.restingRadius)

        self.backgroundNode.alpha = 1.0
        self.backgroundNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
        for node in [self.titleNode, self.closeButton] as [ASDisplayNode] {
            node.alpha = 1.0
            node.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3, delay: 0.1)
        }
        self.globeView.alpha = 1.0

        guard let source = self.sourceCircle() else {
            self.globeView.layer.animateScale(from: 0.6, to: 1.0, duration: 0.4)
            self.globeView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
            return
        }
        // The card's globe becomes this one.
        self.sourceView?.alpha = 0.0
        self.isDiving = true
        self.globeView.radius = source.radius
        self.globeView.centerOffset = CGPoint(x: source.center.x - size.width / 2.0, y: source.center.y - size.height / 2.0)
        self.runDive(from: source, to: target, duration: 0.5, overshoot: true, completion: { [weak self] in
            self?.isDiving = false
        })
    }

    func animateOut(completion: @escaping () -> Void) {
        if self.isClosing {
            return
        }
        self.isClosing = true
        self.view.isUserInteractionEnabled = false

        // Zoom folds into the radius, so the globe shrinks from the size it is shown at.
        let size = self.view.bounds.size
        let shownRadius = self.globeView.radius * self.globeView.zoom
        self.globeView.setZoom(1.0, animated: false)
        self.globeView.radius = shownRadius
        let current = (center: CGPoint(x: size.width / 2.0 + self.globeView.centerOffset.x, y: size.height / 2.0 + self.globeView.centerOffset.y), radius: shownRadius)

        self.backgroundNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
        for node in [self.titleNode, self.closeButton] as [ASDisplayNode] {
            node.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
        }

        guard let source = self.sourceCircle() else {
            self.sourceView?.alpha = 1.0
            self.globeView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { _ in
                completion()
            })
            return
        }
        self.runDive(from: current, to: source, duration: 0.35, overshoot: false, completion: { [weak self] in
            guard let self else {
                completion()
                return
            }
            // The card picks up where this globe was turned to.
            if let sourceView = self.sourceView {
                sourceView.orientation = self.globeView.orientation
                sourceView.alpha = 1.0
            }
            completion()
        })
    }
}
