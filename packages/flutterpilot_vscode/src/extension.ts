import * as vscode from 'vscode';
import { McpClient } from './mcp_client';
import { DashboardProvider } from './dashboard_provider';
import { StatusBarManager } from './status_bar';

let mcpClient: McpClient;
let statusBar: StatusBarManager;

export function activate(context: vscode.ExtensionContext) {
    console.log('FlutterPilot extension is now active!');

    mcpClient = new McpClient(context.extensionPath);
    statusBar = new StatusBarManager();

    const dashboardProvider = new DashboardProvider(context, mcpClient);
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider('flutterpilot.dashboard', dashboardProvider)
    );

    // Command to manually start the server
    let startServerCmd = vscode.commands.registerCommand('flutterpilot.startServer', async (uri?: string) => {
        if (!uri) {
            uri = await vscode.window.showInputBox({
                prompt: 'Enter the VM Service URI (ws://...)',
                placeHolder: 'ws://127.0.0.1:...'
            });
        }

        if (uri) {
            try {
                await mcpClient.start(uri);
                statusBar.update(true);
                vscode.window.showInformationMessage(`FlutterPilot Connected to: ${uri}`);
                dashboardProvider.updateState();
            } catch (e) {
                vscode.window.showErrorMessage(`Failed to start FlutterPilot: ${e}`);
            }
        }
    });

    let captureScreenshotCmd = vscode.commands.registerCommand('flutterpilot.captureScreenshot', async () => {
        if (!mcpClient.isConnected()) {
            vscode.window.showErrorMessage('FlutterPilot is not connected.');
            return;
        }
        try {
            const result = await mcpClient.callTool('capture_screenshot');
            // MCP result format: result.content[0].data (base64)
            const base64Data = result.content[0].data;
            const buffer = Buffer.from(base64Data, 'base64');
            
            const workspaceFolders = vscode.workspace.workspaceFolders;
            if (workspaceFolders) {
                const filePath = vscode.Uri.joinPath(workspaceFolders[0].uri, 'flutterpilot_screenshot.png');
                await vscode.workspace.fs.writeFile(filePath, buffer);
                vscode.window.showInformationMessage('Screenshot saved to workspace.');
                vscode.commands.executeCommand('vscode.open', filePath);
            }
        } catch (e) {
            vscode.window.showErrorMessage(`Screenshot failed: ${e}`);
        }
    });

    let openDashboardCmd = vscode.commands.registerCommand('flutterpilot.openDashboard', () => {
        vscode.commands.executeCommand('workbench.view.extension.flutterpilot-explorer');
    });

    // Automatically detect debug sessions
    vscode.debug.onDidStartDebugSession(async (session) => {
        if (session.type === 'dart') {
            const vmUri = (session.configuration as any).vmServiceUri;
            if (vmUri) {
                vscode.commands.executeCommand('flutterpilot.startServer', vmUri);
            }
        }
    });

    context.subscriptions.push(startServerCmd, captureScreenshotCmd, openDashboardCmd, statusBar);
}

export function deactivate() {
    mcpClient?.stop();
    statusBar?.dispose();
}
