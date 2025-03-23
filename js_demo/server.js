require('dotenv').config();
const http = require('http');
const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');
const url = require('url');
const openaiApi = require('./libs/openai');

const PORT = process.env.PORT || 3000;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

// Enable more detailed logging
const DEBUG = true;

// Helper function for logging with timestamps
function log(message, level = 'info') {
  const timestamp = new Date().toISOString();
  const prefix = level.toUpperCase() === 'ERROR' ? '[ERROR]' : '[INFO]';
  console.log(`[${timestamp}] ${prefix} ${message}`);
}

// Check if API key is set
if (!OPENAI_API_KEY) {
  log('OPENAI_API_KEY is not set in environment variables or .env file', 'error');
  log('Please set it and restart the server', 'error');
  process.exit(1);
}

// Validate API key on startup
log('Starting API key validation...');
openaiApi.validateApiKey(OPENAI_API_KEY)
  .then(isValid => {
    if (!isValid) {
      log('The provided OpenAI API key is invalid', 'error');
      log('Please check the key and restart the server', 'error');
      process.exit(1);
    }
    
    log('API key validated successfully');
    // Start server only if API key is valid
    startServer();
  })
  .catch(error => {
    log(`Error validating API key: ${error.message}`, 'error');
    log('Please check your internet connection and restart the server', 'error');
    process.exit(1);
  });

// Store active WebSocket connections
const activeConnections = new Map();

