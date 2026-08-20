# Third-Party Notices

This file records third-party code, assets, and runtime payloads that may be present in a full Arclume app distribution. The GPL notice in `LICENSE.txt` does not relicense these components.

## Swift package dependencies

The versions are pinned in `Arclume.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`. Preserve each dependency's upstream license and notice when redistributing a built app.

- [Alamofire](https://github.com/Alamofire/Alamofire)
- [Kingfisher](https://github.com/onevcat/Kingfisher)
- [SwiftUI-Flow](https://github.com/tevelee/SwiftUI-Flow)

## Bundled Runtime and game-mode payloads

The App and its public source tree include the following compatibility payloads. They remain separate works under their own terms; they are not relicensed by `LICENSE.txt` and must not be described as Arclume-owned open source.

- **Wine 11.0 / Arclume Wine 1.0.0** — Wine is LGPL-2.1-or-later. Its locked CodeWeavers FOSS source input, build scripts and Arclume patches are in [Arclume-Runtime](https://github.com/PigeonMuyz/Arclume-Runtime) at the Runtime release tag. The App ships an in-bundle notice and links the exact Runtime source release from its GitHub Release page.
- **DXVK** — distributed under the zlib/libpng license. Preserve its copyright notice. Upstream source: [doitsujin/dxvk](https://github.com/doitsujin/dxvk).
- **DXMT v0.80** — LGPL-2.1-or-later. Upstream source and license: [3Shain/dxmt](https://github.com/3Shain/dxmt).
- **GStreamer framework 1.28.1** — the archive contains component-specific licenses under `share/licenses/`. Keep that directory and provide the corresponding source location. Upstream release: [Sikarugir-App/gstreamer](https://github.com/Sikarugir-App/gstreamer/releases/tag/1.28.1).
- **MoltenVK and bundled Vulkan/Mesa pieces** — retain the notices that accompany their original distributions. The current CrossOver FOSS inventory identifies MoltenVK as Apache-2.0. Source: [KhronosGroup/MoltenVK](https://github.com/KhronosGroup/MoltenVK).
- **Noto Sans CJK SC Regular** — [SIL Open Font License 1.1](https://github.com/notofonts/noto-cjk/blob/main/OFL-1.1.txt).
- **Apple Game Porting Toolkit / D3DMetal 3 and 4** — bundled as Apple-provided compatibility components. They are not GPL-licensed by Arclume and are not represented as Arclume open source. The framework retains its supplied copyright and license materials; its `Resources/LICENSE` is an xxHash notice and is not the complete framework license. Apple product names and trademarks remain Apple property. Apple’s current Game Porting Toolkit material: [Apple Developer](https://developer.apple.com/games/game-porting-toolkit/).
- **NVIDIA NGX/DLSS files** — where present in a selected backend, these remain subject to NVIDIA’s applicable terms and are not GPL-licensed by Arclume. They are not offered as standalone downloads. Reference: [NVIDIA NGX terms](https://docs.nvidia.com/ngx/latest/ngx-eula/index.html).
- **Game-mode configuration** — the `config_bd_*.ini` and `jx3-normal-config.ini` files are Arclume launch/configuration presets. They do not include a game client, game assets, account data or entitlement material; the game and its services remain the property of their respective owners.

## Release source location

For every binary Release, the matching GitHub Release notes identify the exact App tag, Runtime tag and this document. The App tag and public Runtime repository provide the release source, Wine source lock, build scripts and Arclume patches; each separately identified component continues to use its own upstream source and license terms.
