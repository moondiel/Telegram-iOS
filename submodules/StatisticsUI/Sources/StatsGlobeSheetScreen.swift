import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import TelegramStringFormatting
import ViewControllerComponent
import SheetComponent
import MultilineTextComponent
import BundleIconComponent
import GlassBarButtonComponent

// Subscriber Globe: the globe opened from the card, in a sheet. See docs/subscriber-globe/README.md.
//
// The sheet is Telegram's glass sheet with a glass close button, as statistics' transaction info
// uses it (`TransactionInfoScreen`). It holds a large globe, opened at the card's turn, and the list
// of countries; tapping a country turns the globe to it.

/// A country of the list under the globe: a dot in its colour, as in the chart's legend, its name,
/// share and followers.
private final class StatsGlobeCountryRowView: UIView {
    private let highlightView: UIView
    private let dotView: UIView
    private let nameLabel: UILabel
    private let valueLabel: UILabel
    private let separatorView: UIView

    var tapped: (() -> Void)?

    override init(frame: CGRect) {
        self.highlightView = UIView()
        self.highlightView.alpha = 0.0
        self.dotView = UIView()
        self.dotView.layer.cornerRadius = 5.0
        self.nameLabel = UILabel()
        self.valueLabel = UILabel()
        self.valueLabel.textAlignment = .right
        self.separatorView = UIView()

        super.init(frame: frame)

        self.addSubview(self.highlightView)
        self.addSubview(self.dotView)
        self.addSubview(self.nameLabel)
        self.addSubview(self.valueLabel)
        self.addSubview(self.separatorView)

        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapGesture(_:))))
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    @objc private func tapGesture(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == .ended {
            self.highlightView.alpha = 1.0
            UIView.animate(withDuration: 0.3, delay: 0.1, options: [], animations: {
                self.highlightView.alpha = 0.0
            })
            self.tapped?()
        }
    }

    func update(country: ChannelStatsCountry, color: UIColor, total: Int, theme: PresentationTheme, locale: Locale, hasSeparator: Bool, size: CGSize) {
        let name = locale.localizedString(forRegionCode: country.code) ?? country.code
        self.nameLabel.attributedText = NSAttributedString(string: name, font: Font.regular(17.0), textColor: theme.list.itemPrimaryTextColor)
        self.dotView.backgroundColor = color

        let share = Int((Double(country.followers) * 100.0 / Double(max(1, total))).rounded())
        let value = NSMutableAttributedString()
        value.append(NSAttributedString(string: "\(share)%  ", font: Font.regular(15.0), textColor: theme.list.itemSecondaryTextColor))
        value.append(NSAttributedString(string: compactNumericCountString(country.followers), font: Font.semibold(17.0), textColor: theme.list.itemPrimaryTextColor))
        self.valueLabel.attributedText = value

        self.highlightView.backgroundColor = theme.list.itemHighlightedBackgroundColor
        self.separatorView.backgroundColor = theme.list.itemBlocksSeparatorColor
        self.separatorView.isHidden = !hasSeparator

        let sideInset: CGFloat = 16.0
        let valueSize = self.valueLabel.sizeThatFits(CGSize(width: size.width / 2.0, height: size.height))
        self.highlightView.frame = CGRect(origin: CGPoint(), size: size)
        self.valueLabel.frame = CGRect(x: size.width - sideInset - valueSize.width, y: floor((size.height - valueSize.height) / 2.0), width: valueSize.width, height: valueSize.height)
        self.dotView.frame = CGRect(x: sideInset, y: floor((size.height - 10.0) / 2.0), width: 10.0, height: 10.0)
        let nameX = sideInset + 10.0 + 12.0
        let nameWidth = max(0.0, size.width - nameX - sideInset - valueSize.width - 8.0)
        let nameSize = self.nameLabel.sizeThatFits(CGSize(width: nameWidth, height: size.height))
        self.nameLabel.frame = CGRect(x: nameX, y: floor((size.height - nameSize.height) / 2.0), width: min(nameWidth, nameSize.width), height: nameSize.height)
        self.separatorView.frame = CGRect(x: nameX, y: size.height - UIScreenPixel, width: size.width - nameX, height: UIScreenPixel)
    }
}

