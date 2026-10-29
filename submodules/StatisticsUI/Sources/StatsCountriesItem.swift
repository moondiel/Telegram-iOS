import Foundation
import UIKit
import UIKitRuntimeUtils
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import GraphCore
import GraphUI
import ComponentFlow
import EdgeEffect

// Subscriber Globe: the "Followers by country" card. See docs/subscriber-globe/README.md.
//
// One card holding two pages side by side, Telegram's pie chart and the globe, switched by the
// Chart / Globe tabs above it. The pages slide like the panes of a profile (`PeerInfoPaneContainerNode`:
// a 0.4 s spring, the page leaving to the side its tab is on), while the tabs' underline moves with
// its own spring. The card keeps the chart's height on both pages, so the list never jumps.

final class StatsCountriesItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let systemStyle: ItemListSystemStyle
    let countries: ChannelStatsCountries
    let graph: StatsGraph
    let showsGlobe: Bool
    let sectionId: ItemListSectionId

    init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle, countries: ChannelStatsCountries, graph: StatsGraph, showsGlobe: Bool, sectionId: ItemListSectionId) {
        self.presentationData = presentationData
        self.systemStyle = systemStyle
        self.countries = countries
        self.graph = graph
        self.showsGlobe = showsGlobe
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = StatsCountriesItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply(false) })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? StatsCountriesItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply(animation.isAnimated)
                        })
                    }
                }
            }
        }
    }

    var selectable: Bool = false
}

