import * as cp from 'child_process';
import * as readline from 'readline';
import * as path from 'path';

export class McpClient {
    private process?: cp.ChildProcess;
    private rl?: readline.Interface;
    private nextId = 1;
    private pendingRequests = new Map<number, { resolve: (res: any) => void, reject: (err: any) => void }>();

    constructor(private extensionPath: string) {}

    async start(uri: string): Promise<void> {
        if (this.process) {
            this.stop();
        }

        const serverPath = path.join(this.extensionPath, '..', 'flutterpilot_server', 'bin', 'flutterpilot_server.dart');
        
        // Spawn server process
        this.process = cp.spawn('dart', ['run', serverPath, '--uri', uri]);

        this.rl = readline.createInterface({
            input: this.process.stdout!,
            terminal: false
        });

        this.rl.on('line', (line) => {
            try {
                const response = JSON.parse(line);
                if (response.id && this.pendingRequests.has(response.id)) {
                    const { resolve, reject } = this.pendingRequests.get(response.id)!;
                    this.pendingRequests.delete(response.id);
                    if (response.error) {
                        reject(response.error);
                    } else {
                        resolve(response.result);
                    }
                }
            } catch (e) {
                // Not a valid JSON-RPC response, might be a log message
                console.log(`[Pilot Server Log]: ${line}`);
            }
        });

        this.process.stderr?.on('data', (data) => {
            console.error(`[Pilot Server Error]: ${data}`);
        });

        this.process.on('close', (code) => {
            console.log(`Pilot Server exited with code ${code}`);
            this.process = undefined;
            // Reject all pending requests when the server exits
            for (const [id, { reject }] of this.pendingRequests) {
                reject(new Error(`Server exited with code ${code}`));
            }
            this.pendingRequests.clear();
        });

        // Wait a bit for the server to initialize
        await new Promise(resolve => setTimeout(resolve, 2000));
    }

    stop() {
        if (this.process) {
            this.process.kill();
            this.process = undefined;
        }
        this.rl?.close();
    }

    async callTool(name: string, args: any = {}): Promise<any> {
        if (!this.process) {
            throw new Error('Server not running');
        }

        const id = this.nextId++;
        const request = {
            jsonrpc: '2.0',
            id,
            method: 'tools/call',
            params: {
                name,
                arguments: args
            }
        };

        const TIMEOUT_MS = 30_000;
        return new Promise((resolve, reject) => {
            const timer = setTimeout(() => {
                this.pendingRequests.delete(id);
                reject(new Error(`Tool call '${name}' timed out after ${TIMEOUT_MS / 1000}s`));
            }, TIMEOUT_MS);

            this.pendingRequests.set(id, {
                resolve: (res: any) => { clearTimeout(timer); resolve(res); },
                reject: (err: any) => { clearTimeout(timer); reject(err); }
            });
            this.process!.stdin!.write(JSON.stringify(request) + '\n');
        });
    }

    isConnected(): boolean {
        return !!this.process;
    }
}
