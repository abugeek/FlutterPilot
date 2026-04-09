# FlutterPilot AI Agent Guide

How to use FlutterPilot with Claude, ChatGPT, Cursor, and other AI coding assistants.

## Table of Contents
- [Overview](#overview)
- [Claude (Recommended)](#claude-recommended)
- [ChatGPT / Custom GPTs](#chatgpt--custom-gpts)
- [Cursor AI](#cursor-ai)
- [Prompt Templates](#prompt-templates)
- [Best Practices](#best-practices)
- [Advanced Workflows](#advanced-workflows)

---

## Overview

FlutterPilot exposes all app state and UI through **83 MCP tools**. AI agents can:

✅ **Understand** the current UI and state  
✅ **Inspect** widgets, navigation, and state managers  
✅ **Automate** taps, text input, navigation  
✅ **Debug** errors and unexpected behavior  
✅ **Test** by driving the app programmatically  
✅ **Mock** HTTP endpoints and network conditions  

### Data Flow

```
┌─────────────────────┐
│ AI Agent (Claude)   │
├─────────────────────┤
│ Uses MCP Tools:     │
│ • get_widget_tree   │
│ • tap_widget        │
│ • get_app_summary   │
└──────────┬──────────┘
           │ MCP Protocol (stdio)
           ↓
┌─────────────────────────────────┐
│ FlutterPilot Server             │
├─────────────────────────────────┤
│ Tool execution + validation     │
└──────────┬──────────────────────┘
           │ VM Service (WebSocket)
           ↓
┌─────────────────────────────────┐
│ Flutter App (running)           │
├─────────────────────────────────┤
│ Renders UI + state              │
└─────────────────────────────────┘
```

---

## Claude (Recommended)

Claude is the best choice for FlutterPilot because:
- Supports MCP (Model Context Protocol) natively
- Large context window (200K tokens) for analyzing code
- Excellent reasoning for UI/state problems
- Can handle complex multi-step workflows

### Setup: Claude with FlutterPilot

#### Step 1: Install Claude Desktop

Download from https://claude.ai/download

Or use Claude Web (https://claude.ai) — web doesn't support MCP yet, so desktop is required.

#### Step 2: Create MCP Configuration

Create `~/.claude/mcp_config.json`:

```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": [
        "run",
        "packages/flutterpilot_server/bin/flutterpilot_server.dart",
        "--uri",
        "http://127.0.0.1:54321/XXXXX="
      ],
      "cwd": "/path/to/your/flutter/project"
    }
  }
}
```

**Replace**:
- `/path/to/your/flutter/project` — Your Flutter app root
- `http://127.0.0.1:54321/XXXXX=` — Your app's VM Service URI (copy from `flutter run` output)

#### Step 3: Restart Claude

Close and reopen Claude Desktop. In a new conversation, you should see:

```
MCP Server: flutterpilot
Status: Connected ✓
Available Tools: 83
```

#### Step 4: Use FlutterPilot

Ask Claude questions about your app:

```
User: "What's the current screen showing?"

Claude will:
1. Call get_app_summary → learn current route
2. Call capture_screenshot → see visual
3. Call get_widget_tree → analyze structure
4. Respond with detailed description
```

---

## ChatGPT / Custom GPTs

ChatGPT doesn't have native MCP support yet. Options:

### Option A: Manual API Calls (Not Recommended)

Call FlutterPilot server HTTP endpoints directly. Complex and error-prone.

### Option B: Wait for MCP in ChatGPT

OpenAI is adding MCP support. Check https://platform.openai.com/docs/guides/mcp for updates.

### Option C: Use Claude Instead

For now, Claude is the best choice.

---

## Cursor AI

Cursor supports MCP (when running locally with your editor).

### Setup: Cursor with FlutterPilot

#### Step 1: Configure Cursor Settings

In Cursor → Settings → Features → MCP:

```json
{
  "mcpServers": {
    "flutterpilot": {
      "command": "dart",
      "args": [
        "run",
        "packages/flutterpilot_server/bin/flutterpilot_server.dart",
        "--uri",
        "http://127.0.0.1:54321/XXXXX="
      ]
    }
  }
}
```

#### Step 2: Use in Cursor

In Cursor Chat, you can now ask:

```
"@flutterpilot what widgets are on screen?"
```

Cursor will use FlutterPilot tools to answer.

---

## Prompt Templates

Ready-to-use prompts for common tasks.

### Template 1: Visual Debugging

```
The user reported the login button is misaligned on their device.

1. Capture a screenshot of the current screen
2. Analyze the widget tree to find the button
3. Report the button's exact properties (size, position, colors)
4. Suggest a fix if the alignment is wrong
```

### Template 2: State Inspection

```
The app seems to be in an unexpected state. 

1. Get the app summary (current route, state)
2. Inspect all available state managers (Bloc, Riverpod, etc.)
3. Analyze if the state matches the UI
4. Identify any state corruption or race conditions
```

### Template 3: User Interaction Flow

```
Automate the following user flow:

1. Navigate to the Settings page
2. Change the theme to Dark
3. Verify the theme changed by taking a screenshot
4. Report any errors encountered

Use tap_widget, navigate_to, and capture_screenshot as needed.
```

### Template 4: Network Mocking for Testing

```
Set up test conditions for the login flow:

1. Mock the /auth/login endpoint to fail with 401 Unauthorized
2. Have the user tap the login button
3. Verify the error message appears
4. Clear the mock and retry with valid credentials
5. Verify successful login
```

### Template 5: State Manager Debugging

```
I'm debugging a Bloc state issue:

1. Get all Bloc states with get_bloc_state
2. Trigger the action that causes the problem (tap a button)
3. Inspect the state again to see what changed
4. Analyze the state transitions and identify the bug
```

---

## Best Practices

### 1. Always Start with Context

Before asking Claude to debug or automate, provide context:

```
Bad: "Why is the button not working?"

Good: "I have a Flutter app with a login screen. The submit button 
should validate the form and call an API, but it seems unresponsive. 
Can you investigate?"
```

Then let Claude call tools to understand the app.

### 2. Break Complex Tasks into Steps

```
Bad (too complex for one request):
"Automate a full user onboarding flow with email signup, 
verification, profile creation, and settings."

Good (break into steps):
1. "Set up the initial screen and verify the email field"
2. "Enter a test email and tap submit"
3. "Verify the verification screen appears"
4. (etc. for each step)
```

### 3. Use get_capabilities First

Always ask Claude to check what plugins are available:

```
Claude: "Let me check what capabilities your app has loaded."
[Claude calls get_capabilities]
Claude: "I see Bloc and Dio plugins are loaded. I can inspect 
Bloc states and mock HTTP requests."
```

### 4. Provide Clear Instructions for Complex Workflows

```
"I want to test error handling in the checkout flow:

1. First, mock the payment API to return 500 error
2. Have a user go through checkout (navigate → fill form → submit)
3. Verify an error message appears
4. Clear the mock
5. Retry with a successful response
6. Verify checkout completes

Can you automate this?"
```

### 5. Ask Claude to Explain What It's Doing

```
User: "Debug why the counter isn't updating after I tap the button"

Claude: "I'll investigate by:
1. Capturing a screenshot to see the current state
2. Getting the widget tree to find the counter and button
3. Inspecting the Bloc state to verify the count
4. Tapping the button and re-inspecting state

Let me start..."
```

### 6. Take Screenshots After Major Changes

If Claude makes changes, ask for verification:

```
Claude: "I've updated the button styling."

You: "Can you take a screenshot to show me the result?"

Claude: [captures screenshot]
Claude: "Here's the updated button..."
```

---

## Advanced Workflows

### Workflow 1: Automated UI Testing

```
Claude, run this test suite:

TEST 1: Login with valid credentials
- Navigate to login screen
- Enter valid email and password
- Tap submit button
- Verify navigation to home screen
- Take screenshot

TEST 2: Login with invalid password
- Navigate to login screen
- Mock /auth/login to return 401
- Enter email and wrong password
- Tap submit button
- Verify error message appears
- Take screenshot

TEST 3: Network error during login
- Navigate to login screen
- Simulate slow network (>5s timeout)
- Tap submit button
- Verify timeout error message
- Take screenshot
```

### Workflow 2: Regression Testing

```
I need to verify my app still works after code changes.

Test these critical paths:

1. App startup → home screen loads
2. Navigation → all routes reachable without errors
3. Form submission → validation works
4. Network requests → mocked endpoints return expected data
5. State persistence → state survives navigation

Run the tests and report any failures.
```

### Workflow 3: Accessibility Auditing

```
Audit the app for accessibility issues:

1. Capture screenshot and inspect all interactive widgets
2. Verify all buttons have semantic labels (readable by screen readers)
3. Check text contrast (light/dark mode)
4. Verify focus order makes sense
5. Check if any widgets lack key information for accessibility

Report issues and suggest fixes.
```

### Workflow 4: Performance Investigation

```
The app feels sluggish. Help me debug:

1. Get the current widget tree and analyze depth/complexity
2. Check if any heavy operations are running on main thread
3. Inspect state manager (Bloc/Riverpod) for excessive rebuilds
4. Check network logs for unnecessary requests
5. Analyze console for warnings/errors

Suggest optimizations.
```

### Workflow 5: AI-Driven Test Case Generation

```
I have a feature:
[Describe feature]

Generate test cases by:
1. Exploring the UI (screenshots, widget tree)
2. Identifying all interactive elements
3. Creating tests for each interaction path
4. Running tests by automating user actions
5. Reporting failures

Create a comprehensive test suite.
```

---

## Tool Categories for Reference

When talking to Claude, you can reference tool categories:

### Screenshots & Layout (5 tools)
- `capture_screenshot` — Get visual
- `get_widget_tree` — Widget hierarchy
- `get_widget_properties` — Specific widget details
- `get_semantics_tree` — Accessibility tree
- `compare_screenshots` — Visual regression

### UI Automation (15 tools)
- `tap_widget` — Simulate tap
- `enter_text` — Type in text fields
- `scroll` — Scroll widgets
- `drag` — Drag and drop
- `longpress` — Long press gesture
- (+ more interaction tools)

### State Inspection (19 tools)
- `get_bloc_state` — Bloc state
- `get_riverpod_state` — Riverpod state
- `get_app_summary` — Current route, errors
- (+ state manager plugins)

### Navigation (8 tools)
- `navigate_to` — Jump to route
- `get_navigation_stack` — View route history
- `pop_route` — Go back

### Network (3 tools via Dio plugin)
- `add_http_mock` — Mock endpoint
- `simulate_network` — Slow/offline
- `get_network_logs` — Request history

### Capabilities (1 tool)
- `get_capabilities` — Loaded plugins status

See [TOOLS.md](../TOOLS.md) for complete reference.

---

## Example: Full Debugging Session

```
User: "My login is broken. The button doesn't work."

Claude: "I'll help! Let me start by understanding your app."

[Claude calls get_app_summary]
Claude: "Your app is on the LoginScreen route. Let me see the UI."

[Claude calls capture_screenshot]
Claude: "I can see a login form with email, password, and submit button. 
Let me inspect the widget tree to find the button."

[Claude calls get_widget_tree]
Claude: "Found the button. It has key 'submitBtn'. Let me check what 
happens when I tap it."

[Claude calls tap_widget with key: 'submitBtn']
Claude: "The button was tapped. Let me check the state and navigation."

[Claude calls get_app_summary]
Claude: "The route is still LoginScreen (navigation didn't happen). 
Let me check if there's an error in Bloc state."

[Claude calls get_bloc_state]
Claude: "I found the issue! The LoginBloc state shows an error: 
'Email validation failed'. The email field has invalid format.

Let me clear it and enter a valid email."

[Claude calls enter_text with selector: 'emailField', text: 'test@example.com']
[Claude calls tap_widget with key: 'submitBtn']
[Claude calls capture_screenshot]

Claude: "Success! You're now on the HomeScreen. The issue was email 
validation. Make sure to validate email format before submitting."
```

---

## Troubleshooting MCP Connection

### Claude can't connect to FlutterPilot

1. **Verify server is running**:
   ```bash
   dart run packages/flutterpilot_server/bin/flutterpilot_server.dart \
     --uri "http://127.0.0.1:54321/XXXXX="
   ```

2. **Check mcp_config.json path**:
   - macOS/Linux: `~/.claude/mcp_config.json`
   - Windows: `%APPDATA%\Claude\mcp_config.json`

3. **Verify URI is current**:
   - VM Service URIs expire. Get a fresh one from `flutter run`
   - Update mcp_config.json with new URI

4. **Restart Claude**:
   - Close entirely and reopen (not just new chat)

### Tools not appearing in Claude

1. **Check server is fully started**:
   - Should see: "FlutterPilot Server started"
   - Wait 2-3 seconds after

2. **Verify MCP config is valid JSON**:
   ```bash
   cat ~/.claude/mcp_config.json | jq  # Test JSON validity
   ```

3. **Check server output for errors**:
   - Run server in terminal, watch for warnings

---

## Next Steps

1. **Set up Claude**: Follow [Claude Setup](#claude-recommended) above
2. **Try a simple task**: Ask "What's the current screen?"
3. **Move to automation**: Ask Claude to tap a button
4. **Advanced workflows**: Use templates for complex testing

For more tool details, see [TOOLS.md](../TOOLS.md).
