# Makefile: Volume Control build rules

UID      := $(shell id -u)
BUILD_DIR := /tmp/VolumeControl-$(UID)/build
CONFIGURATION_BUILD_DIR := $(BUILD_DIR)/target
DESTINATION_X86_64  := "platform=macOS,arch=x86_64"
DESTINATION_ARM64  := "platform=macOS,arch=arm64"

PROJECT   := Volume Control.xcodeproj
SCHEME    := Volume Control

.PHONY: debug-arm64 debug-x86_64 release \
        clean-arm64 clean-x86_64 run generate-db

Q ?= @   # quiet by default; override with `make Q=`

# Debug build for ARM64
debug-arm64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_ARM64}" \
	    BUILD_DIR="$(BUILD_DIR)/debug" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    build | xcpretty

# Debug build for x86_64
debug-x86_64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_X86_64}" \
	    BUILD_DIR="$(BUILD_DIR)/debug" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    build | xcpretty

# Release build for distribution (both archs)
release:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Release \
	    ARCHS="arm64 x86_64" \
	    ONLY_ACTIVE_ARCH=NO \
	    BUILD_DIR="$(BUILD_DIR)/release" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/release" \
	    build | xcpretty

# Clean targets
clean-arm64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_ARM64}" \
	    BUILD_DIR="$(BUILD_DIR)/debug" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    clean | xcpretty

clean-x86_64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_ARM64}" \
	    BUILD_DIR="$(BUILD_DIR)/debug" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    clean | xcpretty

# Run the app (after debug build)
run:
	$(Q)open "$(CONFIGURATION_BUILD_DIR)/debug/Volume Control.app"
	command log stream --process "Volume Control" --predicate 'eventMessage CONTAINS "[DEBUG]"'
run:
	$(Q)killall -15 "Volume Control" 2>/dev/null || true
	$(Q)open "$(CONFIGURATION_BUILD_DIR)/debug/Volume Control.app"
	echo "Waiting for logs from Volume Control..."
	$(Q)command log stream --process "Volume Control"

# Generate compile_commands.json for LSP-clangd server
generate-db-x86_64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_X86_64}" \
	    BUILD_DIR="$(BUILD_DIR)" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    clean build | xcpretty -r json-compilation-database -o compile_commands_x86_64.json

generate-db-arm64:
	$(Q)xcrun xcodebuild \
	    -project "$(PROJECT)" \
	    -scheme "$(SCHEME)" \
	    -configuration Debug \
	    -destination "${DESTINATION_ARM64}" \
	    BUILD_DIR="$(BUILD_DIR)" \
	    CONFIGURATION_BUILD_DIR="$(CONFIGURATION_BUILD_DIR)/debug" \
	    clean build | xcpretty -r json-compilation-database -o compile_commands_arm64.json
