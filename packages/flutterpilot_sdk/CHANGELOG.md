## Unreleased

- A label that only a container holds (a tap-to-dismiss detector over the
  whole page contains every label on screen) no longer resolves to that
  container: tapping "Inventory Tab 3 of 5" pressed whatever sat at the centre
  of the screen. A NavigationBar destination is found by the name the tappable
  list gives it.
- The contrast audit holds an icon to 3:1 (WCAG 1.4.11, graphics), not the
  4.5:1 of text, and says "an icon" in the finding.
- The reading-order audit no longer reports content scrolled below the screen
  followed by a bottom bar as a jump back up.
- Apps built on the separate `material_ui` / `cupertino_ui` packages (the
  same widgets as Flutter's under other classes): text fields are found by
  their label or hint, buttons by their tooltip, sliders and toggles are
  recognised, disabled controls are exempt from the contrast audit, and the
  test recorder sees their controls.
- `execute_action_chain` waits up to 3 s for a step's target to appear, so a
  tap that opens a page can be followed by a tap on that page.
- Typing into a target that holds several fields is refused instead of
  filling the first one.
- The reading-order audit no longer reports a second column as a jump back
  up the screen.
- Scrolling to a widget (scroll_into_view, and before a tap) pages through
  each list, including lazy, reversed, grid and nested horizontal lists,
  instead of swiping; a partial text match no longer stops the search
  ("Item 3" is not "Item 399"). `maxAttempts` is gone.
- Screenshots (and the contrast audit) capture the whole window: dialogs,
  menus and sheets on the root navigator were missing. The AI tap badge is
  removed a frame before the capture.
- Removed service extensions no FlutterPilot tool called: `getStreamLogs`,
  `clearStreamLogs`, `tapAt`, `jumpToScreen`, `getPerfMetrics`,
  `getDebugLogs`, `auditMemoryHealth`; and the `StreamInspector` and
  `MemoryAuditor` classes behind them.

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
