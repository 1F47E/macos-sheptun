const https = require('https');
const WebSocket = require('ws');

/**
 * Validates an OpenAI API key by making a request to the models endpoint
 * @param {string} apiKey - The OpenAI API key to validate
 * @returns {Promise<boolean>} - Whether the API key is valid
 */
function validateApiKey(apiKey) {
  console.log('Validating OpenAI API key...');
  return new Promise((resolve) => {
    const options = {
      hostname: 'api.openai.com',
      path: '/v1/models',
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${apiKey}`
      }
    };

    console.log('Sending request to OpenAI models endpoint...');
    const req = https.request(options, (res) => {
      if (res.statusCode === 200) {
        console.log('✓ API key is valid');
        resolve(true);
      } else {
        console.error(`✗ API key validation failed with status code: ${res.statusCode}`);
        resolve(false);
      }
    });

    req.on('error', (error) => {
      console.error('✗ Error validating API key:', error.message);
      resolve(false);
    });

    req.end();
  });
}

/**
 * Creates a transcription session with OpenAI
 * @param {string} apiKey - The OpenAI API key
 * @param {string} language - The language code for transcription (default: 'en')
 * @returns {Promise<Object>} - The session info with sessionId and clientSecret
 */
async function createTranscriptionSession(apiKey, language = 'en') {
  console.log(`Creating transcription session with language: ${language}`);
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({
      input_audio_format: 'pcm16',
      input_audio_transcription: {
        model: 'gpt-4o-transcribe',
        language: language,
        prompt: ''
      },
      turn_detection: {
        type: 'server_vad',
        threshold: 0.5,
        prefix_padding_ms: 300,
        silence_duration_ms: 500
      },
      input_audio_noise_reduction: {
        type: 'near_field'
      },
      include: [
        'item.input_audio_transcription.logprobs'
      ]
    });

    console.log('Request payload:', data);
    const options = {
      hostname: 'api.openai.com',
      path: '/v1/realtime/transcription_sessions',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
        'Content-Length': Buffer.byteLength(data)
      }
    };

    console.log('Sending session creation request to OpenAI...');
    const req = https.request(options, (res) => {
      let responseData = '';

      res.on('data', (chunk) => {
        responseData += chunk;
      });

      res.on('end', () => {
        console.log(`Session creation response status: ${res.statusCode}`);
        if (res.statusCode === 200) {
          try {
            const session = JSON.parse(responseData);
            console.log(`Session created successfully with ID: ${session.id}`);
            resolve({
              sessionId: session.id,
              clientSecret: session.client_secret.value
            });
          } catch (error) {
            console.error('Failed to parse session response:', error);
            reject(new Error(`Failed to parse session response: ${error.message}`));
          }
        } else {
          console.error(`Failed to create session: ${res.statusCode}`, responseData);
          reject(new Error(`Failed to create session: ${res.statusCode} ${responseData}`));
        }
      });
    });

    req.on('error', (error) => {
      console.error('Error sending session creation request:', error);
      reject(new Error(`Request error: ${error.message}`));
    });

    req.write(data);
    req.end();
  });
}

/**
 * Create a WebSocket connection to OpenAI's real-time API
 * @param {string} clientSecret - The client secret for the session
 * @param {WebSocket} clientWs - The client WebSocket to proxy to/from
 * @returns {WebSocket} - The OpenAI WebSocket connection
 */
function createOpenAIWebSocketConnection(clientSecret, clientWs) {
  console.log('Creating WebSocket connection to OpenAI...');
  
  // Fix: Use proper WebSocket initialization with correct protocols
  const openaiWs = new WebSocket(
    'wss://api.openai.com/v1/realtime?intent=transcription',
    {
      headers: {
        'Authorization': `Bearer ${clientSecret}`
      },
      protocol: 'openai-beta.realtime-v1'
    }
  );
  
  console.log('WebSocket connection initialized with protocols:', openaiWs.protocol);
  
  // Set up event handlers for the OpenAI WebSocket
  openaiWs.on('open', () => {
    console.log('WebSocket connection to OpenAI opened');
  });
  
  openaiWs.on('error', (error) => {
    console.error(`OpenAI WebSocket error:`, error);
    if (clientWs.readyState === WebSocket.OPEN) {
      clientWs.send(JSON.stringify({
        type: 'error',
        event_id: 'server_error',
        error: {
          type: 'server_error',
          message: `Server proxy error: ${error.message}`
        }
      }));
    }
  });
  
  openaiWs.on('close', (code, reason) => {
    console.log(`OpenAI WebSocket closed: ${code} ${reason}`);
  });
  
  return openaiWs;
}

module.exports = {
  validateApiKey,
  createTranscriptionSession,
  createOpenAIWebSocketConnection
}; 