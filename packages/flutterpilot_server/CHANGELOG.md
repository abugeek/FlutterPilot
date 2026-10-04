## Unreleased

- `set_app_settings(windowSize: "390x844")` resizes a macOS desktop app's
  window (its standard window, not a dialog in front) and reports the
  viewport the app then has; other platforms are refused with the reason.
- `navigate_to` waits (up to 1.5 s) for the page transition, so the next call
  sees the new page and not the one underneath.
- `hot_reload` on a sandboxed macOS app explains the permission the Flutter
  tool is missing instead of a bare failure.

## 0.1.0

- Initial release
- Core SDK with 20+ service extensions for AI-native Flutter introspection
- Widget tree capture with layout positions and source locations
- Screenshot capture as PNG
- Error interception and buffering
- Navigation stack tracking
- UI automation: tap, scroll, text entry
- Locale and theme override at runtime
- Performance metrics (FPS)
- Test recording and generation
- State inspection and injection via plugin system
