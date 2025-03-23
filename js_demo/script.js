import AudioProcessor from './audioProcessor.js';
import OpenAIClient from './openaiClient.js';

class TranscriptionApp {
  constructor() {
    // UI Elements
    this.startButton = document.getElementById('startButton');
    this.stopButton = document.getElementById('stopButton');
    this.statusElement = document.getElementById('status');
    this.wsStatusElement = document.getElementById('wsStatus');
    this.audioMeterElement = document.getElementById('audioMeter');
    this.transcriptionElement = document.getElementById('transcription');
    this.errorContainer = document.getElementById('errorContainer');
    this.errorMessageElement = document.getElementById('errorMessage');
    this.clearErrorButton = document.getElementById('clearErrorButton');
    this.debugInfoElement = document.getElementById('debugInfo');
    
    // App state
    this.isRecording = false;
    this.debugMessages = [];
    
    // Initialize components
    this.audioProcessor = new AudioProcessor(
      this.handleAudioData.bind(this),
      this.updateVolumeMeter.bind(this)
    );
    
    this.openaiClient = new OpenAIClient(
      this.updateTranscription.bind(this),
      this.updateStatus.bind(this),
      this.updateWebSocketStatus.bind(this),
      this.showErrorMessage.bind(this)
    );
    
    // Setup event listeners
    this.startButton.addEventListener('click', this.startRecording.bind(this));
    this.stopButton.addEventListener('click', this.stopRecording.bind(this));
    this.clearErrorButton.addEventListener('click', this.clearError.bind(this));
    
    // Initialize application
    this.initializeApp();
  }

  async initializeApp() {
    try {
      this.updateStatus('Initializing application...');
      this.addDebugMessage('Application initializing');
      
      // No need to validate API key here anymore since that happens on the server
      this.updateStatus('Ready to record');
      this.addDebugMessage('Initialization complete, ready to record');
    } catch (error) {
      console.error('Error initializing app:', error);
      this.updateStatus(`Error initializing app`);
      this.showErrorMessage(`Initialization error: ${error.message}`);
      this.startButton.disabled = true;
    }
  }

  async startRecording() {
    if (this.isRecording) return;
    
    try {
      this.updateStatus('Initializing audio...');
      this.addDebugMessage('Starting recording process');
      
      // Initialize audio
      const audioInitialized = await this.audioProcessor.initAudio();
      if (!audioInitialized) {
        this.updateStatus('Failed to initialize audio');
        this.showErrorMessage('Could not access microphone. Please check permissions and try again.');
        return;
      }
      
      this.addDebugMessage('Audio initialized successfully');
      this.updateStatus('Creating OpenAI session...');
      
      // Initialize OpenAI session through our server
      const sessionInitialized = await this.openaiClient.initialize();
      if (!sessionInitialized) {
        this.addDebugMessage('Failed to initialize OpenAI session');
        return;
      }
      
      // Start recording
      this.audioProcessor.startRecording();
      this.isRecording = true;
      
      // Update UI
      this.startButton.disabled = true;
      this.stopButton.disabled = false;
      this.transcriptionElement.textContent = '';
      this.updateStatus('Recording started');
      this.addDebugMessage('Recording started successfully');
    } catch (error) {
      console.error('Error starting recording:', error);
      this.updateStatus('Failed to start recording');
      this.showErrorMessage(`Start recording error: ${error.message}`);
    }
  }

  stopRecording() {
    if (!this.isRecording) return;
    
    this.audioProcessor.stopRecording();
    this.openaiClient.disconnect();
    this.isRecording = false;
    
    // Update UI
    this.startButton.disabled = false;
    this.stopButton.disabled = true;
    this.updateStatus('Recording stopped');
    this.updateVolumeMeter(0);
    this.addDebugMessage('Recording stopped');
  }

  handleAudioData(audioData) {
    if (this.isRecording) {
      this.openaiClient.sendAudio(audioData);
    }
  }

  updateTranscription(text) {
    this.transcriptionElement.textContent = text;
  }

  updateStatus(message) {
    this.statusElement.textContent = message;
    console.log('Status:', message);
  }

  updateWebSocketStatus(status) {
    this.wsStatusElement.textContent = status;
    this.wsStatusElement.setAttribute('data-status', status);
    this.addDebugMessage(`WebSocket status changed: ${status}`);
  }

  updateVolumeMeter(volume) {
    this.audioMeterElement.style.setProperty('--volume', `${volume}%`);
    // For browsers that don't support CSS custom properties
    this.audioMeterElement.style.background = 
      `linear-gradient(to right, #3498db ${volume}%, #eee ${volume}%)`;
  }

  showErrorMessage(message) {
    this.errorMessageElement.textContent = message;
    this.errorContainer.classList.add('visible');
    this.addDebugMessage(`ERROR: ${message}`);
  }

  clearError() {
    this.errorMessageElement.textContent = '';
    this.errorContainer.classList.remove('visible');
  }

  addDebugMessage(message) {
    const timestamp = new Date().toISOString();
    const formattedMessage = `[${timestamp}] ${message}`;
    this.debugMessages.push(formattedMessage);
    
    // Keep only the last 100 messages
    if (this.debugMessages.length > 100) {
      this.debugMessages.shift();
    }
    
    // Update the debug info display
    this.debugInfoElement.textContent = this.debugMessages.join('\n');
    
    // Auto-scroll to bottom
    this.debugInfoElement.scrollTop = this.debugInfoElement.scrollHeight;
  }
}

// Initialize app when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  new TranscriptionApp();
}); 