final class StatsCountriesItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode

    /// The card's area; the pages slide inside it and are cut off at its edges.
    private let pagesNode: ASDisplayNode
    private let chartContainerNode: ASDisplayNode
    private let chartNode: ChartNode
    private let globePageView: UIView
    /// Telegram's edge effect (the fade and blur under glass bars, as on the location screen's
    /// map), on all four sides of the globe page: where the globe reaches the card's edge, it
    /// dissolves into the card instead of being cut off.
    private let globeEdgeViews: [EdgeEffectView]
    private var globeView: StatsGlobeView?

    private var item: StatsCountriesItem?
    private var visibilityHeight: CGFloat?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false

        self.pagesNode = ASDisplayNode()
        self.pagesNode.clipsToBounds = true

        self.chartContainerNode = ASDisplayNode()
        self.chartContainerNode.clipsToBounds = true
        self.chartNode = ChartNode()

        self.globePageView = UIView()
        self.globeEdgeViews = (0 ..< 4).map { _ in
            let view = EdgeEffectView()
            view.isUserInteractionEnabled = false
            return view
        }

        super.init(layerBacked: false)

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.pagesNode)
        self.addSubnode(self.topStripeNode)
        self.addSubnode(self.bottomStripeNode)
        self.addSubnode(self.maskNode)

        self.pagesNode.addSubnode(self.chartContainerNode)
        self.chartContainerNode.addSubnode(self.chartNode)
    }

    override func didLoad() {
        super.didLoad()

        self.pagesNode.view.addSubview(self.globePageView)
        for view in self.globeEdgeViews {
            self.globePageView.addSubview(view)
        }

        // As the chart card does: the back swipe keeps the left edge, and on the chart also the
        // range slider's strip.
        self.view.interactiveTransitionGestureRecognizerTest = { [weak self] point in
            if let item = self?.item, item.showsGlobe {
                return point.x > 44.0
            }
            return point.x > 30.0 || (point.y > 310.0 && point.y < 355.0)
        }
    }

    /// As the chart card does: scrolling the list closes the chart's details.
    func resetInteraction() {
        self.chartNode.resetInteraction()
    }

    func asyncLayout() -> (_ item: StatsCountriesItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, (Bool) -> Void) {
        let currentItem = self.item
        let currentVisibilityHeight = self.visibilityHeight

        return { [weak self] item, params, neighbors in
            let leftInset = params.leftInset
            let rightInset = params.rightInset
            let separatorHeight = UIScreenPixel

            let updatedTheme = currentItem?.presentationData.theme !== item.presentationData.theme
            var updatedController: BaseChartController?
            if currentItem?.graph != item.graph, case let .Loaded(_, data) = item.graph {
                // Set up exactly as the Languages card (`StatsGraphItem`, `.pie`, no details loader:
                // a request for a day's details is left unanswered, as there).
                updatedController = createChartController(data, type: .pie, getDetailsData: { _, _ in
                })
            }

            // The pie chart's height, as `StatsGraphItem` computes it, legend included.
            var visibilityHeight = currentVisibilityHeight
            if let updatedController {
                var items: [ChartVisibilityItem] = []
                for value in updatedController.actualChartsCollection.chartValues {
                    items.append(ChartVisibilityItem(title: value.name, color: .black))
                }
                visibilityHeight = items.count > 1 ? calculateVisiblityHeight(width: params.width - leftInset - rightInset, items: items) : 0.0
            }
            let contentSize = CGSize(width: params.width, height: 361.0 + (visibilityHeight ?? 0.0) + 15.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] animated in
                guard let self else {
                    return
                }
                let previousItem = self.item
                self.item = item
                self.visibilityHeight = visibilityHeight

                let theme = item.presentationData.theme
                if updatedTheme {
                    self.topStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    self.bottomStripeNode.backgroundColor = theme.list.itemBlocksSeparatorColor
                    self.backgroundNode.backgroundColor = theme.list.itemBlocksBackgroundColor
                    self.chartNode.setup(
                        theme: ChartTheme(presentationTheme: theme),
                        strings: ChartStrings(
                            zoomOut: item.presentationData.strings.Stats_ZoomOut,
                            total: item.presentationData.strings.Stats_Total,
                            revenueInTon: item.presentationData.strings.Stats_RevenueInTon,
                            revenueInStars: item.presentationData.strings.Stats_RevenueInStars,
                            revenueInUsd: item.presentationData.strings.Stats_RevenueInUsd
                        )
                    )
                }
                if let updatedController {
                    self.chartNode.setup(controller: updatedController)
                }

                let hasCorners = itemListHasRoundedBlockLayout(params)
                var hasTopCorners = false
                var hasBottomCorners = false
                switch neighbors.top {
                case .sameSection(false):
                    self.topStripeNode.isHidden = true
                default:
                    hasTopCorners = true
                    self.topStripeNode.isHidden = hasCorners
                }
                let bottomStripeInset: CGFloat
                switch neighbors.bottom {
                case .sameSection(false):
                    bottomStripeInset = leftInset
                    self.bottomStripeNode.isHidden = false
                default:
                    bottomStripeInset = 0.0
                    hasBottomCorners = true
                    self.bottomStripeNode.isHidden = hasCorners
                }

                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: leftInset, bottom: 0.0, right: rightInset))
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset, height: separatorHeight))

                // The globe page.
                let pageSize = CGSize(width: params.width - leftInset - rightInset, height: contentSize.height)
                let colors = StatsGlobeColors(theme: theme)
                let globeView: StatsGlobeView
                if let current = self.globeView, current.countries == item.countries {
                    globeView = current
                    globeView.updateColors(colors)
                } else {
                    self.globeView?.removeFromSuperview()
                    globeView = StatsGlobeView(countries: item.countries, colors: colors, strings: item.presentationData.strings)
                    self.globeView = globeView
                    self.globePageView.insertSubview(globeView, at: 0)
                }
                let globeFrame = CGRect(origin: CGPoint(), size: pageSize)
                if globeView.frame != globeFrame {
                    globeView.frame = globeFrame
                }
                self.updateGlobeEdges(size: pageSize, color: theme.list.itemBlocksBackgroundColor)
                globeView.radius = floor(min(pageSize.width, pageSize.height) / 2.0 - 34.0)

                // The pages, side by side in tab order: the chart, then the globe.
                self.pagesNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: pageSize)
                let switched = previousItem != nil && previousItem?.showsGlobe != item.showsGlobe
                let transition: ContainedViewLayoutTransition = switched && animated ? .animated(duration: 0.4, curve: .spring) : .immediate

                let chartFrame = CGRect(origin: CGPoint(x: item.showsGlobe ? -pageSize.width : 0.0, y: 8.0), size: CGSize(width: pageSize.width, height: pageSize.height - 8.0))
                let globePageFrame = CGRect(origin: CGPoint(x: item.showsGlobe ? 0.0 : pageSize.width, y: 0.0), size: pageSize)
                self.chartNode.frame = CGRect(origin: CGPoint(), size: CGSize(width: pageSize.width, height: 750.0))

                if item.showsGlobe {
                    globeView.isPaused = false
                    if switched && animated {
                        // The globe arrives turning, as if it had been spinning just out of view.
                        globeView.spinIn()
                    }
                }
                self.chartContainerNode.isUserInteractionEnabled = !item.showsGlobe
                self.globePageView.isUserInteractionEnabled = item.showsGlobe

                transition.updateFrame(node: self.chartContainerNode, frame: chartFrame)
                transition.updateFrame(view: self.globePageView, frame: globePageFrame, completion: { [weak self] _ in
                    // Off the page, the globe stops.
                    if let self, let item = self.item, !item.showsGlobe {
                        self.globeView?.isPaused = true
                    }
                })
                if !item.showsGlobe && !transition.isAnimated {
                    globeView.isPaused = true
                }
            })
        }
    }

    /// Top and bottom are Telegram's top and bottom edge effects; the sides are the top one turned
    /// a quarter, since the effect only knows top and bottom.
    private func updateGlobeEdges(size: CGSize, color: UIColor) {
        let edgeSize: CGFloat = 26.0
        let edges: [(edge: EdgeEffectView.Edge, length: CGFloat, center: CGPoint, angle: CGFloat)] = [
            (.top, size.width, CGPoint(x: size.width / 2.0, y: edgeSize / 2.0), 0.0),
            (.bottom, size.width, CGPoint(x: size.width / 2.0, y: size.height - edgeSize / 2.0), 0.0),
            (.top, size.height, CGPoint(x: edgeSize / 2.0, y: size.height / 2.0), -CGFloat.pi / 2.0),
            (.top, size.height, CGPoint(x: size.width - edgeSize / 2.0, y: size.height / 2.0), CGFloat.pi / 2.0)
        ]
        for (index, edge) in edges.enumerated() where index < self.globeEdgeViews.count {
            let view = self.globeEdgeViews[index]
            let rect = CGRect(origin: CGPoint(), size: CGSize(width: edge.length, height: edgeSize))
            view.transform = CGAffineTransform(rotationAngle: edge.angle)
            view.bounds = rect
            view.center = edge.center
            view.update(content: color, blur: true, alpha: 0.75, rect: rect, edge: edge.edge, edgeSize: edgeSize, transition: .immediate)
        }
    }

    override func animateInsertion(_ currentTimestamp: Double, duration: Double, options: ListViewItemAnimationOptions) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)
    }

    override func animateAdded(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
    }

    override func animateRemoved(_ currentTimestamp: Double, duration: Double) {
        self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.15, removeOnCompletion: false)
    }
}
