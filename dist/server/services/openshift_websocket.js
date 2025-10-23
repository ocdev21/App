import { spawn } from 'child_process';
export class OpenShiftWebSocketHandler {
    wsClients = new Set();
    handleConnection(ws) {
        this.wsClients.add(ws);
        ws.on('message', async (message) => {
            try {
                const data = JSON.parse(message);
                if (data.type === 'analyze') {
                    await this.handleAnalysisRequest(ws, data);
                }
            }
            catch (error) {
                ws.send(JSON.stringify({
                    type: 'error',
                    content: `Message parsing error: ${error}`,
                    timestamp: new Date().toISOString()
                }));
            }
        });
        ws.on('close', () => {
            this.wsClients.delete(ws);
        });
    }
    async handleAnalysisRequest(ws, data) {
        const remoteHost = process.env.TSLAM_REMOTE_HOST || '10.193.0.4';
        const pythonProcess = spawn('python3', [
            'server/services/remote_tslam_client.py',
            '--host', remoteHost,
            '--prompt', JSON.stringify(data.prompt)
        ]);
        pythonProcess.stdout.on('data', (data) => {
            try {
                const response = JSON.parse(data.toString());
                ws.send(JSON.stringify({
                    type: 'ai_response',
                    content: response.content,
                    timestamp: new Date().toISOString()
                }));
            }
            catch (error) {
                console.error('Python process output parsing error:', error);
            }
        });
        pythonProcess.stderr.on('data', (data) => {
            console.error('TSLAM Error:', data.toString());
            ws.send(JSON.stringify({
                type: 'error',
                content: `TSLAM processing error: ${data.toString()}`,
                timestamp: new Date().toISOString()
            }));
        });
    }
}
//# sourceMappingURL=openshift_websocket.js.map