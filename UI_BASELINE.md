# MusicXS2 UI baseline — locked

The only approved interface is the **original MusicX GitHub Actions Build 486**, commit `d2f825a48b06207356620aef38e780b57268b11e`.

## Canonical interface files
- `MusicX/Features/Home/ContentView.swift`
- `MusicX/Features/Discovery/MusicDiscoveryPage.swift`
- `MusicX/Features/Home/HomeArtwork.swift`
- `MusicX/Features/Home/HomeScrollBounceDisabler.swift`
- `MusicX/DesignSystem/MusicXTheme.swift`
- `MusicX/Assets.xcassets/AppIcon.appiconset/AppIcon.svg`

These files form the approved visual baseline. The current test branch includes intentional **data-loading changes** inside some of these files; do not reset them wholesale or replace them with old feature-branch UI files.

## Development rules
1. Do not copy `ContentView.swift` or `MusicDiscoveryPage.swift` from `feature/official-collections-dual-source`, Build 338, or other older UI revisions.
2. Do not change layouts, gradients, typography, artwork, mini-player, tab bar, or app icon while implementing catalogs, search, or playback.
3. Make backend changes in the source, resource-engine, and catalog layers whenever possible; if view-file data loading must change, preserve its SwiftUI view/layout code.
4. Do not modify `huangenxu-prog/MusicX` (original repo).
5. Before merging or building, inspect UI file diffs and verify they contain only intentional data/behavior changes.

## Existing legacy UI
There is no second active Home or Discovery SwiftUI implementation in this branch to safely delete. Older UI versions remain in Git history/other branches, not in the active Swift source tree. Do not delete shared assets or player dependencies simply because they are old.
