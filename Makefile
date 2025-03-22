.PHONY: build clean run verbose-build logs-view logs-tail logs-clean logs-crash logs-latest

# Configuration
PROJECT_NAME = sheptun
PROJECT_FILE = $(PROJECT_NAME).xcodeproj
BUILD_DIR = build
CONFIGURATION = Debug
SCHEME = $(PROJECT_NAME)
LOG_FILE = ~/Library/Containers/com.carsan.sheptun/Data/Documents/Sheptun/debug.log

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
	@killall "$(PROJECT_NAME)" 2>/dev/null || true
	@open $(BUILD_DIR)/Build/Products/$(CONFIGURATION)/$(PROJECT_NAME).app

# Show project schemes
schemes:
	@xcodebuild -project $(PROJECT_FILE) -list

# View the log file
logs-view:
	@echo "Displaying logs..."
	@cat $(LOG_FILE) 2>/dev/null || echo "Log file not found at $(LOG_FILE)"

# For backward compatibility
logs: logs-view

# Follow the log file in real-time
logs-tail:
	@echo "Following logs in real-time (Ctrl+C to exit)..."
	@tail -f $(LOG_FILE) 2>/dev/null || echo "Log file not found at $(LOG_FILE)"

# Clean logs
logs-clean:
	@echo "Cleaning logs..."
	@rm -f $(LOG_FILE) 2>/dev/null
	@echo "Logs cleaned"

# View crash logs
logs-crash:
	@echo "Displaying crash logs..."
	@ls -lt ~/Library/Logs/DiagnosticReports/$(PROJECT_NAME)_*.crash 2>/dev/null || echo "No crash logs found"
	@echo ""
	@echo "To view a specific crash log, use: open ~/Library/Logs/DiagnosticReports/FILENAME"

# Open most recent crash log
logs-latest:
	@echo "Opening most recent crash log..."
	@LATEST=$$(ls -t ~/Library/Logs/DiagnosticReports/$(PROJECT_NAME)_*.crash 2>/dev/null | head -1); \
	if [ -n "$$LATEST" ]; then \
		echo "Opening: $$LATEST"; \
		open "$$LATEST"; \
	else \
		echo "No crash logs found"; \
	fi 