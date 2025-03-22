.PHONY: build clean run verbose-build logs tail-logs

# Configuration
PROJECT_NAME = sheptun
PROJECT_FILE = $(PROJECT_NAME).xcodeproj
BUILD_DIR = build
CONFIGURATION = Debug
SCHEME = $(PROJECT_NAME)
LOG_FILE = ~/Library/Application\ Support/$(PROJECT_NAME)/debug.log

# Check if xcpretty is installed
XCPRETTY := $(shell command -v xcpretty 2> /dev/null)

# Default target
all: build

# Build the application
build:
	@echo "Building $(PROJECT_NAME)..."
ifdef XCPRETTY
	@xcodebuild -project $(PROJECT_FILE) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(BUILD_DIR) build | xcpretty -c
else
	@xcodebuild -project $(PROJECT_FILE) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(BUILD_DIR) build
endif

# Build with verbose output and show full errors
verbose-build:
	@echo "Building $(PROJECT_NAME) with verbose output..."
	@xcodebuild -project $(PROJECT_FILE) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(BUILD_DIR) build

# Clean build artifacts
clean:
	@echo "Cleaning $(PROJECT_NAME)..."
	@xcodebuild -project $(PROJECT_FILE) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(BUILD_DIR) clean

# Run the application
run: build
	@echo "Running $(PROJECT_NAME)..."
	@open $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(PROJECT_NAME).app

# Show project schemes
schemes:
	@xcodebuild -project $(PROJECT_FILE) -list

# View the log file
logs:
	@echo "Displaying logs..."
	@cat ~/Library/Containers/$(PROJECT_NAME)/Data/Documents/$(PROJECT_NAME)/debug.log 2>/dev/null || cat ~/Library/Application\ Support/$(PROJECT_NAME)/debug.log 2>/dev/null || echo "Log file not found"

# Follow the log file in real-time
tail-logs:
	@echo "Following logs in real-time (Ctrl+C to exit)..."
	@tail -f ~/Library/Containers/$(PROJECT_NAME)/Data/Documents/$(PROJECT_NAME)/debug.log 2>/dev/null || tail -f ~/Library/Application\ Support/$(PROJECT_NAME)/debug.log 2>/dev/null || echo "Log file not found"

# Clean logs
clean-logs:
	@echo "Cleaning logs..."
	@rm -f ~/Library/Containers/$(PROJECT_NAME)/Data/Documents/$(PROJECT_NAME)/debug.log 2>/dev/null
	@rm -f ~/Library/Application\ Support/$(PROJECT_NAME)/debug.log 2>/dev/null
	@echo "Logs cleaned" 