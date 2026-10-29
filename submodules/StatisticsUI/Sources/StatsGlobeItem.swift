import Foundation
import UIKit
import MapKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import TelegramStringFormatting
import ItemListUI

// Subscriber Globe: the card with the globe in channel statistics. See docs/subscriber-globe/README.md.
//
// The globe is MapKit's satellite map zoomed out, the map Telegram's location screens show in their
// Satellite mode (`LocationMapNode`, `.satelliteFlyover`): a real globe that turns under the finger,
// with no texture or renderer of our own. A country is a MapKit marker in the theme's accent
// colour, carrying the number of followers; markers that overlap merge into one with their sum.

/// The globe card of the "Followers by country" section.
final class StatsGlobeItem: ListViewItem, ItemListItem {
    let presentationData: ItemListPresentationData
    let systemStyle: ItemListSystemStyle
    let countries: ChannelStatsCountries
    let sectionId: ItemListSectionId

    init(presentationData: ItemListPresentationData, systemStyle: ItemListSystemStyle, countries: ChannelStatsCountries, sectionId: ItemListSectionId) {
        self.presentationData = presentationData
        self.systemStyle = systemStyle
        self.countries = countries
        self.sectionId = sectionId
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

/// A country on the globe.
private final class CountryAnnotation: NSObject, MKAnnotation {
    let code: String
    let followers: Int
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(country: ChannelStatsCountry, title: String) {
        self.code = country.code
        self.followers = country.followers
        self.coordinate = CLLocationCoordinate2D(latitude: country.latitude, longitude: country.longitude)
        self.title = title
    }
}

private let countryReuseIdentifier = "country"
private let clusterReuseIdentifier = "countryCluster"
private let countryClusteringIdentifier = "countries"

/// MapKit calls back into an `NSObject`; the node stays a plain node, as `LocationMapNode` does.
private final class GlobeMapDelegate: NSObject, MKMapViewDelegate {
    var accentColor: UIColor = .systemBlue

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let cluster = annotation as? MKClusterAnnotation {
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: clusterReuseIdentifier) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: clusterReuseIdentifier)
            view.annotation = cluster
            let followers = cluster.memberAnnotations.reduce(0, { $0 + (($1 as? CountryAnnotation)?.followers ?? 0) })
            view.glyphText = compactNumericCountString(followers)
            view.markerTintColor = self.accentColor
            view.titleVisibility = .hidden
            view.subtitleVisibility = .hidden
            view.canShowCallout = false
            return view
        }
        guard let country = annotation as? CountryAnnotation else {
            return nil
        }
        let view = (mapView.dequeueReusableAnnotationView(withIdentifier: countryReuseIdentifier) as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(annotation: country, reuseIdentifier: countryReuseIdentifier)
        view.annotation = country
        view.glyphText = compactNumericCountString(country.followers)
        view.markerTintColor = self.accentColor
        view.titleVisibility = .adaptive
        view.subtitleVisibility = .hidden
        view.canShowCallout = false
        view.clusteringIdentifier = countryClusteringIdentifier
        // The biggest audiences stay visible when markers crowd.
        view.displayPriority = MKFeatureDisplayPriority(rawValue: min(1000.0, 500.0 + Float(country.followers)))
        return view
    }

    func mapView(_ mapView: MKMapView, clusterAnnotationForMemberAnnotations memberAnnotations: [MKAnnotation]) -> MKClusterAnnotation {
        let cluster = MKClusterAnnotation(memberAnnotations: memberAnnotations)
        cluster.title = nil
        cluster.subtitle = nil
        return cluster
    }
}

final class StatsGlobeItemNode: ListViewItemNode {
    private let backgroundNode: ASDisplayNode
    private let topStripeNode: ASDisplayNode
    private let bottomStripeNode: ASDisplayNode
    private let maskNode: ASImageNode
    private let mapNode: ASDisplayNode
    private let mapDelegate = GlobeMapDelegate()

