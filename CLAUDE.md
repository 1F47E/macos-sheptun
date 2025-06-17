# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Sheptun is a macOS menu bar application built with SwiftUI that provides speech-to-text functionality using OpenAI's Whisper API. The app runs as a status bar item and allows users to record audio via a global hotkey, transcribe it, and optionally paste the transcribed text.

## Build and Development Commands

```bash
# Build the application
make build

# Build with verbose output (for debugging build issues)
make verbose-build

# Build and run the application
make run

# Clean build artifacts
make clean

# View logs
make logs         # Display full log file
make logs-tail    # Follow logs in real-time
make logs-clean   # Clean log files
make logs-crash   # View crash logs
make logs-latest  # Open most recent crash log
```

Note: The Makefile supports xcpretty for cleaner build output if installed, but falls back to standard xcodebuild output if not available.

## Architecture Overview

### Core Components

1. **sheptunApp.swift**: Main app entry point with AppDelegate that manages:
   - Status bar item with microphone status indicator (red when no microphones available)
   - Global hotkey registration
   - Settings window management
   - Microphone permission handling

2. **PopupWindowManager.swift**: Central component managing the floating transcription window
   - Uses a state machine pattern (TranscriberState enum) for recording/transcribing/completed/error states
   - Manages a reusable NSWindow with SwiftUI content
   - Coordinates with AudioRecorder and AI providers

3. **Audio System**:
   - **AudioRecorder.swift**: Handles microphone recording with AVAudioEngine
   - **AudioLevelMonitor.swift**: Monitors audio levels for visual feedback

4. **AI Integration**:
   - **AIProvider.swift**: Protocol defining transcription interface
   - **OpenAIManager.swift**: OpenAI Whisper API implementation
   - **GroqAIManager.swift**: Groq API implementation (alternative provider)

5. **Settings & Configuration**:
   - **SettingsManager.swift**: Singleton managing UserDefaults-based settings
   - **SettingsView.swift**: SwiftUI settings interface
   - **HotkeyManager.swift** & **HotkeyRecorder.swift**: Global hotkey handling

### Key Design Patterns

- **Singleton Pattern**: Used for managers (SettingsManager, Logger, AudioRecorder, PopupWindowManager)
- **State Machine**: TranscriberState enum drives UI updates in the popup window
- **Protocol-Oriented**: AIProvider protocol allows swapping between OpenAI and Groq

### Important Implementation Details

- The app uses GRDB for database operations (imported in PopupWindowManager.swift)
- Logs are stored at: `~/Library/Containers/com.carsan.sheptun/Data/Documents/Sheptun/debug.log`
- The app runs without a dock icon (LSUIElement = true)
- Requires entitlements for: audio input, network client, app sandbox

### API Integration

The app supports multiple transcription endpoints:
- OpenAI Whisper API (whisper-1, gpt-4o-mini-transcribe, gpt-4o-transcribe)
- Groq API as an alternative provider
- See API.md for detailed API documentation

## Development Notes

- When modifying the popup window behavior, changes primarily go in PopupWindowManager.swift
- Audio recording logic is centralized in AudioRecorder.swift
- All UI strings and settings keys are hardcoded (no localization system currently)
- The app checks for microphone availability and updates the status bar icon color accordingly