/// The globe and the list of countries under it.
private final class StatsGlobeSheetBodyComponent: Component {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let countries: ChannelStatsCountries
    let orientation: StatsGlobeOrientation?
    let sideInset: CGFloat

    init(theme: PresentationTheme, strings: PresentationStrings, countries: ChannelStatsCountries, orientation: StatsGlobeOrientation?, sideInset: CGFloat) {
        self.theme = theme
        self.strings = strings
        self.countries = countries
        self.orientation = orientation
        self.sideInset = sideInset
    }

    static func ==(lhs: StatsGlobeSheetBodyComponent, rhs: StatsGlobeSheetBodyComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.countries != rhs.countries {
            return false
        }
        if lhs.orientation != rhs.orientation {
            return false
        }
        if lhs.sideInset != rhs.sideInset {
            return false
        }
        return true
    }

    final class View: UIView {
        private var globeView: StatsGlobeView?
        private let sectionView: UIView
        private var rowViews: [StatsGlobeCountryRowView] = []

        override init(frame: CGRect) {
            self.sectionView = UIView()
            self.sectionView.clipsToBounds = true
            self.sectionView.layer.cornerRadius = 26.0

            super.init(frame: frame)

            self.addSubview(self.sectionView)
        }

        required init?(coder: NSCoder) {
            preconditionFailure()
        }

        func update(component: StatsGlobeSheetBodyComponent, availableSize: CGSize) -> CGSize {
            let width = availableSize.width
            let colors = StatsGlobeColors(theme: component.theme, background: component.theme.list.modalBlocksBackgroundColor)

            let globeView: StatsGlobeView
            if let current = self.globeView, current.countries == component.countries {
                globeView = current
                globeView.updateColors(colors)
            } else {
                self.globeView?.removeFromSuperview()
                globeView = StatsGlobeView(countries: component.countries, colors: colors, strings: component.strings, isExpanded: true, orientation: component.orientation)
                self.globeView = globeView
                self.insertSubview(globeView, at: 0)
            }
            let globeHeight = min(width, 400.0)
            globeView.frame = CGRect(x: 0.0, y: 0.0, width: width, height: globeHeight)
            globeView.radius = floor(min(width, globeHeight) / 2.0 - 32.0)

            let countries = component.countries.countries
            while self.rowViews.count > countries.count {
                self.rowViews.removeLast().removeFromSuperview()
            }
            while self.rowViews.count < countries.count {
                let rowView = StatsGlobeCountryRowView()
                self.sectionView.addSubview(rowView)
                self.rowViews.append(rowView)
            }

            let rowHeight: CGFloat = 52.0
            let sectionWidth = width - component.sideInset * 2.0
            let locale = localeWithStrings(component.strings)
            for (index, country) in countries.enumerated() {
                let rowView = self.rowViews[index]
                rowView.frame = CGRect(x: 0.0, y: CGFloat(index) * rowHeight, width: sectionWidth, height: rowHeight)
                rowView.update(country: country, color: channelStatsCountryColor(at: index), total: component.countries.total, theme: component.theme, locale: locale, hasSeparator: index != countries.count - 1, size: rowView.bounds.size)
                rowView.tapped = { [weak globeView] in
                    globeView?.focus(on: country)
                }
            }
            self.sectionView.backgroundColor = component.theme.list.itemModalBlocksBackgroundColor
            let sectionFrame = CGRect(x: component.sideInset, y: globeHeight + 8.0, width: sectionWidth, height: CGFloat(countries.count) * rowHeight)
            self.sectionView.frame = sectionFrame
            self.sectionView.isHidden = countries.isEmpty

            return CGSize(width: width, height: countries.isEmpty ? globeHeight : sectionFrame.maxY)
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize)
    }
}

private final class StatsGlobeSheetContent: CombinedComponent {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let countries: ChannelStatsCountries
    let orientation: StatsGlobeOrientation?
    let dismiss: () -> Void

    init(countries: ChannelStatsCountries, orientation: StatsGlobeOrientation?, dismiss: @escaping () -> Void) {
        self.countries = countries
        self.orientation = orientation
        self.dismiss = dismiss
    }