    private var item: StatsGlobeItem?
    private var shownCountries: ChannelStatsCountries?
    private var isMapConfigured = false

    init() {
        self.backgroundNode = ASDisplayNode()
        self.backgroundNode.isLayerBacked = true

        self.topStripeNode = ASDisplayNode()
        self.topStripeNode.isLayerBacked = true

        self.bottomStripeNode = ASDisplayNode()
        self.bottomStripeNode.isLayerBacked = true

        self.maskNode = ASImageNode()
        self.maskNode.isUserInteractionEnabled = false

        self.mapNode = ASDisplayNode()
        self.mapNode.setViewBlock({
            return MKMapView()
        })

        super.init(layerBacked: false)

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.mapNode)
        self.addSubnode(self.topStripeNode)
        self.addSubnode(self.bottomStripeNode)
        self.addSubnode(self.maskNode)
    }

    /// The map, set up on first use: the first layout can be applied before the node has loaded.
    private func configuredMapView() -> MKMapView? {
        guard let mapView = self.mapNode.view as? MKMapView else {
            return nil
        }
        if self.isMapConfigured {
            return mapView
        }
        self.isMapConfigured = true
        // As on the location screens: the map takes horizontal drags except at the left edge,
        // where the back swipe stays.
        mapView.interactiveTransitionGestureRecognizerTest = { point in
            return point.x > 44.0
        }
        mapView.delegate = self.mapDelegate
        mapView.mapType = .satelliteFlyover
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.isPitchEnabled = false
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: countryReuseIdentifier)
        mapView.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: clusterReuseIdentifier)
        // From the whole globe down to a region; never to street level.
        mapView.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 1_500_000.0, maxCenterCoordinateDistance: 40_000_000.0), animated: false)
        return mapView
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

            let contentSize = CGSize(width: params.width, height: 340.0)
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
                    self.mapDelegate.accentColor = item.presentationData.theme.list.itemAccentColor
                    self.configuredMapView()?.overrideUserInterfaceStyle = item.presentationData.theme.overallDarkAppearance ? .dark : .light
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
                self.mapNode.frame = CGRect(origin: CGPoint(x: leftInset, y: 0.0), size: CGSize(width: params.width - leftInset - rightInset, height: contentSize.height))
                self.topStripeNode.frame = CGRect(origin: CGPoint(x: 0.0, y: -min(insets.top, separatorHeight)), size: CGSize(width: params.width, height: separatorHeight))
                self.bottomStripeNode.frame = CGRect(origin: CGPoint(x: bottomStripeInset, y: contentSize.height - separatorHeight), size: CGSize(width: params.width - bottomStripeInset, height: separatorHeight))

                // Markers take the accent colour when they are created: a new theme recreates them.
                if self.shownCountries != item.countries || updatedTheme {
                    self.shownCountries = item.countries
                    self.updateAnnotations(countries: item.countries, strings: item.presentationData.strings)
                }
            })
        }
    }

    private func updateAnnotations(countries: ChannelStatsCountries, strings: PresentationStrings) {
        guard let mapView = self.configuredMapView() else {
            return
        }
        mapView.removeAnnotations(mapView.annotations)

        let locale = localeWithStrings(strings)
        let annotations = countries.countries.map { country -> CountryAnnotation in
            let name = locale.localizedString(forRegionCode: country.code) ?? country.code
            return CountryAnnotation(country: country, title: "\(flagEmoji(countryCode: country.code)) \(name)")
        }
        mapView.addAnnotations(annotations)

        // The globe opens over the largest audience, whole and upright.
        if let top = countries.countries.first {
            let center = CLLocationCoordinate2D(latitude: max(-50.0, min(50.0, top.latitude)), longitude: top.longitude)
            mapView.setCamera(MKMapCamera(lookingAtCenter: center, fromDistance: 25_000_000.0, pitch: 0.0, heading: 0.0), animated: false)
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
