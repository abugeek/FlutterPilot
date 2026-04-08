import * as vscode from 'vscode';

export class StatusBarManager {
    private statusBarItem: vscode.StatusBarItem;

    constructor() {
        this.statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
        this.statusBarItem.command = 'flutterpilot.openDashboard';
        this.update(false, 'STABLE');
        this.statusBarItem.show();
    }

    update(connected: boolean, status: string = 'STABLE') {
        if (!connected) {
            this.statusBarItem.text = '$(circle-slash) Pilot: Off';
            this.statusBarItem.backgroundColor = undefined;
            this.statusBarItem.tooltip = 'FlutterPilot Server is disconnected';
        } else {
            if (status === 'UNSTABLE') {
                this.statusBarItem.text = '$(error) Pilot: CRASH';
                this.statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
                this.statusBarItem.tooltip = 'App has crashed! Self-Heal active.';
            } else {
                this.statusBarItem.text = '$(check) Pilot: Live';
                this.statusBarItem.backgroundColor = undefined;
                this.statusBarItem.tooltip = 'FlutterPilot is connected and app is stable';
            }
        }
    }

    dispose() {
        this.statusBarItem.dispose();
    }
}
