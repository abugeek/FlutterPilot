## Unreleased

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
