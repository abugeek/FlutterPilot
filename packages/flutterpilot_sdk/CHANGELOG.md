## Unreleased

- Scrolling to a widget (scroll_into_view, and before a tap) pages through
  each list, including lazy, reversed, grid and nested horizontal lists,
  instead of swiping; a partial text match no longer stops the search
  ("Item 3" is not "Item 399"). `maxAttempts` is gone.

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
