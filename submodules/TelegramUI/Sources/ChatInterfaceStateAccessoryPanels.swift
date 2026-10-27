import Foundation
import UIKit
import AsyncDisplayKit
import TelegramCore
import AccountContext
import ChatPresentationInterfaceState
import ChatControllerInteraction
import AccessoryPanelNode
import ForwardAccessoryPanelNode
import ReplyAccessoryPanelNode
import SuggestPostAccessoryPanelNode
import ChatInputAccessoryPanel
import ChatInputMessageAccessoryPanel
import ComponentFlow
import TelegramNotices
import PresentationDataUtils
import Display
import Markdown
import TextFormat
import TelegramPresentationData
import AlertComponent
import ChannelDrafts
import TelegramStringFormatting

func textInputAccessoryPanel(
    context: AccountContext,
    chatPresentationInterfaceState: ChatPresentationInterfaceState,
    chatControllerInteraction: ChatControllerInteraction?,
    interfaceInteraction: ChatPanelInterfaceInteraction?
) -> AnyComponentWithIdentity<ChatInputAccessoryPanelEnvironment>? {
    if case .standard(.previewing) = chatPresentationInterfaceState.mode {
        return nil
    }
    if let _ = chatPresentationInterfaceState.interfaceState.selectionState {
        return nil
    }
    if chatPresentationInterfaceState.search != nil {
        return nil
    }
    
    switch chatPresentationInterfaceState.subject {
    case .pinnedMessages, .messageOptions:
        return nil
    default:
        break
    }
    
    if chatPresentationInterfaceState.interfaceState.editMessage == nil, let attachedDraft = chatPresentationInterfaceState.channelDrafts.attachedDraft {
        // Channel Drafts: the composer holds a draft taken with Use Draft. × clears the composer
        // and unlinks the draft, which stays as it was. A draft with media and no caption reads
        // "Photo", "Video"... as the Edit header does.
        var text = attachedDraft.text
        var textIsMediaKind = false
        if text.isEmpty, let media = attachedDraft.media.first, let kind = mediaContentKind(EngineMedia(media), strings: chatPresentationInterfaceState.strings) {
            text = stringForMediaKind(kind, strings: chatPresentationInterfaceState.strings).0.string
            textIsMediaKind = true
        }
        return AnyComponentWithIdentity(id: "channelDraft", component: AnyComponent(ChatInputMessageAccessoryPanel(
            context: context,
            contents: .custom(ChatInputMessageAccessoryPanel.Contents.Custom(
                id: AnyHashable(attachedDraft.id),
                title: chatPresentationInterfaceState.strings.ChannelDrafts_AttachedPanelTitle,
                text: text,
                textIsMediaKind: textIsMediaKind
            )),
            chatPeerId: chatPresentationInterfaceState.chatLocation.peerId,
            action: nil,
            dismiss: { _ in
                // As × in the Edit header: the composer gets back what it held before.
                interfaceInteraction?.unlinkChannelDraft()
            }
        )))
    }
    
    if let editMessage = chatPresentationInterfaceState.interfaceState.editMessage, chatPresentationInterfaceState.interfaceState.postSuggestionState == nil {
        if let editingUrlPreview = chatPresentationInterfaceState.editingUrlPreview, !editMessage.disableUrlPreviews.contains(editingUrlPreview.url) {
            var previousTapTimestamp: Double?
            return AnyComponentWithIdentity(id: "linkPreview", component: AnyComponent(ChatInputMessageAccessoryPanel(
                context: context,
                contents: .linkPreview(ChatInputMessageAccessoryPanel.Contents.LinkPreview(
                    url: editingUrlPreview.url,
                    webpage: editingUrlPreview.webPage
                )),
                chatPeerId: chatPresentationInterfaceState.chatLocation.peerId,
                action: { sourceView in
                    let timestamp = CFAbsoluteTimeGetCurrent()
                    if let previousTapTimestamp, previousTapTimestamp + 1.0 > timestamp {
                        return
                    }
                    previousTapTimestamp = CFAbsoluteTimeGetCurrent()
                    interfaceInteraction?.presentLinkOptions(sourceView)
                },
                dismiss: { _ in
                    interfaceInteraction?.dismissUrlPreview()
                }
            )))
        }
        
        if case let .customChatContents(customChatContents) = chatPresentationInterfaceState.subject, let draftsContents = customChatContents as? ChannelDraftsChatContents {
            // Channel Drafts: the edited draft is not a stored message, so the header shows its text
            // directly, or names its media in the secondary colour, as the Edit header does.
            let draft = draftsContents.draft(messageId: editMessage.messageId)
            var text = draft.map(channelDraftHeaderText) ?? ""
            var textIsMediaKind = false
            if text.isEmpty, let media = draft?.decodedMedia.first, let kind = mediaContentKind(EngineMedia(media), strings: chatPresentationInterfaceState.strings) {
                text = stringForMediaKind(kind, strings: chatPresentationInterfaceState.strings).0.string
                textIsMediaKind = true
            }
            return AnyComponentWithIdentity(id: "edit", component: AnyComponent(ChatInputMessageAccessoryPanel(
                context: context,
                contents: .custom(ChatInputMessageAccessoryPanel.Contents.Custom(
                    id: AnyHashable(editMessage.messageId),
                    title: chatPresentationInterfaceState.strings.ChannelDrafts_EditPanelTitle,
                    text: text,
                    textIsMediaKind: textIsMediaKind
                )),
                chatPeerId: nil,
                action: { _ in
                },
                dismiss: { _ in
                    interfaceInteraction?.setupEditMessage(nil, { _ in })
                }
            )))
        }
        
        return AnyComponentWithIdentity(id: "edit", component: AnyComponent(ChatInputMessageAccessoryPanel(
            context: context,
            contents: .edit(ChatInputMessageAccessoryPanel.Contents.Edit(
                id: editMessage.messageId,
                message: nil
            )),
            chatPeerId: chatPresentationInterfaceState.chatLocation.peerId,
            action: { _ in
            },
            dismiss: { _ in
                interfaceInteraction?.setupEditMessage(nil, { _ in })
            }
        )))
    } else if let urlPreview = chatPresentationInterfaceState.urlPreview, !chatPresentationInterfaceState.interfaceState.composeDisableUrlPreviews.contains(urlPreview.url) {
        var previousTapTimestamp: Double?
        return AnyComponentWithIdentity(id: "linkPreview", component: AnyComponent(ChatInputMessageAccessoryPanel(
            context: context,
            contents: .linkPreview(ChatInputMessageAccessoryPanel.Contents.LinkPreview(
                url: urlPreview.url,
                webpage: urlPreview.webPage
            )),
            chatPeerId: chatPresentationInterfaceState.chatLocation.peerId,
            action: { sourceView in
                let timestamp = CFAbsoluteTimeGetCurrent()
                if let previousTapTimestamp, previousTapTimestamp + 1.0 > timestamp {
                    return
                }
                previousTapTimestamp = CFAbsoluteTimeGetCurrent()
                interfaceInteraction?.presentLinkOptions(sourceView)
            },
            dismiss: { _ in
                interfaceInteraction?.dismissUrlPreview()
            }
        )))
    } else if let forwardMessageIds = chatPresentationInterfaceState.interfaceState.forwardMessageIds {
        var chatPeerId: EnginePeer.Id?
        if let peerId = chatPresentationInterfaceState.chatLocation.peerId {
            chatPeerId = peerId
        } else if case .customChatContents = chatPresentationInterfaceState.chatLocation {
            chatPeerId = context.account.peerId
        }
        if let chatPeerId {
            var previousTapTimestamp: Double?
            let theme = chatPresentationInterfaceState.theme
            let strings = chatPresentationInterfaceState.strings
            let nameDisplayOrder = chatPresentationInterfaceState.nameDisplayOrder
            
            return AnyComponentWithIdentity(id: "forward", component: AnyComponent(ChatInputMessageAccessoryPanel(
                context: context,
                contents: .forward(ChatInputMessageAccessoryPanel.Contents.Forward(
                    messageIds: forwardMessageIds,
                    forwardOptionsState: chatPresentationInterfaceState.interfaceState.forwardOptionsState
                )),
                chatPeerId: chatPeerId,
                action: { sourceView in
                    let timestamp = CFAbsoluteTimeGetCurrent()
                    if let previousTapTimestamp, previousTapTimestamp + 1.0 > timestamp {
                        return
                    }
                    previousTapTimestamp = CFAbsoluteTimeGetCurrent()
                    interfaceInteraction?.presentForwardOptions(sourceView)
                    let _ = ApplicationSpecificNotice.incrementChatForwardOptionsTip(accountManager: context.sharedContext.accountManager, count: 3).start()
                },
                dismiss: { sourceView in
                    Task { @MainActor [weak sourceView] in
                        guard let messageId = forwardMessageIds.first else {
                            return
                        }
                        guard let message = await context.engine.data.get(
                            TelegramEngine.EngineData.Item.Messages.Message(id: messageId)
                        ).get() else {
                            return
                        }
                        guard let peer = message.peers[message.id.peerId] else {
                            return
                        }
                        
                        let peerId = peer.id
                        let peerDisplayTitle = EnginePeer(peer).displayTitle(strings: strings, displayOrder: nameDisplayOrder)

                        let messageCount = Int32(forwardMessageIds.count)
                        let messages = strings.Conversation_ForwardOptions_Messages(messageCount)
                        let string: PresentationStrings.FormattedString
                        if peerId == context.account.peerId {
                            string = strings.Conversation_ForwardOptions_TextSaved(messages)
                        } else if peerId.namespace == Namespaces.Peer.CloudUser {
                            string = strings.Conversation_ForwardOptions_TextPersonal(messages, peerDisplayTitle)
                        } else {
                            string = strings.Conversation_ForwardOptions_Text(messages, peerDisplayTitle)
                        }

                        let font = Font.regular(15.0)
                        let boldFont = Font.semibold(15.0)
                        let body = MarkdownAttributeSet(font: font, textColor: theme.actionSheet.primaryTextColor)
                        let bold = MarkdownAttributeSet(font: boldFont, textColor: theme.actionSheet.primaryTextColor)
                        let text = addAttributesToStringWithRanges(string._tuple, body: body, argumentAttributes: [0: bold, 1: bold], textAlignment: .natural)
                        
                        var content: [AnyComponentWithIdentity<AlertComponentEnvironment>] = []
                        content.append(AnyComponentWithIdentity(
                            id: "title",
                            component: AnyComponent(
                                AlertTitleComponent(
                                    title: strings.Conversation_ForwardOptions_Title(messageCount)
                                )
                            )
                        ))
                        content.append(AnyComponentWithIdentity(
                            id: "text",
                            component: AnyComponent(
                                AlertTextComponent(content: .attributed(text))
                            )
                        ))
                        
                        let alertController = AlertScreen(
                            context: context,
                            configuration: AlertScreen.Configuration(actionAlignment: .vertical, allowInputInset: true),
                            content: content,
                            actions: [
                                .init(title: strings.Conversation_ForwardOptions_ShowOptions, action: {
                                    guard let sourceView else {
                                        return
                                    }
                                    interfaceInteraction?.presentForwardOptions(sourceView)
                                    let _ = ApplicationSpecificNotice.incrementChatForwardOptionsTip(accountManager: context.sharedContext.accountManager, count: 3).start()
                                }),
                                .init(title: strings.Conversation_ForwardOptions_CancelForwarding, type: .destructive, action: {
                                    interfaceInteraction?.dismissForwardMessages()
                                })
                            ]
                        )
                        interfaceInteraction?.presentController(alertController, nil)
                    }
                }
            )))
        } else {
            return nil
        }
    } else if let replyMessageSubject = chatPresentationInterfaceState.interfaceState.replyMessageSubject {
        var chatPeerId: EnginePeer.Id?
        if let peerId = chatPresentationInterfaceState.chatLocation.peerId {
            chatPeerId = peerId
        } else if case .customChatContents = chatPresentationInterfaceState.chatLocation {
            chatPeerId = context.account.peerId
        }
        if let chatPeerId {
            var previousTapTimestamp: Double?
            return AnyComponentWithIdentity(id: "reply", component: AnyComponent(ChatInputMessageAccessoryPanel(
                context: context,
                contents: .reply(ChatInputMessageAccessoryPanel.Contents.Reply(
                    id: replyMessageSubject.messageId,
                    quote: replyMessageSubject.quote,
                    innerSubject: replyMessageSubject.innerSubject,
                    message: nil
                )),
                chatPeerId: chatPeerId,
                action: { sourceView in
                    let timestamp = CFAbsoluteTimeGetCurrent()
                    if let previousTapTimestamp, previousTapTimestamp + 1.0 > timestamp {
                        return
                    }
                    previousTapTimestamp = CFAbsoluteTimeGetCurrent()
                    interfaceInteraction?.presentReplyOptions(sourceView)
                },
                longPressAction: { _ in
                    interfaceInteraction?.navigateToMessage(replyMessageSubject.messageId, false, true, ChatLoadingMessageSubject.generic)
                },
                dismiss: { _ in
                    interfaceInteraction?.setupReplyMessage(nil, nil, { _, f in f() })
                }
            )))
        } else {
            return nil
        }
    } else if let postSuggestionState = chatPresentationInterfaceState.interfaceState.postSuggestionState {
        var previousTapTimestamp: Double?
        return AnyComponentWithIdentity(id: "suggestPost", component: AnyComponent(ChatInputMessageAccessoryPanel(
            context: context,
            contents: .suggestPost(ChatInputMessageAccessoryPanel.Contents.SuggestPost(
                state: postSuggestionState
            )),
            chatPeerId: chatPresentationInterfaceState.chatLocation.peerId,
            action: { sourceView in
                let timestamp = CFAbsoluteTimeGetCurrent()
                if let previousTapTimestamp, previousTapTimestamp + 1.0 > timestamp {
                    return
                }
                previousTapTimestamp = CFAbsoluteTimeGetCurrent()
                interfaceInteraction?.presentSuggestPostOptions()
            },
            dismiss: { _ in
                interfaceInteraction?.dismissSuggestPost()
            }
        )))
    }
    
    return nil
}