    static func ==(lhs: StatsGlobeSheetContent, rhs: StatsGlobeSheetContent) -> Bool {
        if lhs.countries != rhs.countries {
            return false
        }
        if lhs.orientation != rhs.orientation {
            return false
        }
        return true
    }

    static var body: Body {
        let closeButton = Child(GlassBarButtonComponent.self)
        let title = Child(MultilineTextComponent.self)
        let subtitle = Child(MultilineTextComponent.self)
        let globe = Child(StatsGlobeSheetBodyComponent.self)

        return { context in
            let environment = context.environment[EnvironmentType.self]
            let component = context.component
            let theme = environment.theme

            let closeButton = closeButton.update(
                component: GlassBarButtonComponent(
                    size: CGSize(width: 44.0, height: 44.0),
                    backgroundColor: nil,
                    isDark: theme.overallDarkAppearance,
                    state: .glass,
                    component: AnyComponentWithIdentity(id: "close", component: AnyComponent(
                        BundleIconComponent(
                            name: "Navigation/Close",
                            tintColor: theme.chat.inputPanel.panelControlColor
                        )
                    )),
                    action: { _ in
                        component.dismiss()
                    }
                ),
                availableSize: CGSize(width: 44.0, height: 44.0),
                transition: .immediate
            )
            context.add(closeButton
                .position(CGPoint(x: 16.0 + closeButton.size.width / 2.0, y: 16.0 + closeButton.size.height / 2.0))
            )

            let title = title.update(
                component: MultilineTextComponent(
                    text: .plain(NSAttributedString(string: environment.strings.ChannelStats_Countries_ScreenTitle, font: Font.semibold(17.0), textColor: theme.actionSheet.primaryTextColor)),
                    horizontalAlignment: .center,
                    maximumNumberOfLines: 1
                ),
                availableSize: CGSize(width: context.availableSize.width - 140.0, height: 44.0),
                transition: .immediate
            )
            if component.countries.isEstimate {
                // Under the title, where the numbers come from.
                let subtitle = subtitle.update(
                    component: MultilineTextComponent(
                        text: .plain(NSAttributedString(string: environment.strings.ChannelStats_Countries_EstimateSubtitle, font: Font.regular(13.0), textColor: theme.actionSheet.secondaryTextColor)),
                        horizontalAlignment: .center,
                        maximumNumberOfLines: 1
                    ),
                    availableSize: CGSize(width: context.availableSize.width - 140.0, height: 44.0),
                    transition: .immediate
                )
                let titleY: CGFloat = 16.0 + 22.0 - floor(subtitle.size.height / 2.0) - 1.0
                context.add(title
                    .position(CGPoint(x: context.availableSize.width / 2.0, y: titleY))
                )
                context.add(subtitle
                    .position(CGPoint(x: context.availableSize.width / 2.0, y: titleY + title.size.height / 2.0 + 1.0 + subtitle.size.height / 2.0))
                )
            } else {
                context.add(title
                    .position(CGPoint(x: context.availableSize.width / 2.0, y: 16.0 + 22.0))
                )
            }

            var contentHeight: CGFloat = 68.0

            let globe = globe.update(
                component: StatsGlobeSheetBodyComponent(
                    theme: theme,
                    strings: environment.strings,
                    countries: component.countries,
                    orientation: component.orientation,
                    sideInset: 16.0 + environment.safeInsets.left
                ),
                availableSize: CGSize(width: context.availableSize.width, height: 10000.0),
                transition: context.transition
            )
            context.add(globe
                .position(CGPoint(x: context.availableSize.width / 2.0, y: contentHeight + globe.size.height / 2.0))
            )
            contentHeight += globe.size.height
            contentHeight += 16.0 + max(environment.safeInsets.bottom, 16.0)

            return CGSize(width: context.availableSize.width, height: contentHeight)
        }
    }
}

private final class StatsGlobeSheetContainerComponent: CombinedComponent {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let countries: ChannelStatsCountries
    let orientation: StatsGlobeOrientation?

    init(countries: ChannelStatsCountries, orientation: StatsGlobeOrientation?) {
        self.countries = countries
        self.orientation = orientation
    }

