export default class AudioProcessor {
  constructor(onAudioData, onVolumeChange) {
    this.audioContext = null;
    this.mediaStream = null;
    this.mediaRecorder = null;
    this.sourceNode = null;
    this.analyserNode = null;
    this.processor = null;
    this.isRecording = false;
    this.onAudioData = onAudioData;
    this.onVolumeChange = onVolumeChange;
    this.sampleRate = 24000; // Required by OpenAI: 24kHz
  }

  async initAudio() {
    if (this.audioContext) return;

    try {
      // Request microphone access
      this.mediaStream = await navigator.mediaDevices.getUserMedia({
        audio: {
          channelCount: 1, // Mono audio
          sampleRate: this.sampleRate,
        },
        video: false
      });

      // Create audio context
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)({
        sampleRate: this.sampleRate,
      });

      // Create audio graph nodes
      this.sourceNode = this.audioContext.createMediaStreamSource(this.mediaStream);
      this.analyserNode = this.audioContext.createAnalyser();
      this.analyserNode.fftSize = 256;
      
      // Connect nodes
      this.sourceNode.connect(this.analyserNode);
      
      // Create processor for audio data
      this.processor = this.audioContext.createScriptProcessor(4096, 1, 1);
      this.processor.onaudioprocess = this.handleAudioProcess.bind(this);
      
      // Connect processor and start
      this.analyserNode.connect(this.processor);
      this.processor.connect(this.audioContext.destination);
      
      // Start volume meter
      this.startVolumeMeter();
      
      return true;
    } catch (error) {
      console.error('Error initializing audio:', error);
      return false;
    }
  }

  startRecording() {
    if (!this.audioContext || this.isRecording) return false;
    this.isRecording = true;
    return true;
  }

  stopRecording() {
    if (!this.isRecording) return;
    this.isRecording = false;
    
    // We keep the audio context and stream alive for quick restart
    // But we could close them here if needed
  }

  closeAudio() {
    this.stopRecording();
    
    if (this.processor) {
      this.processor.disconnect();
      this.processor = null;
    }
    
    if (this.analyserNode) {
      this.analyserNode.disconnect();
      this.analyserNode = null;
    }
    
    if (this.sourceNode) {
      this.sourceNode.disconnect();
      this.sourceNode = null;
    }
    
    if (this.mediaStream) {
      this.mediaStream.getTracks().forEach(track => track.stop());
      this.mediaStream = null;
    }
    
    if (this.audioContext) {
      this.audioContext.close();
      this.audioContext = null;
    }
    
    this.isRecording = false;
  }

  handleAudioProcess(e) {
    if (!this.isRecording) return;
    
    // Get audio data from the buffer
    const inputBuffer = e.inputBuffer;
    const inputData = inputBuffer.getChannelData(0);
    
    // Convert Float32Array to Int16Array for PCM16 format
    const pcmData = this.floatTo16BitPCM(inputData);
    
    // Pass audio data to callback
    if (this.onAudioData && this.isRecording) {
      this.onAudioData(pcmData);
    }
  }

  startVolumeMeter() {
    if (!this.analyserNode) return;
    
    const dataArray = new Uint8Array(this.analyserNode.frequencyBinCount);
    
    const updateVolume = () => {
      if (!this.analyserNode) return;
      
      this.analyserNode.getByteFrequencyData(dataArray);
      
      // Calculate volume level (0-100)
      let sum = 0;
      for (let i = 0; i < dataArray.length; i++) {
        sum += dataArray[i];
      }
      const average = sum / dataArray.length;
      const volume = Math.min(100, average * 2); // Scale up for better visibility
      
      if (this.onVolumeChange) {
        this.onVolumeChange(volume);
      }
      
      // Continue updating
      requestAnimationFrame(updateVolume);
    };
    
    updateVolume();
  }

  floatTo16BitPCM(float32Array) {
    const int16Array = new Int16Array(float32Array.length);
    for (let i = 0; i < float32Array.length; i++) {
      // Convert float [-1.0, 1.0] to int16 [-32768, 32767]
      const s = Math.max(-1, Math.min(1, float32Array[i]));
      int16Array[i] = s < 0 ? s * 0x8000 : s * 0x7FFF;
    }
    return int16Array;
  }
} 