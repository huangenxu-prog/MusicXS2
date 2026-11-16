# MusicXS2 UI Design Freeze — Approved Baseline

Status: FROZEN / APPROVED BY PRODUCT OWNER
Approved build: GitHub Actions #178 (successful)
Approved UI source commit: 4c164b5403039096a09cc791d883f22c5f739403
Branch at approval: test/build-486-complete-source
Date: 2026-11-16

## Non-negotiable rule

Preserve the appearance and interactions of the approved #178 interface. Do not restore older layouts, colors, controls, background treatments, or navigation patterns. Any visible UI deviation requires the product owner's explicit approval *before changing code*. Functional additions should reuse existing visual components and conventions. Code refactoring must be visually neutral unless an exception is approved.

## Approved visual/interaction baseline

- Home: existing immersive gradient, header, rankings, and card grids; five new songs with real artwork, truncated song titles, duration when known, compact playing waveform by duration, no ellipsis menu or selected-row background highlight.
- Home recommendation entry cards: Daily Recommendations and My Favorites; preserve current gradients, hierarchy, spacing, icon styles and text.
- Daily Recommendations: same detail-header design as New Releases; first QQ + first NetEase recommendation collections only, de-duplicated, at most 50 songs; no multi-playlist backfill.
- My Favorites: same approved detail-page visual language; existing favorites store, with tabs for liked songs and future imported playlists; preserve existing music library favorites and recent-played features.
- New Releases: illustrated vinyl artwork, text hierarchy, wide Play All, round Shuffle, and song list section.
- Recommended playlist and music category details: shared cover + title + metadata header, gentle violet atmosphere, wide Play All, round Shuffle; do not replace with the old dual-wide-buttons layout.
- Track rows elsewhere: real cover first; truncated single-line song title and artist; true duration only (hide missing duration); playing indicator immediately before duration; subtle ellipsis menu for favorite/unfavorite.
- Playlist collection browse page: approved full-page navigation, violet gradient and wave, three-column cover grid.
- Mini player and bottom tabs: preserve approved size, location, spacing, glass/dark style and interactions.
- Maintain existing page transitions, back navigation, music playback, audio source routing, lyrics and caching unless explicitly requested.

## Change control

1. Explicitly enumerate intended file/page changes before implementing.
2. Make the smallest necessary change; do not “improve” unrelated stable screens.
3. Reuse approved components rather than creating alternative styling.
4. For any user-visible UI change, obtain prior approval and compare against this frozen baseline.
5. Report changed files, commit SHA, build status, and real-device validation separately.
6. Use commit 4c164b5 / build #178 as the visual rollback reference, not as a command to roll back other future functional changes.

This file documents a product design freeze; it does not technically lock branch writes or enforce GitHub branch protection.