    static func ==(lhs: StatsGlobeSheetContainerComponent, rhs: StatsGlobeSheetContainerComponent) -> Bool {
        if lhs.countries != rhs.countries {
            return false
        }
        if lhs.orientation != rhs.orientation {
            return false
        }
        return true
    }

    static var body: Body {
        let sheet = Child(SheetComponent<EnvironmentType>.self)
        let animateOut = StoredActionSlot(Action<Void>.self)

        let sheetExternalState = SheetComponent<EnvironmentType>.ExternalState()

        return { context in
            let environment = context.environment[EnvironmentType.self]

            let controller = environment.controller

            let sheet = sheet.update(
                component: SheetComponent<EnvironmentType>(
                    content: AnyComponent<EnvironmentType>(StatsGlobeSheetContent(
                        countries: context.component.countries,
                        orientation: context.component.orientation,
                        dismiss: {
                            animateOut.invoke(Action { _ in
                                if let controller = controller() {
                                    controller.dismiss(completion: nil)
                                }
                            })
                        }
                    )),
                    style: .glass,
                    backgroundColor: .color(environment.theme.list.modalBlocksBackgroundColor),
                    followContentSizeChanges: true,
                    externalState: sheetExternalState,
                    animateOut: animateOut
                ),
                environment: {
                    environment
                    SheetComponentEnvironment(
                        metrics: environment.metrics,
                        deviceMetrics: environment.deviceMetrics,
                        isDisplaying: environment.value.isVisible,
                        isCentered: environment.presentsFloatingPanels,
                        hasInputHeight: !environment.inputHeight.isZero,
                        regularMetricsSize: CGSize(width: 430.0, height: 900.0),
                        dismiss: { animated in
                            if animated {
                                animateOut.invoke(Action { _ in
                                    if let controller = controller() {
                                        controller.dismiss(completion: nil)
                                    }
                                })
                            } else {
                                if let controller = controller() {
                                    controller.dismiss(completion: nil)
                                }
                            }
                        }
                    )
                },
                availableSize: context.availableSize,
                transition: context.transition
            )

            context.add(sheet
                .position(CGPoint(x: context.availableSize.width / 2.0, y: context.availableSize.height / 2.0))
            )

            if let controller = controller(), !controller.automaticallyControlPresentationContextLayout {
                let layout = ContainerViewLayout(
                    size: context.availableSize,
                    metrics: environment.metrics,
                    deviceMetrics: environment.deviceMetrics,
                    intrinsicInsets: UIEdgeInsets(top: 0.0, left: 0.0, bottom: max(environment.safeInsets.bottom, sheetExternalState.contentHeight), right: 0.0),
                    safeInsets: UIEdgeInsets(top: 0.0, left: environment.safeInsets.left, bottom: 0.0, right: environment.safeInsets.right),
                    reservedCorners: environment.reservedCorners,
                    division: nil,
                    additionalInsets: .zero,
                    statusBarHeight: environment.fullStatusBarHeight,
                    inputHeight: nil,
                    inputHeightIsInteractivellyChanging: false,
                    inVoiceOver: false,
                    presentedInFormSheet: false
                )
                controller.presentationContext.containerLayoutUpdated(layout, transition: context.transition.containedViewLayoutTransition)
            }

            return context.availableSize
        }
    }
}

/// The globe sheet. It opens at the turn of the card's globe it was opened from.
final class StatsGlobeSheetScreen: ViewControllerComponentContainer {
    /// The card's globe: it stops while the sheet covers it, so two globes do not render at once.
    private weak var sourceView: StatsGlobeView?

    init(context: AccountContext, sourceView: StatsGlobeView) {
        self.sourceView = sourceView

        super.init(
            context: context,
            component: StatsGlobeSheetContainerComponent(
                countries: sourceView.countries,
                orientation: sourceView.orientation
            ),
            navigationBarAppearance: .none,
            statusBarStyle: .ignore,
            theme: .default
        )

        self.navigationPresentation = .flatModal
        sourceView.isPaused = true
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let sourceView = self.sourceView
        Queue.mainQueue().async {
            sourceView?.isPaused = false
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // The sheet dismisses itself on a downward drag; the navigation controller's would fight it.
        self.view.disablesInteractiveModalDismiss = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.sourceView?.isPaused = false
    }
}
