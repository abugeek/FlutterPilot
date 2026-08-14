# FlutterPilot Documentation Index

Complete guide to all FlutterPilot documentation.

## 📚 Documentation Overview

FlutterPilot documentation is organized into focused guides:

### **Getting Started**
- **[README.md](../README.md)** — Overview, features, quick start
- **[SETUP.md](./SETUP.md)** — Platform-specific installation and configuration
- **[GETTING_STARTED.md](#getting-started-guide)** ← Start here for first-time users

### **Using FlutterPilot**
- **[AI_AGENTS.md](./AI_AGENTS.md)** — How to use with Claude, ChatGPT, Cursor
- **[TOOLS.md](../TOOLS.md)** — Complete reference for the current MCP tool set
- **[BEST_PRACTICES.md](./BEST_PRACTICES.md)** — Production patterns and recommendations

### **Development**
- **[PLUGINS.md](./PLUGINS.md)** — Creating custom plugins for state managers
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — System design and internal structure
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — How to contribute to FlutterPilot

### **Support**
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** — Common issues and solutions
- **[FAQ](#frequently-asked-questions)** ← Common questions

---

## 🚀 Quick Navigation

### I want to...

#### Get FlutterPilot working in my app
→ Go to [SETUP.md](./SETUP.md)
- Platform-specific setup (iOS, Android, Web, macOS, Windows)
- Plugin configuration
- Verification steps

#### Use FlutterPilot with Claude AI
→ Go to [AI_AGENTS.md](./AI_AGENTS.md)
- MCP configuration for Claude
- Prompt templates
- Example workflows
- Claude vs ChatGPT vs Cursor

#### Know what tools are available
→ Go to [../TOOLS.md](../TOOLS.md)
- MCP tools reference with examples
- Categorized by function
- Parameter documentation

#### Debug an issue
→ Go to [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- Installation issues
- Connection problems
- Tool execution failures
- Platform-specific problems
- FAQ

#### Create a custom plugin
→ Go to [PLUGINS.md](./PLUGINS.md)
- Plugin architecture overview
- Step-by-step creation guide
- Testing plugins
- Examples (GetX, Firebase, etc.)

#### Understand the codebase
→ Go to [ARCHITECTURE.md](./ARCHITECTURE.md)
- System design diagram
- Component breakdown
- Data flow explanation
- Plugin system internals

#### Follow best practices
→ Go to [BEST_PRACTICES.md](./BEST_PRACTICES.md)
- Setup recommendations
- Widget key patterns
- State management tips
- Error handling
- Security guidelines
- Testing patterns

#### See example code
→ Go to [examples/](../examples/)
- Example Flutter app with FlutterPilot
- Demonstrates all major features

---

## 📖 Complete Reading Guide

### For First-Time Users (Start Here)

1. **[README.md](../README.md)** (5 min) — Understand what FlutterPilot is
2. **[SETUP.md](./SETUP.md)** (10 min) — Install and run it
3. **This page / [AI_AGENTS.md](./AI_AGENTS.md)** (10 min) — Use with AI

That's enough to start!

### For Daily Users

- **[TOOLS.md](../TOOLS.md)** — Reference when you need a specific tool
- **[BEST_PRACTICES.md](./BEST_PRACTICES.md)** — Patterns for common tasks
- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** — When something breaks

### For Contributors

- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — How to contribute
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — How it works internally
- **[PLUGINS.md](./PLUGINS.md)** — Creating new plugins

### For Advanced Users

- **[PLUGINS.md](./PLUGINS.md)** — Create custom plugins
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** — Understand internals
- GitHub Issues — Contribute fixes

---

## 📋 Documentation by Use Case

### Use Case 1: I Want to Add FlutterPilot to My Existing App

**Path:**
1. [README.md](../README.md) — Understand it
2. [SETUP.md](./SETUP.md) — Follow setup
3. [TOOLS.md](../TOOLS.md) — Learn what tools you have
4. [BEST_PRACTICES.md](./BEST_PRACTICES.md) — Use correctly

**Time:** ~20 minutes to setup, then read tools reference

---

### Use Case 2: I Want to Use FlutterPilot with Claude AI

**Path:**
1. [README.md](../README.md) — Understand it
2. [SETUP.md](./SETUP.md) — Get it running
3. [AI_AGENTS.md](./AI_AGENTS.md) — Configure Claude
4. [TOOLS.md](../TOOLS.md) — Reference tools (Claude will use them)

**Time:** ~30 minutes to setup, then you're ready

---

### Use Case 3: I'm Debugging a Problem

**Path:**
1. [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — Find your issue
2. [SETUP.md](./SETUP.md) — Verify your setup
3. [BEST_PRACTICES.md](./BEST_PRACTICES.md) — Check if you're doing it right

**Time:** ~10 minutes to fix most issues

---

### Use Case 4: I Want to Create a Custom Plugin

**Path:**
1. [ARCHITECTURE.md](./ARCHITECTURE.md) — Understand plugin system
2. [PLUGINS.md](./PLUGINS.md) — Follow creation guide
3. [BEST_PRACTICES.md](./BEST_PRACTICES.md) → Testing plugins section
4. [CONTRIBUTING.md](../CONTRIBUTING.md) — Submit if you want to share

**Time:** ~2 hours to create first plugin

---

### Use Case 5: I Want to Understand How FlutterPilot Works

**Path:**
1. [README.md](../README.md) — High-level overview
2. [ARCHITECTURE.md](./ARCHITECTURE.md) — Detailed design
3. [PLUGINS.md](./PLUGINS.md) — Plugin system
4. Read source code in `packages/`

**Time:** ~1-2 hours for good understanding

---

## 🔍 Tool Categories Reference

Quick links to tool categories in [TOOLS.md](../TOOLS.md):

### **Screenshots & Layout** (5 tools)
For capturing visuals and understanding UI structure
- `capture_screenshot` — Get PNG
- `get_widget_tree` — Widget hierarchy
- `get_widget_properties` — Read widget state
- `compare_screenshots` — Visual regression
- `save_screenshot_baseline` — Save for regression

### **UI Automation** (15 tools)
For programmatically interacting with the UI
- `tap_widget` — Tap by key
- `enter_text` — Type text
- `scroll` — Scroll widgets
- `set_slider_value` — Change slider
- (+ 11 more interaction tools)

### **Navigation & Routing** (8 tools)
For controlling navigation flow
- `navigate_to` — Go to route
- `get_navigation_stack` — View route history
- `press_back` — Go back
- (+ 5 more navigation tools)

### **State Inspection** (19 tools)
For inspecting state managers
- `get_bloc_state` — Bloc inspection
- `get_riverpod_state` — Riverpod inspection
- `get_app_summary` — Current route + errors
- (+ 16 more state tools)

### **Recording & Testing** (6 tools)
For test automation and recording
- Various recording and replay tools

### **DevTools Integration** (12 tools)
For deep inspection like DevTools
- Performance profiling
- Memory analysis
- DevTools command execution

### **Network** (via Dio plugin)
For HTTP mocking and inspection
- `add_http_mock` — Mock endpoint
- `get_network_logs` — Request log
- `simulate_network` — Network conditions

**See [TOOLS.md](../TOOLS.md) for complete reference with examples.**

---

## 🛠️ Setup Checklist

### Quick Setup (5 minutes)

- [ ] Read [README.md](../README.md) overview
- [ ] Run `flutter pub add --dev flutterpilot_sdk`
- [ ] Add `FlutterPilot.initialize()` to `main.dart`
- [ ] Run `flutter run`
- [ ] Copy VM Service URI
- [ ] Start server with URI
- [ ] Verify in Claude (if using AI)

### Full Setup (20 minutes)

- [ ] Complete Quick Setup
- [ ] Read [SETUP.md](./SETUP.md) fully
- [ ] Review [TOOLS.md](../TOOLS.md) categories
- [ ] Read [BEST_PRACTICES.md](./BEST_PRACTICES.md)
- [ ] Try a tool manually (e.g., `capture_screenshot`)

### Advanced Setup (1 hour)

- [ ] Complete Full Setup
- [ ] Set up Claude integration ([AI_AGENTS.md](./AI_AGENTS.md))
- [ ] Read [ARCHITECTURE.md](./ARCHITECTURE.md)
- [ ] Review plugin setup ([PLUGINS.md](./PLUGINS.md))
- [ ] Read [CONTRIBUTING.md](../CONTRIBUTING.md)

---

## 📧 Getting Help

### Where to Look

1. **Can't get it working?** → [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
2. **Need to know how to use a tool?** → [TOOLS.md](../TOOLS.md)
3. **Want to do something specific?** → Search this INDEX page
4. **Found a bug?** → [GitHub Issues](https://github.com/abugeek/FlutterPilot/issues)
5. **Have a feature request?** → [GitHub Issues](https://github.com/abugeek/FlutterPilot/issues)

### Common Questions

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md#faq) for:
- Will FlutterPilot slow my app?
- Does it work with iOS/Android/Web/macOS/Windows?
- How do I use it in production?
- Can I use it with [my state manager]?
- Why isn't [tool] working?

---

## 📚 Documentation Statistics

**Total Documentation:** ~80 KB across 7 documents

| Document | Size | Audience |
|----------|------|----------|
| README.md | 8 KB | Everyone |
| SETUP.md | 9 KB | New users |
| TOOLS.md | 35 KB | All users |
| TROUBLESHOOTING.md | 19 KB | Users with issues |
| AI_AGENTS.md | 14 KB | AI integration users |
| PLUGINS.md | 14 KB | Plugin developers |
| ARCHITECTURE.md | 13 KB | Contributors |
| BEST_PRACTICES.md | 13 KB | Power users |

---

## 🔄 Documentation Updates

Documentation is kept up-to-date with each release:
- [TOOLS.md](../TOOLS.md) — Updated when tools change
- [SETUP.md](./SETUP.md) — Updated for new platforms
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) — Updated for new issues
- [ARCHITECTURE.md](./ARCHITECTURE.md) — Updated for major refactors

See [CHANGELOG.md](../CHANGELOG.md) for release notes.

---

## 💡 Tips for Finding Things

### Search the docs:
```bash
# Find all mentions of "mock"
grep -r "mock" docs/

# Find tool names
grep -r "^### `" TOOLS.md

# Find setup instructions for a platform
grep -i "android\|ios\|web" SETUP.md
```

### Use GitHub's search:
Visit the [repo](https://github.com/abugeek/FlutterPilot) and search docs

### Ask Claude:
Paste a doc into Claude and ask questions about it

---

## Getting Started Guide

Below is a condensed getting-started that combines key points from other docs.

### Step 1: Install (5 min)

```bash
# Create or navigate to your Flutter project
cd your_flutter_app

# Add SDK
flutter pub add --dev flutterpilot_sdk
```

### Step 2: Initialize (2 min)

Edit `lib/main.dart`:

```dart
import 'package:flutterpilot_sdk/flutterpilot_sdk.dart';

void main() {
  FlutterPilot.initialize();  // Add this line
  runApp(const MyApp());
}
```

### Step 3: Run App (2 min)

```bash
flutter run
```

Copy the VM Service URI from console output (looks like `http://127.0.0.1:54321/xxxxx=`)

### Step 4: Start Server (1 min)

```bash
dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
  --uri "http://127.0.0.1:54321/xxxxx="
```

Replace the URI with the one you copied.

### Step 5: Test It (2 min)

If using Claude:
- Set up [AI_AGENTS.md](./AI_AGENTS.md)
- Ask Claude: "What's the current screen showing?"
- Claude will call tools to analyze

If using manually:
- Check server output for "ready to serve tools"
- Try calling a tool (e.g., `get_app_summary`)

---

**You're now ready to use FlutterPilot!**

Next steps:
- Read [TOOLS.md](../TOOLS.md) to see what tools you have
- Read [BEST_PRACTICES.md](./BEST_PRACTICES.md) for patterns
- For AI integration, read [AI_AGENTS.md](./AI_AGENTS.md)

---

## Document License

All documentation is MIT licensed, same as the code.

Last updated: 2024-01-09
