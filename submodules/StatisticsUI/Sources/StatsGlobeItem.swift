import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

// Subscriber Globe: the globe card in channel statistics. See docs/subscriber-globe/README.md.
//
// The "Followers by country" card shows either Telegram's pie chart or this globe, switched from
// the section header. The globe turns under a sideways drag and opens in a sheet on a tap.

/// The globe card of the "Followers by country" section.
final class StatsGlobeItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let systemStyle: ItemListSystemStyle
    let countries: ChannelStatsCountries
    let sectionId: ItemListSectionId
    let open: (StatsGlobeView) -> Void

    init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle, countries: ChannelStatsCountries, sectionId: ItemListSectionId, open: @escaping (StatsGlobeView) -> Void) {
        self.presentationData = presentationData
        self.systemStyle = systemStyle
        self.countries = countries
        self.sectionId = sectionId
        self.open = open
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, neighbors: ListViewItemNeighbors, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = StatsGlobeItemNode()
            let (layout, apply) = node.asyncLayout()(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, neighbors: ListViewItemNeighbors, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? StatsGlobeItemNode {
                let makeLayout = nodeValue.asyncLayout()
                async {
                    let (layout, apply) = makeLayout(self, params, itemListNeighbors(item: self, topFacet: neighbors.previous?.base(ItemListNeighborFacet.self), bottomFacet: neighbors.next?.base(ItemListNeighborFacet.self)))
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }

    var selectable: Bool = false
}

final class StatsGlobeItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let expandIconNode: ASImageNode
    private var globeView: StatsGlobeView?

    private var item: StatsGlobeItem?

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false

        self.expandIconNode = ASImageNode()
        self.expandIconNode.isUserInteractionEnabled = false
        self.expandIconNode.displaysAsynchronously = false

        super.init(layerBacked: false)

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.topStripeNode)
        self.addSubnode(self.bottomStripeNode)
        self.addSubnode(self.expandIconNode)
        self.addSubnode(self.maskNode)
    }

    func asyncLayout() -> (_ item: StatsGlobeItem, _ params: ListViewItemLayoutParams, _ neighbors: ItemListNeighbors) -> (ListViewItemNodeLayout, () -> Void) {
        let currentItem = self.item

        return { [weak self] item, params, neighbors in
            let leftInset = params.leftInset
            let rightInset = params.rightInset
            let separatorHeight = UIScreenPixel

            let updatedTheme = currentItem?.presentationData.theme !== item.presentationData.theme
            let itemBackgroundColor = item.presentationData.theme.list.itemBlocksBackgroundColor
            let itemSeparatorColor = item.presentationData.theme.list.itemBlocksSeparatorColor

            let contentSize = CGSize(width: params.width, height: 361.0)
            let insets = itemListNeighborsGroupedInsets(neighbors, params)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: insets)

            return (layout, { [weak self] in
                guard let self else {
                    return
                }
                self.item = item

                if updatedTheme {
                    self.topStripeNode.backgroundColor = itemSeparatorColor
                    self.bottomStripeNode.backgroundColor = itemSeparatorColor
                    self.backgroundNode.backgroundColor = itemBackgroundColor
                    self.expandIconNode.image = generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Expand"), color: item.presentationData.theme.list.itemSecondaryTextColor)
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

                self.maskNode.image = hasCorners ? PresentationResourcesItemList.cornersImage(item.presentationData.theme, top: hasTopCorners, bottom: hasBottomCorners, glass: item.systemStyle == .glass) : nil
                self.backgroundNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: contentSize.height + min(insets.top, separatorHeight) + min(insets.bottom, separatorHeight)))
                self.maskNode.frame = self.backgroundNode.frame.inset(by: UIEdgeInsets(top: 0.0, left: leftInset, bottom: 0.0, right: rightInset))
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset, height: separatorHeight))

                let globeView: StatsGlobeView
                let colors = StatsGlobeColors(theme: item.presentationData.theme)
                if let current = self.globeView, current.countries == item.countries {
                    globeView = current
                    globeView.updateColors(colors)
                } else {
                    self.globeView?.removeFromSuperview()
                    globeView = StatsGlobeView(countries: item.countries, colors: colors, strings: item.presentationData.strings, isExpanded: false)
                    self.globeView = globeView
                    // Over the background and stripes, which are layers, under the icon and corners.
                    self.view.insertSubview(globeView, belowSubview: self.expandIconNode.view)
                }
                globeView.tapped = { [weak self, weak globeView] in
                    guard let self, let globeView, let item = self.item else {
                        return
                    }
                    item.open(globeView)
                }
                let globeFrame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: params.width - leftInset - rightInset, height: contentSize.height))
                if globeView.frame != globeFrame {
                    globeView.frame = globeFrame
                }
                globeView.radius = floor(min(globeFrame.width, globeFrame.height) / 2.0 - 34.0)

                if let image = self.expandIconNode.image {
                    self.expandIconNode.frame = CGRect(origin: CGPoint(x: params.width - rightInset - 12.0 - image.size.width, y: 12.0), size: image.size)
                }
            })
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
