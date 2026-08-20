# Third-Party Notices

This file records third-party code, assets, and runtime payloads that may be present in a full Arclume app distribution. The GPL notice in `LICENSE.txt` does not relicense these components.

## Upstream source

Arclume is an independent, unofficial product derived from [Procyon](https://github.com/italomandara/Procyon). The upstream source and its copyright notices remain subject to the GNU GPL v3.0. Keep `LICENSE.txt` and the notices in the relevant source files.

## Swift package dependencies

The versions are pinned in `Arclume.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Preserve each dependency's upstream license and notice when redistributing a built app.

- [Alamofire](https://github.com/Alamofire/Alamofire)
- [Kingfisher](https://github.com/onevcat/Kingfisher)
- [SwiftUI-Flow](https://github.com/tevelee/SwiftUI-Flow)

## Optional runtime payloads

The following items are not part of a GPL source-only release unless their individual license and redistribution terms have been verified. A public source snapshot should omit prebuilt runtime payloads and game-specific data, while retaining this inventory for a separately assembled, compliant distribution.

- **GStreamer framework 1.28.1** — the archive contains component-specific license files under `share/licenses/`. Keep the complete license directory and the corresponding source offer when redistributing it. Upstream source: [Sikarugir-App/gstreamer](https://github.com/Sikarugir-App/gstreamer/releases/tag/1.28.1).
- **DXMT v0.80** — distributed by its upstream project under its own terms; retain the upstream license and notices. Upstream source: [3Shain/dxmt](https://github.com/3Shain/dxmt/releases/tag/v0.80).
- **GPTK / D3DMetal runtime** — the local framework `Resources/LICENSE` is an xxHash BSD 2-Clause notice and does not by itself establish the license for the entire framework. Verify the applicable Apple/GPTK distribution terms before redistributing the framework or its bundled Wine payloads. Upstream release reference: [Game Porting Toolkit releases](https://github.com/Gcenx/game-porting-toolkit/releases).
- **Noto Sans CJK SC Regular** — subject to the [SIL Open Font License 1.1](https://github.com/notofonts/noto-fonts/blob/main/LICENSE); include the required font license and notices when distributing the font.
- **Game-specific configuration/data** — `jx3-normal-config.ini` is a game-related configuration snapshot. Its provenance and redistribution permission must be verified separately; do not describe it as GPL source.
- **NVIDIA NGX/DLSS runtime DLLs** — the `nvngx-jx3.tar.xz` payload, when present, is a proprietary runtime component and is not covered by this repository's GPL notice. Its provenance and permission to redistribute have not been established in this repository; omit it from a public source snapshot and do not publish it in a binary release until separately authorized. See the [NVIDIA NGX EULA](https://docs.nvidia.com/ngx/latest/ngx-eula/index.html).

## Source-only release boundary

The source-only publication intentionally contains the project source, tests, build metadata, and license documents, but not the prebuilt runtime libraries, compressed dependency archives, fonts, or game-specific configuration/data listed above. Those files require a separate, component-by-component redistribution review.
