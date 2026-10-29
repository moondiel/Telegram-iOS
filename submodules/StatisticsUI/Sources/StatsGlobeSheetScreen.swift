import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import ViewControllerComponent
import SheetComponent
import MultilineTextComponent
import BundleIconComponent
import GlassBarButtonComponent

// Subscriber Globe: the globe opened from the card, in a sheet. See docs/subscriber-globe/README.md.
//
// The sheet is Telegram's glass sheet with a glass close button, as statistics' transaction info
// uses it (`TransactionInfoScreen`). It holds a large globe, opened at the card's turn, that turns
// any way and zooms.

/// The globe, as large as the sheet's width allows.
private final class StatsGlobeSheetBodyComponent: Component {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let countries: ChannelStatsCountries
    let orientation: StatsGlobeOrientation?

    init(theme: PresentationTheme, strings: PresentationStrings, countries: ChannelStatsCountries, orientation: StatsGlobeOrientation?) {
        self.theme = theme
        self.strings = strings
        self.countries = countries
        self.orientation = orientation
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
        return true
    }

    final class View: UIView {
        private var globeView: StatsGlobeView?

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
                self.addSubview(globeView)
            }
            let size = CGSize(width: width, height: min(width + 20.0, 460.0))
            globeView.frame = CGRect(origin: CGPoint(), size: size)
            globeView.radius = floor(min(size.width, size.height) / 2.0 - 30.0)
            return size
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
                    orientation: component.orientation
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