func accessoryPanelForChatPresentationIntefaceState(_ chatPresentationInterfaceState: ChatPresentationInterfaceState, context: AccountContext, currentPanel: AccessoryPanelNode?, chatControllerInteraction: ChatControllerInteraction?, interfaceInteraction: ChatPanelInterfaceInteraction?) -> AccessoryPanelNode? {
    if "".isEmpty {
        return nil
    }
    
    if case .standard(.previewing) = chatPresentationInterfaceState.mode {
        return nil
    }
    if let _ = chatPresentationInterfaceState.interfaceState.selectionState {
        return nil
    }
    if chatPresentationInterfaceState.search != nil {
        return nil
    }
    
    switch chatPresentationInterfaceState.subject {
    case .pinnedMessages, .messageOptions:
        return nil
    default:
        break
    }
    
    if let editMessage = chatPresentationInterfaceState.interfaceState.editMessage, chatPresentationInterfaceState.interfaceState.postSuggestionState == nil {
        let _ = editMessage
        return nil
    } else if let urlPreview = chatPresentationInterfaceState.urlPreview, !chatPresentationInterfaceState.interfaceState.composeDisableUrlPreviews.contains(urlPreview.url) {
        if let previewPanelNode = currentPanel as? WebpagePreviewAccessoryPanelNode {
            previewPanelNode.interfaceInteraction = interfaceInteraction
            previewPanelNode.replaceWebpage(url: urlPreview.url, webpage: urlPreview.webPage)
            previewPanelNode.updateThemeAndStrings(theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings)
            return previewPanelNode
        } else {
            let panelNode = WebpagePreviewAccessoryPanelNode(context: context, url: urlPreview.url, webpage: urlPreview.webPage, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings)
            panelNode.interfaceInteraction = interfaceInteraction
            return panelNode
        }
    } else if let forwardMessageIds = chatPresentationInterfaceState.interfaceState.forwardMessageIds {
        if let forwardPanelNode = currentPanel as? ForwardAccessoryPanelNode, forwardPanelNode.messageIds == forwardMessageIds {
            forwardPanelNode.interfaceInteraction = interfaceInteraction
            forwardPanelNode.updateThemeAndStrings(theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, forwardOptionsState: chatPresentationInterfaceState.interfaceState.forwardOptionsState)
            return forwardPanelNode
        } else {
            let panelNode = ForwardAccessoryPanelNode(context: context, messageIds: forwardMessageIds, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, fontSize: chatPresentationInterfaceState.fontSize, nameDisplayOrder: chatPresentationInterfaceState.nameDisplayOrder, forwardOptionsState: chatPresentationInterfaceState.interfaceState.forwardOptionsState, animationCache: chatControllerInteraction?.presentationContext.animationCache, animationRenderer: chatControllerInteraction?.presentationContext.animationRenderer)
            panelNode.interfaceInteraction = interfaceInteraction
            return panelNode
        }
    } else if let replyMessageSubject = chatPresentationInterfaceState.interfaceState.replyMessageSubject {
        if let replyPanelNode = currentPanel as? ReplyAccessoryPanelNode, replyPanelNode.messageId == replyMessageSubject.messageId && replyPanelNode.quote == replyMessageSubject.quote {
            replyPanelNode.interfaceInteraction = interfaceInteraction
            replyPanelNode.updateThemeAndStrings(theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings)
            return replyPanelNode
        } else {
            var chatPeerId: EnginePeer.Id?
            if let peerId = chatPresentationInterfaceState.chatLocation.peerId {
                chatPeerId = peerId
            } else if case .customChatContents = chatPresentationInterfaceState.chatLocation {
                chatPeerId = context.account.peerId
            }
            
            if let chatPeerId {
                let panelNode = ReplyAccessoryPanelNode(context: context, chatPeerId: chatPeerId, messageId: replyMessageSubject.messageId, quote: replyMessageSubject.quote, innerSubject: replyMessageSubject.innerSubject, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, nameDisplayOrder: chatPresentationInterfaceState.nameDisplayOrder, dateTimeFormat: chatPresentationInterfaceState.dateTimeFormat, animationCache: chatControllerInteraction?.presentationContext.animationCache, animationRenderer: chatControllerInteraction?.presentationContext.animationRenderer)
                panelNode.interfaceInteraction = interfaceInteraction
                return panelNode
            } else {
                return nil
            }
        }
    } else if chatPresentationInterfaceState.interfaceState.postSuggestionState != nil {
        if let replyPanelNode = currentPanel as? SuggestPostAccessoryPanelNode {
            replyPanelNode.interfaceInteraction = interfaceInteraction
            replyPanelNode.updateThemeAndStrings(theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings)
            return replyPanelNode
        } else {
            let panelNode = SuggestPostAccessoryPanelNode(context: context, theme: chatPresentationInterfaceState.theme, strings: chatPresentationInterfaceState.strings, nameDisplayOrder: chatPresentationInterfaceState.nameDisplayOrder, dateTimeFormat: chatPresentationInterfaceState.dateTimeFormat, animationCache: chatControllerInteraction?.presentationContext.animationCache, animationRenderer: chatControllerInteraction?.presentationContext.animationRenderer)
            panelNode.interfaceInteraction = interfaceInteraction
            return panelNode
        }
    } else {
        return nil
    }
}
