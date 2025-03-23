export default class OpenAIClient {
  /**
   * OpenAI Real-time Transcription API Client
   * 
   * This class implements the complete workflow for the OpenAI Real-time Transcription API:
   * 
   * 1. Start a transcription session via our server (initialize)
   * 2. Connect to a server-proxied WebSocket for the session (connectWebSocket)
   * 3. Stream audio data for real-time transcription (sendAudio)
   * 4. Process transcription results (handleWebSocketMessage)
   * 5. Close connection when done (disconnect)
   * 
   * @param {Function} onTranscriptionUpdate Callback for transcription updates
   * @param {Function} onStatusChange Callback for client status changes
   * @param {Function} onWebSocketStatusChange Callback for WebSocket status changes
   * @param {Function} onErrorMessage Callback for error messages
   */
  constructor(onTranscriptionUpdate, onStatusChange, onWebSocketStatusChange, onErrorMessage) {
    this.socket = null;
    this.sessionId = null;
    this.isConnected = false;
    this.onTranscriptionUpdate = onTranscriptionUpdate;
    this.onStatusChange = onStatusChange;
    this.onWebSocketStatusChange = onWebSocketStatusChange || (() => {});
    this.onErrorMessage = onErrorMessage || (() => {});
    this.eventIdCounter = 0;
    this.currentTranscript = '';
    this.connectionTimeoutId = null;
    this.retryCount = 0;
    this.maxRetries = 3;
    this.reconnecting = false;
  }

  /**
   * STEP 1: Initialize a transcription session via our server
   * 
   * Instead of directly calling OpenAI's API, we'll request our server
   * to create a session and return the WebSocket URL with proper authentication
   * 
   * @returns {Promise<boolean>} True if session was successfully created
   */
  async initialize() {
    try {
      this.onStatusChange('Creating transcription session...');
      
      const response = await fetch('/api/transcription/create-session', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        // Send any configuration parameters to the server
        body: JSON.stringify({
          language: 'en'
        })
      });
      
      if (!response.ok) {
        const error = `Error creating session: ${response.status} ${response.statusText}`;
        this.onErrorMessage(error);
        throw new Error(error);
      }
      
      const data = await response.json();
      
      // Save session info returned from our server
      this.sessionId = data.sessionId;
      this.wsUrl = data.wsUrl; // WebSocket URL with auth handled by server
      
      console.log('Session created with ID:', this.sessionId);
      this.onStatusChange('Session created successfully');
      
      // Connect to the WebSocket provided by our server
      return await this.connectWebSocket();
    } catch (error) {
      console.error('Failed to create session:', error);
      this.onStatusChange(`Session creation failed`);
      this.onErrorMessage(error.message);
      return false;
    }
  }

  /**
   * STEP 2: Connect to the WebSocket provided by our server
   * 
   * Our server will properly handle authentication with OpenAI and provide
   * a pre-authenticated WebSocket URL for us to connect to.
   * 
   * @returns {Promise<boolean>} True if WebSocket connection was successfully established
   */
  async connectWebSocket() {
    if (!this.sessionId || !this.wsUrl) {
      const error = 'Error: No session available';
      this.onWebSocketStatusChange('error');
      this.onStatusChange(error);
      this.onErrorMessage(error);
      return false;
    }
    
    try {
      this.onStatusChange('Preparing to connect...');
      this.onWebSocketStatusChange('connecting');
      
      // Log connection details for debugging
      console.log('Connection details:', {
        sessionId: this.sessionId,
        wsUrl: this.wsUrl.split('?')[0] + '?...',  // Don't log full URL with tokens
        networkStatus: navigator.onLine ? 'Online' : 'Offline',
        userAgent: navigator.userAgent,
        timestamp: new Date().toISOString()
      });
      
      console.log('Attempting WebSocket connection with session:', this.sessionId);
      
      // Clear any existing timeout
      if (this.connectionTimeoutId) {
        clearTimeout(this.connectionTimeoutId);
      }
      
      // Set connection timeout (10 seconds)
      this.connectionTimeoutId = setTimeout(() => {
        if (!this.isConnected) {
          console.error('WebSocket connection timeout after 10 seconds');
          if (this.socket) {
            this.socket.close();
            this.socket = null;
          }
          this.onWebSocketStatusChange('error');
          this.onStatusChange('Connection timeout');
          this.onErrorMessage('WebSocket connection timeout after 10 seconds');
          
          // Try to reconnect if we haven't exceeded max retries
          this.attemptReconnect();
        }
      }, 10000);
      
      // Create WebSocket connection to our server's WebSocket proxy
      // No need to handle authentication here - our server takes care of it
      this.socket = new WebSocket(this.wsUrl);
      
      // Monitor and log all readyState changes
      const logReadyState = () => {
        const states = ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'];
        console.log(`WebSocket readyState changed: ${states[this.socket.readyState]} (${this.socket.readyState})`);
      };
      
      // Initial readyState
      logReadyState();
      
      // Poll for readyState changes
      const readyStateInterval = setInterval(() => {
        if (!this.socket) {
          clearInterval(readyStateInterval);
          return;
        }
        logReadyState();
        if (this.socket.readyState === WebSocket.CLOSED) {
          clearInterval(readyStateInterval);
        }
      }, 500);
      
      /**
       * Handle WebSocket open event
       */
      this.socket.onopen = () => {
        console.log('WebSocket connection opened at:', new Date().toISOString());
        logReadyState();
        
        // Update WebSocket status
        this.isConnected = true;
        this.onWebSocketStatusChange('connected');
        this.onStatusChange('Connected and ready');
        console.log('WebSocket connection opened');
        
        // Clear connection timeout
        if (this.connectionTimeoutId) {
          clearTimeout(this.connectionTimeoutId);
          this.connectionTimeoutId = null;
        }
        
        // Reset retry count on successful connection
        this.retryCount = 0;
      };
      
      /**
       * Handle WebSocket messages
       */
      this.socket.onmessage = (event) => {
        console.log('WebSocket message received, size:', event.data.length);
        this.handleWebSocketMessage(event);
      };
      
      /**
       * Handle WebSocket errors
       */
      this.socket.onerror = (error) => {
        console.error('WebSocket error:', error);
        logReadyState();
        
        // Extract more information from the error event
        const errorDetails = {
          type: error.type,
          eventPhase: error.eventPhase,
          timeStamp: error.timeStamp,
          isTrusted: error.isTrusted,
          target: {
            url: error.target?.url,
            readyState: error.target?.readyState,
            protocol: error.target?.protocol,
            extensions: error.target?.extensions || ''
          }
        };
        
        console.error('WebSocket error details:', JSON.stringify(errorDetails));
        console.error('Network status at error time:', navigator.onLine ? 'Online' : 'Offline');
        
        this.onWebSocketStatusChange('error');
        this.onStatusChange('WebSocket error occurred');
        this.onErrorMessage(`WebSocket error: ${error.message || JSON.stringify(errorDetails) || 'Unknown WebSocket error'}`);
        this.isConnected = false;
        
        clearInterval(readyStateInterval);
      };
      
      /**
       * Handle WebSocket close events
       */
      this.socket.onclose = (event) => {
        logReadyState();
        
        const closeInfo = {
          code: event.code,
          reason: event.reason,
          wasClean: event.wasClean,
          timestamp: new Date().toISOString()
        };
        console.log('WebSocket closed:', JSON.stringify(closeInfo));
        
        // Provide more context based on close codes
        let closeMessage = event.reason || 'Connection closed';
        let shouldReconnect = false;
        
        if (event.code === 1000) {
          closeMessage = 'Normal closure';
        } else if (event.code === 1001) {
          closeMessage = 'Endpoint going away';
          shouldReconnect = true;
        } else if (event.code === 1006) {
          closeMessage = 'Abnormal closure - server may be unreachable';
          shouldReconnect = true;
        } else if (event.code === 1011) {
          closeMessage = 'Server error occurred';
          shouldReconnect = true;
        } else if (event.code === 1012) {
          closeMessage = 'Server restarting';
          shouldReconnect = true;
        } else if (event.code === 1013) {
          closeMessage = 'Try again later';
          shouldReconnect = true;
        } else if (event.code === 1014) {
          closeMessage = 'Bad gateway';
          shouldReconnect = true;
        }
        
        this.onWebSocketStatusChange('disconnected');
        this.onStatusChange(`WebSocket disconnected: ${closeMessage} (code: ${event.code})`);
        this.isConnected = false;
        
        // Clear connection timeout
        if (this.connectionTimeoutId) {
          clearTimeout(this.connectionTimeoutId);
          this.connectionTimeoutId = null;
        }
        
        // Attempt to reconnect if appropriate
        if (shouldReconnect) {
          this.attemptReconnect();
        }
        
        clearInterval(readyStateInterval);
      };
      
      return true;
    } catch (error) {
      console.error('Failed to connect WebSocket:', error);
      console.error('Error stack:', error.stack);
      this.onWebSocketStatusChange('error');
      this.onStatusChange(`Connection error`);
      this.onErrorMessage(`WebSocket connection error: ${error.message}`);
      return false;
    }
  }

  /**
   * Attempt to reconnect to the WebSocket server
   */
  attemptReconnect() {
    // Only attempt if not already reconnecting
    if (this.reconnecting) {
      return;
    }
    
    this.reconnecting = true;
    
    // If we've exceeded max retries, don't attempt again
    if (this.retryCount >= this.maxRetries) {
      console.log(`Maximum retry attempts (${this.maxRetries}) reached, giving up`);
      this.onStatusChange(`Connection failed after ${this.maxRetries} attempts`);
      this.reconnecting = false;
      this.retryCount = 0;
      return;
    }
    
    this.retryCount++;
    const backoffDelay = Math.min(1000 * Math.pow(2, this.retryCount - 1), 10000); // Exponential backoff, max 10 seconds
    
    console.log(`Attempting to reconnect (try ${this.retryCount}/${this.maxRetries}) in ${backoffDelay}ms...`);
    this.onStatusChange(`Reconnecting in ${backoffDelay/1000} seconds... (attempt ${this.retryCount}/${this.maxRetries})`);
    
    setTimeout(async () => {
      console.log(`Executing reconnection attempt ${this.retryCount}`);
      
      // Clean up existing socket if any
      if (this.socket) {
        this.socket.close();
        this.socket = null;
      }
      
      // Connection sequence
      await this.connectWebSocket();
      this.reconnecting = false;
    }, backoffDelay);
  }

  /**
   * STEP 3: Process WebSocket messages
   * 
   * Handle messages from our proxied WebSocket connection
   * @param {MessageEvent} event The WebSocket message event
   */
  handleWebSocketMessage(event) {
    try {
      const message = JSON.parse(event.data);
      console.log('WS message received:', message.type, message);
      
      // Handle different message types
      switch (message.type) {
        case 'session.created':
        case 'transcription_session.created':
        case 'transcription_session.updated':
          this.isConnected = true;
          this.onWebSocketStatusChange('connected');
          this.onStatusChange('Connected and ready');
          console.log('WebSocket session created/updated successfully');
          break;
        
        case 'error':
          console.error('WebSocket error message:', message.error);
          this.onWebSocketStatusChange('error');
          this.onStatusChange(`Error: ${message.error.message}`);
          this.onErrorMessage(`WebSocket error: ${message.error.message}`);
          break;
        
        case 'conversation.item.input_audio_transcription.delta':
          // Update transcript with delta
          if (message.delta) {
            this.currentTranscript += message.delta;
            this.onTranscriptionUpdate(this.currentTranscript);
          }
          break;
        
        case 'conversation.item.input_audio_transcription.completed':
          // Final transcript for this segment
          if (message.transcript) {
            this.currentTranscript = message.transcript;
            this.onTranscriptionUpdate(this.currentTranscript);
            console.log('Transcription completed:', message.transcript);
          }
          break;
          
        case 'input_audio_buffer.speech_started':
          this.onStatusChange('Speech detected');
          console.log('Speech started detected by server');
          break;
          
        case 'input_audio_buffer.speech_stopped':
          this.onStatusChange('Speech ended, processing...');
          console.log('Speech stopped detected by server');
          break;
          
        case 'input_audio_buffer.committed':
          this.onStatusChange('Audio committed');
          console.log('Audio buffer committed successfully');
          break;
          
        case 'input_audio_buffer.cleared':
          this.onStatusChange('Audio buffer cleared');
          console.log('Audio buffer cleared');
          break;
          
        case 'conversation.created':
          console.log('Conversation created:', message.conversation?.id);
          break;
          
        case 'conversation.item.created':
          console.log('Conversation item created:', message.item?.id);
          break;
          
        case 'rate_limits.updated':
          console.log('Rate limits updated:', message.rate_limits);
          break;
        
        default:
          // For debugging
          console.log('Received unknown message type:', message.type, message);
      }
    } catch (error) {
      console.error('Error processing WebSocket message:', error, 'Raw data:', event.data);
      this.onErrorMessage(`Error processing WebSocket message: ${error.message}`);
    }
  }

  /**
   * STEP 4: Send audio data for transcription
   * 
   * @param {Int16Array} audioData PCM audio data to send for transcription
   * @returns {boolean} True if audio was successfully sent
   */
  sendAudio(audioData) {
    if (!this.isConnected || !this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return false;
    }
    
    try {
      // Convert Int16Array to base64
      const base64Audio = this.arrayBufferToBase64(audioData.buffer);
      
      // Create audio buffer append message
      const message = {
        type: 'input_audio_buffer.append',
        event_id: `event_${this.eventIdCounter++}`,
        audio: base64Audio
      };
      
      // Send the message
      this.socket.send(JSON.stringify(message));
      return true;
    } catch (error) {
      console.error('Error sending audio:', error);
      this.onErrorMessage(`Error sending audio: ${error.message}`);
      return false;
    }
  }

  /**
   * Convert ArrayBuffer to Base64 string
   * 
   * Helper function to convert audio data (ArrayBuffer) to Base64 encoding
   * for sending over the WebSocket connection.
   * 
   * @param {ArrayBuffer} buffer The array buffer to convert
   * @returns {string} Base64 encoded string
   */
  arrayBufferToBase64(buffer) {
    const bytes = new Uint8Array(buffer);
    const binary = bytes.reduce((acc, byte) => acc + String.fromCharCode(byte), '');
    return btoa(binary);
  }

  /**
   * STEP 5: Disconnect from the WebSocket
   */
  disconnect() {
    this.currentTranscript = '';
    
    // Clear connection timeout if any
    if (this.connectionTimeoutId) {
      clearTimeout(this.connectionTimeoutId);
      this.connectionTimeoutId = null;
    }
    
    // Reset reconnection state
    this.reconnecting = false;
    this.retryCount = 0;
    
    if (this.socket) {
      this.socket.close();
      this.socket = null;
    }
    
    this.isConnected = false;
    this.sessionId = null;
    this.wsUrl = null;
    this.onWebSocketStatusChange('disconnected');
  }
} 