# Mention Cards — decision log

Each entry is one decision and the reason for it. A decision that was later replaced stays in the
list, marked "Replaced by D-0xx". Entries marked (moondiel) are design calls made by the author.

## Base (2026-10-30)

**D-001. A separate branch from the clean base.** `feature/mention-cards` starts from `16a3d3c5`,
like the other features, and shares no code with them. It carries the same Xcode 26 build fix,
which is left out of the patch.

## Look (2026-10-30)

**D-002. A block of its own, like a quote. (moondiel)** Replaced by D-011. A pill inside the line was the other
option. The block has room for the avatar, the name and the username, and reads as the quote
blocks Telegram already draws.

**D-003. Both kinds of mention. (moondiel)** `@username` and a name linked to a person both become
cards. A linked name without a username gets a one-line card.

**D-004. Everywhere. (moondiel)** Every chat, group and channel, not only channel posts.

**D-005. The quote's bar and tint, the sender's name colours.** Replaced by D-011. A message's quotes take the
sender's name colours; the card takes the same, so it belongs to the message. The name is semibold
in that colour, the username is the bubble's secondary text colour, at the quote font's size.

## How it is drawn (2026-10-30)

**D-006. The card is text in the message, not a view over it.** Replaced by D-012. Laying a view over the bubble would
need the bubble to measure room for it, and selection, highlight, truncation and the date's
placement would all need to know. As text inside a block quote, the card gets all of that from the
text node. The only additions are a `.mention` block kind (the quote without its icon) and a
generic embedded-layer hook for the avatar, beside the one custom emoji use.

**D-007. The mention's own tap attribute on the whole card.** Replaced by D-012. The bubble already opens an account
for `PeerMention` and `PeerTextMention`, and offers their long-press menu. Putting the mention's
attribute on the whole card reuses that unchanged.

**D-008. Copy gives back what was written.** No longer needed: the text is not changed (D-012). The card's text carries the mention as written in an
`OriginalTextAttribute`, the mechanism custom emoji use, so selecting and copying a message with a
card give the original text, `@username` included.

**D-009. A username is looked up once, then the message is laid out again.** Kept, now for the preview (D-013). Layout cannot wait on
the network, so a message with an unknown username shows the mention as written, starts the
lookup, and asks for a new layout when it answers. `resolvePeerByName` caches answers for two days
and the resolver keeps them for the session, so this happens once per username. A username with no
account stays a plain mention.

**D-010. Mentions that stay inline.** Replaced by D-015. Inside a quote or a code block (a block cannot hold another),
under a spoiler (a card would reveal it), or where a custom emoji sits in the mention.

## The card as a link preview (2026-10-30)

**D-011. The card looks like the preview of a `t.me` link. (moondiel)** Replaced by D-021. Telegram already draws a
card for an account: the preview a `t.me/username` link gets, with the name, the description, the
avatar and "View Channel" / "Send Message". The mention's card is that card, so it reads as part
of Telegram rather than a new element.

**D-012. Telegram's own preview, not a copy of it.** Replaced by D-021. The preview is the server's
(`messages.getWebPagePreview`, as for a pasted link) and is drawn by Telegram's
`ChatMessageWebpageBubbleContentNode`, on a copy of the message carrying it. Layout, colours,
avatar, button, tap and long press are therefore the link preview's own code. The text is left as
it was written, so the earlier changes to the text nodes (the `.mention` quote kind and the
embedded avatar layer) were removed.

**D-013. Asked once per username, kept for the session.** Replaced by D-021. Layout cannot wait on the network, so the
message is laid out without the card, the preview is asked for, and the message is laid out again
when it comes. Usernames without a preview are remembered too, so they are not asked about again.

**D-014. One card per message, for the first mention.** Replaced by D-021. Telegram shows one preview per message, and
a stack of cards would bury the text. While an earlier mention's answer is pending there is no
card, so the card does not jump between mentions.

**D-015. Where there is no card.** Replaced by D-021. Media captions, messages with their own link preview, sponsored
messages and secret chats (a preview request would tell the server about the mention), as for link
previews; mentions under a spoiler (the card would reveal them); text mentions of accounts without
a username (a preview needs a `t.me` link).

**D-016. Opening without the "Open this link?" question.** Replaced by D-021. The copy marks the preview as safe:
the link is Telegram's own `t.me` link to the mentioned account, not one the sender typed.

## The composer (2026-10-30)

**D-017. A mention gets the link preview in the composer too. (moondiel)** Replaced by D-021. Typing `@username` shows
the account's preview above the field, as a pasted `t.me` link does. It is done by counting the
mention as its `t.me` link in `detectUrls`, so the panel, ✕, the link-preview options and the
sending are all Telegram's own, unchanged.

**D-018. Sent as a real link preview.** Replaced by D-021. The preview goes out as `inputMediaWebPage` with the `t.me`
link, which the server accepts without the link being in the text. The message then carries the
preview for everyone, in every app; drawing cards when reading (D-012) remains for messages without
one.

**D-019. The text's own links come first.** Replaced by D-021. A mention is added after the text's links, so a message
with a link keeps that link's preview, and the mentions are offered as the other links in the
preview options.

**D-020. Closing the preview is respected.** Replaced by D-021. A message whose preview was closed with ✕ carries
`disableLinkPreviews`, and this app does not draw a card for it either.

## The pill in the line (2026-10-30)

**D-021. A pill in the line instead of a card. (moondiel)** The card turned out to be what Telegram
already draws for a `t.me` link, so it added little. A mention drawn in the line with its avatar and
name, as Notion, Slack and Discord do, is something no Telegram app has. The link-preview card, the
composer preview and the `.mention` quote kind are removed.

**D-022. The pill is one run of the text.** The mention becomes a single character whose width a
run delegate sets, with a layer drawing the pill in its place, the way custom emoji sit in a line.
So the pill flows and wraps with the text, and the tap attribute and `OriginalTextAttribute` on
that character keep tapping, the menu, selection and copy as they were (D-007, D-008, D-009 hold).

**D-023. Link colour, medium weight, short name.** The capsule is the message's link colour at 15%
and the name is in the link colour, so a pill reads as the link it replaces in both incoming and
outgoing bubbles. The name is `compactDisplayTitle` (a user's first name, a channel's title), as
mention pills elsewhere show one short name, shortened with an ellipsis past 220 pt.

**D-024. The line grows by 1 pt above and below.** The capsule is a little taller than the text so
the avatar has room; lines without a pill keep their height.
