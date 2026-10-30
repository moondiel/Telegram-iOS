# Mention Cards — decision log

Each entry is one decision and the reason for it. A decision that was later replaced stays in the
list, marked "Replaced by D-0xx". Entries marked (moondiel) are design calls made by the author.

## Base (2026-10-30)

**D-001. A separate branch from the clean base.** `feature/mention-cards` starts from `16a3d3c5`,
like the other features, and shares no code with them. It carries the same Xcode 26 build fix,
which is left out of the patch.

## Look (2026-10-30)

**D-002. A block of its own, like a quote. (moondiel)** A pill inside the line was the other
option. The block has room for the avatar, the name and the username, and reads as the quote
blocks Telegram already draws.

**D-003. Both kinds of mention. (moondiel)** `@username` and a name linked to a person both become
cards. A linked name without a username gets a one-line card.

**D-004. Everywhere. (moondiel)** Every chat, group and channel, not only channel posts.

**D-005. The quote's bar and tint, the sender's name colours.** A message's quotes take the
sender's name colours; the card takes the same, so it belongs to the message. The name is semibold
in that colour, the username is the bubble's secondary text colour, at the quote font's size.

## How it is drawn (2026-10-30)

**D-006. The card is text in the message, not a view over it.** Laying a view over the bubble would
need the bubble to measure room for it, and selection, highlight, truncation and the date's
placement would all need to know. As text inside a block quote, the card gets all of that from the
text node. The only additions are a `.mention` block kind (the quote without its icon) and a
generic embedded-layer hook for the avatar, beside the one custom emoji use.

**D-007. The mention's own tap attribute on the whole card.** The bubble already opens an account
for `PeerMention` and `PeerTextMention`, and offers their long-press menu. Putting the mention's
attribute on the whole card reuses that unchanged.

**D-008. Copy gives back what was written.** The card's text carries the mention as written in an
`OriginalTextAttribute`, the mechanism custom emoji use, so selecting and copying a message with a
card give the original text, `@username` included.

**D-009. A username is looked up once, then the message is laid out again.** Layout cannot wait on
the network, so a message with an unknown username shows the mention as written, starts the
lookup, and asks for a new layout when it answers. `resolvePeerByName` caches answers for two days
and the resolver keeps them for the session, so this happens once per username. A username with no
account stays a plain mention.

**D-010. Mentions that stay inline.** Inside a quote or a code block (a block cannot hold another),
under a spoiler (a card would reveal it), or where a custom emoji sits in the mention.