function startServer() {
  const MIME_TYPES = {
    '.html': 'text/html',
    '.css': 'text/css',
    '.js': 'text/javascript',
    '.json': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
  };

  const server = http.createServer((req, res) => {
    log(`${req.method} ${req.url}`);
    
    // Handle POST requests
    if (req.method === 'POST') {
      // New endpoint to create a transcription session
      if (req.url === '/api/transcription/create-session') {
        log('Received request to create transcription session');
        let body = '';
        
        req.on('data', (chunk) => {
          body += chunk.toString();
        });
        
        req.on('end', async () => {
          try {
            // Parse the request body
            log(`Request body: ${body}`);
            const requestData = JSON.parse(body);
            const language = requestData.language || 'en';
            
            log(`Creating transcription session with language: ${language}`);
            // Create a session with OpenAI
            const session = await openaiApi.createTranscriptionSession(OPENAI_API_KEY, language);
            
            // Generate a unique connection ID
            const connectionId = Math.random().toString(36).substring(2, 15);
            log(`Generated connection ID: ${connectionId}`);
            
            // Store the session info for when the WebSocket connects
            activeConnections.set(connectionId, {
              sessionId: session.sessionId,
              clientSecret: session.clientSecret,
              created: Date.now()
            });
            
            // Create WebSocket URL with connection ID
            const wsUrl = `ws://${req.headers.host}/ws/transcription/${connectionId}`;
            log(`WebSocket URL created: ${wsUrl}`);
            
            // Return session info and WebSocket URL to the client
            const responseData = {
              sessionId: session.sessionId,
              wsUrl: wsUrl
            };
            log(`Sending response: ${JSON.stringify(responseData)}`);
            
            res.writeHead(200, { 
              'Content-Type': 'application/json',
              'Access-Control-Allow-Origin': '*'
            });
            
            res.end(JSON.stringify(responseData));
          } catch (error) {
            log(`Error creating session: ${error.message}`, 'error');
            log(error.stack, 'error');
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: error.message }));
          }
        });
        
        return;
      }
    }
    
    // API endpoint to securely provide the OpenAI key to client (deprecated - kept for compatibility)
    if (req.url === '/api/config') {
      log('Received request for API config');
      res.writeHead(200, { 
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      });
      res.end(JSON.stringify({ 
        apiKey: OPENAI_API_KEY 
      }));
      return;
    }
    
    // Parse the URL
    let filepath = req.url;
    
    // Default to index.html for root path
    if (filepath === '/') {
      filepath = '/index.html';
    }
    
    // Get the full path
    const fullPath = path.join(__dirname, filepath);
    
    // Get the file extension
    const ext = path.extname(fullPath).toLowerCase();
    
    // Check if the file exists
    fs.access(fullPath, fs.constants.F_OK, (err) => {
      if (err) {
        log(`File not found: ${fullPath}`, 'error');
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('404 Not Found');
        return;
      }
      
      // Read and serve the file
      fs.readFile(fullPath, (err, data) => {
        if (err) {
          log(`Error reading file: ${err}`, 'error');
          res.writeHead(500, { 'Content-Type': 'text/plain' });
          res.end('500 Internal Server Error');
          return;
        }
        
        // Set MIME type
        const contentType = MIME_TYPES[ext] || 'application/octet-stream';
        
        // Set CORS headers for development
        res.writeHead(200, {
          'Content-Type': contentType,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type'
        });
        
        res.end(data);
      });
    });
  });

  // Setup WebSocket server
  const wss = new WebSocket.Server({ server });
  log('WebSocket server created');
  
  // Handle WebSocket connections
  wss.on('connection', (ws, req) => {
    const pathname = url.parse(req.url).pathname;
    log(`WebSocket connection received: ${pathname}`);
    
    // Handle transcription WebSocket connections
    if (pathname.startsWith('/ws/transcription/')) {
      const connectionId = pathname.split('/').pop();
      log(`WebSocket connection attempt for connection ID: ${connectionId}`);
      const connection = activeConnections.get(connectionId);
      
      if (!connection) {
        log(`Invalid connection ID: ${connectionId}`, 'error');
        ws.close(4000, 'Invalid connection ID');
        return;
      }
      
      log(`WebSocket connection established for session: ${connection.sessionId}`);
      
      // Create connection to OpenAI using our OpenAI API module
      const openaiWs = openaiApi.createOpenAIWebSocketConnection(connection.clientSecret, ws);
      
      // Handle messages from client and forward to OpenAI
      ws.on('message', (message) => {
        try {
          // Binary data handling - don't try to log or parse binary data
          if (typeof message === 'string') {
            log(`Received text message from client: ${message.substring(0, 100)}${message.length > 100 ? '...' : ''}`);
            // Only parse if it's a string and looks like JSON
            if (message.startsWith('{') || message.startsWith('[')) {
              try {
                const parsed = JSON.parse(message);
                log(`Parsed message: ${JSON.stringify(parsed).substring(0, 100)}${JSON.stringify(parsed).length > 100 ? '...' : ''}`);
              } catch (e) {
                log(`Error parsing message as JSON: ${e.message}`, 'error');
              }
            }
          } else {
            log(`Received binary message from client, size: ${message.length} bytes`);
          }
          
          if (openaiWs.readyState === WebSocket.OPEN) {
            openaiWs.send(message);
            log('Message forwarded to OpenAI');
          } else {
            log(`Cannot forward message, OpenAI WebSocket not open (state: ${openaiWs.readyState})`, 'error');
          }
        } catch (error) {
          log(`Error processing WebSocket message: ${error.message}`, 'error');
        }
      });
      
      // Handle messages from OpenAI and forward to client
      openaiWs.on('message', (message) => {
        try {
          if (typeof message === 'string') {
            log(`Received text message from OpenAI: ${message.substring(0, 100)}${message.length > 100 ? '...' : ''}`);
            // Only parse if it's a string and looks like JSON
            if (message.startsWith('{') || message.startsWith('[')) {
              try {
                const parsed = JSON.parse(message);
                log(`Parsed OpenAI message: ${JSON.stringify(parsed).substring(0, 100)}${JSON.stringify(parsed).length > 100 ? '...' : ''}`);
              } catch (e) {
                log(`Error parsing OpenAI message as JSON: ${e.message}`, 'error');
              }
            }
          } else {
            log(`Received binary message from OpenAI, size: ${message.length} bytes`);
          }
          
          if (ws.readyState === WebSocket.OPEN) {
            ws.send(message);
            log('Message forwarded to client');
          } else {
            log(`Cannot forward message, client WebSocket not open (state: ${ws.readyState})`, 'error');
          }
        } catch (error) {
          log(`Error processing OpenAI WebSocket message: ${error.message}`, 'error');
        }
      });
      
      // Handle OpenAI connection close
      openaiWs.on('close', (code, reason) => {
        log(`OpenAI WebSocket closed for session ${connection.sessionId}: ${code} ${reason}`);
        // Close client connection too if still open
        if (ws.readyState === WebSocket.OPEN) {
          ws.close(code, reason);
          log(`Closed client WebSocket due to OpenAI WebSocket closure`);
        }
      });
      
      // Handle client connection close
      ws.on('close', () => {
        log(`Client WebSocket closed for session ${connection.sessionId}`);
        // Close OpenAI connection too if still open
        if (openaiWs.readyState === WebSocket.OPEN) {
          openaiWs.close();
          log(`Closed OpenAI WebSocket due to client WebSocket closure`);
        }
        // Clean up connection
        activeConnections.delete(connectionId);
        log(`Removed connection ${connectionId} from active connections`);
      });
      
      // Handle client connection errors
      ws.on('error', (error) => {
        log(`Client WebSocket error for session ${connection.sessionId}: ${error.message}`, 'error');
        // Close OpenAI connection
        if (openaiWs.readyState === WebSocket.OPEN) {
          openaiWs.close();
          log(`Closed OpenAI WebSocket due to client WebSocket error`);
        }
        // Clean up connection
        activeConnections.delete(connectionId);
        log(`Removed connection ${connectionId} from active connections`);
      });
    }
  });
  
  // Clean up expired connections periodically (30 min ttl)
  setInterval(() => {
    const now = Date.now();
    const maxAge = 30 * 60 * 1000; // 30 minutes
    let count = 0;
    
    for (const [connectionId, connection] of activeConnections.entries()) {
      if (now - connection.created > maxAge) {
        log(`Removing expired connection: ${connectionId}, session: ${connection.sessionId}`);
        activeConnections.delete(connectionId);
        count++;
      }
    }
    
    if (count > 0) {
      log(`Cleaned up ${count} expired connections`);
    }
  }, 5 * 60 * 1000); // Check every 5 minutes

  server.listen(PORT, () => {
    log(`Server running at http://localhost:${PORT}/`);
    log(`WebSocket server running at ws://localhost:${PORT}/ws/`);
    log(`API Key from environment: Valid ✓`);
  });
} 