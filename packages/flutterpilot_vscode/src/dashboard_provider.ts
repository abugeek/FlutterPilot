import * as vscode from 'vscode';
import { McpClient } from './mcp_client';

export class DashboardProvider implements vscode.WebviewViewProvider {
    private view?: vscode.WebviewView;
    private refreshInterval?: ReturnType<typeof setInterval>;

    constructor(
        private readonly context: vscode.ExtensionContext,
        private readonly mcpClient: McpClient
    ) {}

    resolveWebviewView(
        webviewView: vscode.WebviewView,
        _context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken
    ) {
        this.view = webviewView;

        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [this.context.extensionUri]
        };

        webviewView.webview.html = this._getHtmlForWebview();

        webviewView.webview.onDidReceiveMessage(async (data) => {
            switch (data.type) {
                case 'callTool':
                    try {
                        const result = await this.mcpClient.callTool(data.tool, data.args);
                        webviewView.webview.postMessage({ type: 'toolResult', tool: data.tool, result });
                    } catch (e) {
                        vscode.window.showErrorMessage(`Tool Error: ${e}`);
                    }
                    break;
                case 'refresh':
                    this.updateState();
                    break;
            }
        });

        // Start periodic sync and clean up on disposal
        this.refreshInterval = setInterval(() => this.updateState(), 5000);
        webviewView.onDidDispose(() => {
            if (this.refreshInterval) {
                clearInterval(this.refreshInterval);
                this.refreshInterval = undefined;
            }
        });
    }

    async updateState() {
        if (!this.view || !this.mcpClient.isConnected()) {
            return;
        }

        try {
            const summary = await this.mcpClient.callTool('get_app_summary');
            const stability = await this.mcpClient.callTool('get_self_heal_status');
            const riverpod = await this.mcpClient.callTool('get_riverpod_state');
            const bloc = await this.mcpClient.callTool('get_bloc_state');

            this.view.webview.postMessage({
                type: 'update',
                data: {
                    summary,
                    stability,
                    riverpod,
                    bloc
                }
            });
        } catch (e) {
            console.error('Failed to sync dashboard state', e);
        }
    }

    private _getHtmlForWebview() {
        return `
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <style>
                    body { font-family: var(--vscode-font-family); color: var(--vscode-foreground); padding: 10px; }
                    .card { background: var(--vscode-editor-background); border: 1px solid var(--vscode-widget-border); border-radius: 4px; padding: 10px; margin-bottom: 10px; }
                    .status-stable { color: #4caf50; font-weight: bold; }
                    .status-unstable { color: #f44336; font-weight: bold; }
                    button { background: var(--vscode-button-background); color: var(--vscode-button-foreground); border: none; padding: 5px 10px; border-radius: 2px; cursor: pointer; margin-right: 5px; }
                    button:hover { background: var(--vscode-button-hoverBackground); }
                    .state-list { font-size: 0.9em; margin-top: 10px; }
                    .state-item { border-bottom: 1px solid var(--vscode-widget-border); padding: 5px 0; display: flex; justify-content: space-between; align-items: center; }
                    .state-name { font-family: monospace; color: var(--vscode-symbolIcon-propertyForeground); }
                    .state-value { color: var(--vscode-descriptionForeground); max-width: 150px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
                    h3 { margin-top: 0; font-size: 1.1em; border-bottom: 1px solid var(--vscode-widget-border); padding-bottom: 5px; }
                </style>
            </head>
            <body>
                <h3>🚀 FlutterPilot Dashboard</h3>
                
                <div class="card" id="status-card">
                    <div>Status: <span id="conn-status">Disconnected</span></div>
                    <div id="stability-status" class="status-stable"></div>
                    <div style="margin-top: 10px;">
                        <button onclick="sendAction('hot_reload')">Reload</button>
                        <button onclick="sendAction('hot_restart')">Restart</button>
                        <button onclick="sendAction('capture_screenshot')">📷</button>
                    </div>
                </div>

                <div class="card">
                    <h3>🌊 Riverpod States</h3>
                    <div id="riverpod-list" class="state-list">Loading...</div>
                </div>

                <div class="card">
                    <h3>🧱 Bloc States</h3>
                    <div id="bloc-list" class="state-list">Loading...</div>
                </div>

                <script>
                    const vscode = acquireVsCodeApi();

                    function sendAction(tool, args = {}) {
                        vscode.postMessage({ type: 'callTool', tool, args });
                    }

                    function injectState(type, name) {
                        const val = prompt('Enter new JSON value for ' + name);
                        if (val) {
                            try {
                                const parsed = JSON.parse(val);
                                sendAction(type === 'riverpod' ? 'set_riverpod_state' : 'set_bloc_state', {
                                    name: name,
                                    [type === 'riverpod' ? 'value' : 'state']: parsed
                                });
                            } catch(e) { alert('Invalid JSON'); }
                        }
                    }

                    window.addEventListener('message', event => {
                        const message = event.data;
                        if (message.type === 'update') {
                            const { summary, stability, riverpod, bloc } = message.data;
                            
                            const stabilityText = stability?.content?.[0]?.text ?? 'Unknown';
                            document.getElementById('conn-status').innerText = 'Connected';
                            document.getElementById('stability-status').innerText = stabilityText;
                            document.getElementById('stability-status').className = stabilityText.includes('UNSTABLE') ? 'status-unstable' : 'status-stable';

                            const riverpodText = riverpod?.content?.[0]?.text ?? 'No data';
                            const blocText = bloc?.content?.[0]?.text ?? 'No data';
                            renderList('riverpod-list', riverpodText, 'riverpod');
                            renderList('bloc-list', blocText, 'bloc');
                        }
                    });

                    function escapeHtml(str) {
                        const div = document.createElement('div');
                        div.textContent = str;
                        return div.innerHTML;
                    }

                    function renderList(id, text, type) {
                        const container = document.getElementById(id);
                        if (text.includes('No observed')) {
                            container.textContent = text;
                            return;
                        }
                        
                        const lines = text.split('\\n');
                        container.innerHTML = '';
                        lines.forEach(line => {
                            if (!line.trim()) return;
                            const parts = line.split(':');
                            const name = parts[0].trim();
                            const val = parts.slice(1).join(':').trim();
                            
                            const div = document.createElement('div');
                            div.className = 'state-item';

                            const nameSpan = document.createElement('span');
                            nameSpan.className = 'state-name';
                            nameSpan.textContent = name;

                            const valSpan = document.createElement('span');
                            valSpan.className = 'state-value';
                            valSpan.title = val;
                            valSpan.textContent = val;

                            const btn = document.createElement('button');
                            btn.textContent = '✎';
                            btn.addEventListener('click', () => injectState(type, name));

                            div.appendChild(nameSpan);
                            div.appendChild(valSpan);
                            div.appendChild(btn);
                            container.appendChild(div);
                        });
                    }
                </script>
            </body>
            </html>
        `;
    }
}
