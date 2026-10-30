load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

swift_library(
    name = "ChatMessageMentionPills",
    module_name = "ChatMessageMentionPills",
    srcs = glob([
        "Sources/**/*.swift",
    ]),
    copts = [
        "-warnings-as-errors",
    ],
    deps = [
        "//submodules/Display",
        "//submodules/SSignalKit/SwiftSignalKit",
        "//submodules/TelegramCore",
        "//submodules/TextFormat",
        "//submodules/AccountContext",
        "//submodules/LocalizedPeerData",
        "//submodules/AvatarNode",
        "//submodules/TelegramUI/Components/InteractiveTextComponent",
    ],
    visibility = [
        "//visibility:public",
    ],
)
