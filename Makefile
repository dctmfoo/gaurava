APP_NAME := Gaurava
APP_PROJECT := Gaurava.xcodeproj
APP_WORKSPACE := Gaurava.xcworkspace
APP_SCHEME ?= Gaurava
# Watch app scheme + simulator (Phase 0). The watch app is built/launched on a
# watchOS Simulator; the iOS `Gaurava` scheme already embeds + compiles it.
WATCH_SCHEME ?= GauravaWatch
WATCH_SIM_NAME ?= auto
APP_PLATFORM := ios
APP_GENERATOR := xcodegen
CONFIGURATION ?= Debug
SIM_NAME ?= auto
TARGET_PREFIX :=
SCRIPTS_DIR := ./scripts
ASC_APP_ID ?= 6775155354
ASC_TESTFLIGHT_GROUP ?= 8a379ef0-71cb-4b01-bea1-e271cf518c16
APPLE_TEAM_ID ?=
APP_BUNDLE_ID ?= com.nags.gaurava
TESTFLIGHT_INTERNAL_TESTING_ONLY ?= false
RELEASE_PROFILE_UUID ?=
RELEASE_PROFILE_SPECIFIER ?= Gaurava App Store AppGroups
RELEASE_PROFILE_PATH ?= $(HOME)/Library/MobileDevice/Provisioning Profiles/$(RELEASE_PROFILE_UUID).mobileprovision
# Widget extension needs its own App Store profile (App Groups capability).
WIDGET_BUNDLE_ID ?= com.nags.gaurava.GauravaWidgets
WIDGET_RELEASE_PROFILE_UUID ?=
WIDGET_RELEASE_PROFILE_SPECIFIER ?= Gaurava Widgets App Store
# Watch app + watch widget App Store profiles. Both App IDs have App Groups
# (group.com.nags.gaurava) enabled and assigned, and the distribution profiles
# below carry that entitlement; `make testflight` maps both bundle IDs in the
# export options (the watch app ships embedded in the iOS archive).
#   com.nags.gaurava.watchkitapp                       (App ID 9Y9GPXFZ22)
#   com.nags.gaurava.watchkitapp.GauravaWatchWidgets   (App ID 7YF9SKT4Y6)
WATCH_BUNDLE_ID ?= com.nags.gaurava.watchkitapp
WATCH_WIDGET_BUNDLE_ID ?= com.nags.gaurava.watchkitapp.GauravaWatchWidgets
WATCH_RELEASE_PROFILE_UUID ?=
WATCH_WIDGET_RELEASE_PROFILE_UUID ?=
WATCH_RELEASE_PROFILE_SPECIFIER ?= Gaurava Watch App Store
WATCH_WIDGET_RELEASE_PROFILE_SPECIFIER ?= Gaurava Watch Widgets App Store
CLOUDKIT_CONTAINER ?= iCloud.com.nags.gaurava
ONBOARDING_SANDBOX_SCHEME ?= GauravaOnboarding
ONBOARDING_SANDBOX_BUNDLE_ID ?= com.nags.gaurava.onboarding
ONBOARDING_SANDBOX_DEVICE_FILTER ?= iPhone
# Optional App Store Connect API key for headless device signing. Leave
# ASC_KEY_PATH empty to sign via the Xcode-account (-allowProvisioningUpdates).
ASC_KEY_ID ?= S6AHM3S48K
ASC_ISSUER_ID ?= 6aa2c530-187a-41b6-a6da-1aa81974d90b
ASC_KEY_PATH ?=
IOS_ARCHIVE_PATH ?= build/Gaurava.xcarchive
IOS_EXPORT_PATH ?= build/export
IOS_EXPORT_OPTIONS ?= build/ExportOptions.generated.plist
IOS_IPA_PATH ?= $(IOS_EXPORT_PATH)/Gaurava.ipa
ASC_OUTPUT ?= json
CHECK_RELEASE_CONFIG_DRY_RUN ?= 0
RELEASE_CONFIG_DERIVED ?= build/DerivedData/release-config
RELEASE_CONFIG_WATCH_APP ?= $(RELEASE_CONFIG_DERIVED)/Build/Products/Release-iphonesimulator/Gaurava.app/Watch/Gaurava.app

WORKSPACE ?= $(firstword $(wildcard *.xcworkspace))
PROJECT ?= $(firstword $(wildcard *.xcodeproj))
ifeq ($(strip $(PROJECT)),)
PROJECT := $(APP_PROJECT)
endif

ifeq ($(strip $(WORKSPACE)),)
BUILD_FILE_FLAG := -project $(PROJECT)
else
BUILD_FILE_FLAG := -workspace $(WORKSPACE)
endif

ifeq ($(TARGET_PREFIX),)
.DEFAULT_GOAL := build-and-run
endif

XCBUILD := $(SCRIPTS_DIR)/xcbuild.sh

ifeq ($(origin AGENT_NAME), undefined)
AGENT_NAME := $(shell $(SCRIPTS_DIR)/resolve_agent_name.sh)
endif

DERIVED_BASE := build/DerivedData
DERIVED := $(DERIVED_BASE)/$(AGENT_NAME)
LOG_DIR := build/logs/$(AGENT_NAME)
CACHE_ROOT := $(CURDIR)/build/cache/$(AGENT_NAME)
TMPDIR_PATH := $(CURDIR)/build/tmp/$(AGENT_NAME)

ifeq ($(APP_PLATFORM),ios)
PLATFORM_SUFFIX := -iphonesimulator
else
PLATFORM_SUFFIX :=
DESTINATION := platform=macOS,arch=arm64
endif

BUILD_PRODUCTS := $(DERIVED)/Build/Products/$(CONFIGURATION)$(PLATFORM_SUFFIX)
APP_PATH := $(BUILD_PRODUCTS)/$(APP_SCHEME).app

# --- Test lanes ---------------------------------------------------------------
# The correctness gate (`test` / `agent-verify`) runs unit + functional UI suites
# but SKIPS capture-only suites: those generate reviewed visual artifacts, not
# hidden pass/fail signal. Regenerate reviewed artifacts on demand with
# `make capture-screenshots`.
CAPTURE_ONLY_SUITES := \
	GauravaUITests/LocalizedScreenshotAuditUITests \
	GauravaUITests/MarketingScreenshotTests \
	GauravaUITests/SemaglutideVerificationScreenshotTests
SKIP_CAPTURE_ONLY := $(foreach s,$(CAPTURE_ONLY_SUITES),-skip-testing:$(s))
ONLY_CAPTURE_ONLY := $(foreach s,$(CAPTURE_ONLY_SUITES),-only-testing:$(s))
UI_SMOKE_TESTS ?= \
	GauravaUITests/GauravaUITests/testMainTabsAppear \
	GauravaUITests/GauravaUITests/testSummaryDailyLogActionOpensDailyNoteSheet \
	GauravaUITests/GauravaUITests/testSeededResultsShowsReferenceChartControls \
	GauravaUITests/GauravaUITests/testCarePrivacyDataSafetyAndAboutSurfacesOpen \
	GauravaUITests/FirstRunUITests/testCompletingFirstRunEntersTabShellAndDoesNotReturn \
	GauravaUITests/DeepLinkPrivacyUITests/testDeepLinkSelectsJabsTab
UI_SMOKE_SCOPE_FLAGS := $(foreach t,$(UI_SMOKE_TESTS),-only-testing:$(t))
CAPTURE_DEVICE ?= iphone
CAPTURE_THEME ?= light
CAPTURE_MEDICATION ?= tirzepatide
CAPTURE_LOCALES ?= en hi ta te
THEME_MATRIX_THEMES ?= editorial-ink midnight-focus
THEME_MATRIX_APPEARANCES ?= light dark
THEME_MATRIX_SEED ?= scratch/seed/gaurava/owner-seed.json
THEME_MATRIX_OUTPUT_DIR ?= build/evidence/theme-matrix/$$(date +%Y%m%d-%H%M%S)
SURFACE_SNAPSHOT_SCHEME ?= GauravaSurfaceSnapshots
SURFACE_SNAPSHOT_TEST ?= GauravaSurfaceSnapshots/SurfaceSnapshotTests/testCaptureSurfaceSnapshots
SURFACE_SNAPSHOT_EXPORT_DIR ?= build/evidence/surface-snapshots
# Scope a run to specific tests (space-separated, repeatable), e.g.
#   make test TEST_ONLY=GauravaUITests/TabBarMinimizeUITests
# Empty = the full gate (everything except the capture-only suites above).
TEST_ONLY ?=
ifeq ($(strip $(TEST_ONLY)),)
TEST_SCOPE_FLAGS := $(SKIP_CAPTURE_ONLY)
else
TEST_SCOPE_FLAGS := $(foreach t,$(TEST_ONLY),-only-testing:$(t))
endif
# Parallel UI testing clones the simulator and runs test classes concurrently.
# Disable with TEST_PARALLEL=NO; cap runners with TEST_WORKERS=<n> (this Mac has
# 10 performance cores; 4 keeps RAM/CPU sane while ~halving UI wall time).
TEST_PARALLEL ?= YES
TEST_WORKERS ?= 4
TEST_PARALLEL_FLAGS := -parallel-testing-enabled $(TEST_PARALLEL) -maximum-parallel-testing-workers $(TEST_WORKERS)
# Retry transient UI-test flakes (parallel sim clones can lose a race on a slow
# element wait / app launch under contention). A genuinely-broken test still fails
# all attempts (xcodebuild default max = 3), so only transient flakes recover —
# real regressions are NOT masked. Disable with TEST_RETRY=NO.
TEST_RETRY ?= YES
ifeq ($(TEST_RETRY),YES)
TEST_RETRY_FLAGS := -retry-tests-on-failure
else
TEST_RETRY_FLAGS :=
endif

PHONY_TARGETS := $(TARGET_PREFIX)help $(TARGET_PREFIX)diagnose $(TARGET_PREFIX)build \
	$(TARGET_PREFIX)test $(TARGET_PREFIX)test-unit $(TARGET_PREFIX)test-ui-smoke \
	$(TARGET_PREFIX)test-regression $(TARGET_PREFIX)test-list \
	$(TARGET_PREFIX)check-screenshot-policy $(TARGET_PREFIX)test-screenshots \
	$(TARGET_PREFIX)capture-screenshots $(TARGET_PREFIX)capture-theme-matrix \
	$(TARGET_PREFIX)test-surface-snapshots \
	$(TARGET_PREFIX)run $(TARGET_PREFIX)build-and-run \
	$(TARGET_PREFIX)build-and-run-background $(TARGET_PREFIX)clean \
	$(TARGET_PREFIX)check-process $(TARGET_PREFIX)check-device-install $(TARGET_PREFIX)check-release-config \
	$(TARGET_PREFIX)release-readiness $(TARGET_PREFIX)agent-verify \
	$(TARGET_PREFIX)bump-build $(TARGET_PREFIX)testflight $(TARGET_PREFIX)implement-testflight \
	$(TARGET_PREFIX)device-install $(TARGET_PREFIX)onboarding-sandbox-device-install \
	$(TARGET_PREFIX)watch-build $(TARGET_PREFIX)watch-run \
	$(TARGET_PREFIX)localization-check
.PHONY: $(PHONY_TARGETS)

$(TARGET_PREFIX)help:
	@printf "%s\n" \
		"Targets:" \
		"  make $(TARGET_PREFIX)build                    Build with strict flags + logs" \
		"  make $(TARGET_PREFIX)diagnose                 Print toolchain + config info" \
		"  make $(TARGET_PREFIX)test                     Run full non-capture regression gate (TEST_ONLY=, TEST_PARALLEL=NO)" \
		"  make $(TARGET_PREFIX)test-unit                Run only unit tests (seconds; fast iteration loop)" \
		"  make $(TARGET_PREFIX)test-ui-smoke            Run a focused UI smoke subset for fast agent iteration" \
		"  make $(TARGET_PREFIX)test-regression          Alias for the full non-capture regression gate" \
		"  make $(TARGET_PREFIX)test-list                Enumerate default-gate tests and print lane membership" \
		"  make $(TARGET_PREFIX)check-screenshot-policy  Fail if screenshot APIs appear outside capture files" \
		"  make $(TARGET_PREFIX)capture-screenshots      Export reviewed App Store screenshots (CAPTURE_LOCALES=en)" \
		"  make $(TARGET_PREFIX)capture-theme-matrix     Capture theme/tab/light-dark evidence under build/evidence" \
		"  make $(TARGET_PREFIX)test-screenshots         Back-compat alias for capture-screenshots" \
		"  make $(TARGET_PREFIX)test-surface-snapshots   Run surface snapshots and export attachments" \
		"  make $(TARGET_PREFIX)run                      Run app (assumes prior build)" \
		"  make $(TARGET_PREFIX)build-and-run            Build then run" \
		"  make $(TARGET_PREFIX)build-and-run-background Build then run in background" \
		"  make $(TARGET_PREFIX)clean                    Clean derived data + logs" \
		"  make $(TARGET_PREFIX)check-process            Validate canonical docs and spec lifecycle" \
		"  make $(TARGET_PREFIX)check-device-install     Verify device installs exclude simulators/unavailable devices" \
		"  make $(TARGET_PREFIX)check-release-config     Validate release IDs, profiles, entitlements, and watch icon" \
		"  make $(TARGET_PREFIX)release-readiness        Check ASC/profile release gates" \
		"  make $(TARGET_PREFIX)agent-verify             Build and test" \
		"  make $(TARGET_PREFIX)bump-build               Increment native build number" \
		"  make $(TARGET_PREFIX)testflight               Archive and upload current build to TestFlight" \
		"  make $(TARGET_PREFIX)implement-testflight     Verify, bump, and upload TestFlight" \
		"  make $(TARGET_PREFIX)onboarding-sandbox-device-install  Install local-only side-by-side onboarding sandbox"

$(TARGET_PREFIX)diagnose:
ifeq ($(APP_PLATFORM),ios)
	@APP_PROJECT="$(PROJECT)" \
		APP_WORKSPACE="$(WORKSPACE)" \
		APP_BUILD_FILE="$$( [ -n "$(WORKSPACE)" ] && printf "%s" "$(WORKSPACE)" || printf "%s" "$(PROJECT)" )" \
		APP_SCHEME="$(APP_SCHEME)" \
		APP_PLATFORM="$(APP_PLATFORM)" \
		APP_GENERATOR="$(APP_GENERATOR)" \
		APP_DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)" 2>/dev/null || true)" \
		AGENT_NAME="$(AGENT_NAME)" \
		CACHE_ROOT="$(CACHE_ROOT)" \
		TMPDIR="$(TMPDIR_PATH)" \
		$(SCRIPTS_DIR)/diagnose.sh
else
	@APP_PROJECT="$(PROJECT)" \
		APP_WORKSPACE="$(WORKSPACE)" \
		APP_BUILD_FILE="$$( [ -n "$(WORKSPACE)" ] && printf "%s" "$(WORKSPACE)" || printf "%s" "$(PROJECT)" )" \
		APP_SCHEME="$(APP_SCHEME)" \
		APP_PLATFORM="$(APP_PLATFORM)" \
		APP_GENERATOR="$(APP_GENERATOR)" \
		APP_DESTINATION="$(DESTINATION)" \
		AGENT_NAME="$(AGENT_NAME)" \
		CACHE_ROOT="$(CACHE_ROOT)" \
		TMPDIR="$(TMPDIR_PATH)" \
		$(SCRIPTS_DIR)/diagnose.sh
endif

$(TARGET_PREFIX)build:
ifeq ($(APP_PLATFORM),ios)
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action build -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		build
else
	@LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action build -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED) \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		build
endif

$(TARGET_PREFIX)test:
ifeq ($(APP_PLATFORM),ios)
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
			$(TEST_SCOPE_FLAGS) \
			$(TEST_PARALLEL_FLAGS) \
			$(TEST_RETRY_FLAGS) \
			-collect-test-diagnostics on-failure \
			GCC_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_STRICT_CONCURRENCY=complete \
		test
else
	@LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
			-configuration $(CONFIGURATION) \
			-destination '$(DESTINATION)' \
			-derivedDataPath $(DERIVED) \
			-collect-test-diagnostics on-failure \
			GCC_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_STRICT_CONCURRENCY=complete \
		test
endif

# Fast inner loop: unit tests only (GauravaTests, a bundle.unit-test target) — no
# simulator-driven UI suites, so it returns in seconds. Use while iterating; run
# `make agent-verify` once before handoff for the full gate.
$(TARGET_PREFIX)test-unit:
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
			-destination "$$DESTINATION" \
			-derivedDataPath $(DERIVED) \
			-only-testing:GauravaTests \
			-collect-test-diagnostics never \
			GCC_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
			SWIFT_STRICT_CONCURRENCY=complete \
			test

$(TARGET_PREFIX)test-ui-smoke:
ifeq ($(APP_PLATFORM),ios)
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test-ui-smoke -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
		$(UI_SMOKE_SCOPE_FLAGS) \
		$(TEST_PARALLEL_FLAGS) \
		$(TEST_RETRY_FLAGS) \
		-collect-test-diagnostics never \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		test
else
	@echo "test-ui-smoke is only defined for iOS." >&2; exit 2
endif

$(TARGET_PREFIX)test-regression:
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)test

$(TARGET_PREFIX)test-list:
ifeq ($(APP_PLATFORM),ios)
	@printf "%s\n" "Capture-only suites skipped by default:" $(CAPTURE_ONLY_SUITES)
	@printf "%s\n" "UI smoke selectors:" $(UI_SMOKE_TESTS)
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test-list -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(APP_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
		$(TEST_SCOPE_FLAGS) \
		$(TEST_PARALLEL_FLAGS) \
		-enumerate-tests \
		-test-enumeration-style flat \
		-test-enumeration-format text \
		-test-enumeration-output-path - \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		test
else
	@echo "test-list is only defined for iOS." >&2; exit 2
endif

$(TARGET_PREFIX)check-screenshot-policy:
	@python3 $(SCRIPTS_DIR)/check_test_screenshots.py

# Human-reviewed App Store screenshot/marketing capture. This uses the artifact
# exporter, not a raw hidden .xcresult-only test run.
$(TARGET_PREFIX)capture-screenshots:
	@.agents/skills/gaurava-store-screenshots/assets/capture.sh "$(CAPTURE_DEVICE)" "$(CAPTURE_THEME)" "$(CAPTURE_MEDICATION)" $(CAPTURE_LOCALES)

$(TARGET_PREFIX)capture-theme-matrix: $(TARGET_PREFIX)build
	@$(SCRIPTS_DIR)/capture_theme_matrix.sh \
		--app-path "$(APP_PATH)" \
		--sim-name "$(SIM_NAME)" \
		--seed "$(THEME_MATRIX_SEED)" \
		--themes "$(THEME_MATRIX_THEMES)" \
		--appearances "$(THEME_MATRIX_APPEARANCES)" \
		--output-dir "$(THEME_MATRIX_OUTPUT_DIR)"

$(TARGET_PREFIX)test-screenshots: $(TARGET_PREFIX)capture-screenshots

$(TARGET_PREFIX)test-surface-snapshots:
ifeq ($(APP_PLATFORM),ios)
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_sim_destination.sh --sim-name "$(SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No iOS Simulator found."; exit 1; fi; \
	RESULT_BUNDLE="$(LOG_DIR)/test-surface-snapshots.xcresult"; \
	EXPORT_DIR="$(SURFACE_SNAPSHOT_EXPORT_DIR)/$$(date +%Y%m%d-%H%M%S)"; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action test-surface-snapshots -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(SURFACE_SNAPSHOT_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
		-only-testing:$(SURFACE_SNAPSHOT_TEST) \
		-parallel-testing-enabled NO \
		-collect-test-diagnostics on-failure \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		test; \
	mkdir -p "$$EXPORT_DIR"; \
	xcrun xcresulttool export attachments --path "$$RESULT_BUNDLE" --output-path "$$EXPORT_DIR"; \
	printf "Surface snapshot attachments: %s\n" "$$EXPORT_DIR"
else
	@echo "test-surface-snapshots is only defined for iOS." >&2; exit 2
endif

$(TARGET_PREFIX)run:
ifeq ($(APP_PLATFORM),ios)
	@$(SCRIPTS_DIR)/run_app_ios_sim.sh --app-path "$(APP_PATH)" --sim-name "$(SIM_NAME)"
else
	@$(SCRIPTS_DIR)/run_app_macos.sh --app-path "$(APP_PATH)"
endif

$(TARGET_PREFIX)device-install:
	@APP_SCHEME="$(APP_SCHEME)" CONFIGURATION="$(CONFIGURATION)" APPLE_TEAM_ID="$(APPLE_TEAM_ID)" \
		ASC_KEY_ID="$(ASC_KEY_ID)" ASC_ISSUER_ID="$(ASC_ISSUER_ID)" ASC_KEY_PATH="$(ASC_KEY_PATH)" \
		$(SCRIPTS_DIR)/device_install.sh

$(TARGET_PREFIX)onboarding-sandbox-device-install:
	@APP_SCHEME="$(ONBOARDING_SANDBOX_SCHEME)" APP_BUNDLE_ID="$(ONBOARDING_SANDBOX_BUNDLE_ID)" \
		CONFIGURATION="Debug" APPLE_TEAM_ID="$(APPLE_TEAM_ID)" DEVICE_DERIVED="build/onboarding-sandbox-derived" \
		DEVICE_INSTALL_ONLY="$(ONBOARDING_SANDBOX_DEVICE_FILTER)" DEVICE_UNINSTALL_FIRST="1" \
		ASC_KEY_ID="$(ASC_KEY_ID)" ASC_ISSUER_ID="$(ASC_ISSUER_ID)" ASC_KEY_PATH="$(ASC_KEY_PATH)" \
		$(SCRIPTS_DIR)/device_install.sh

# Build the watch app for a watchOS Simulator (Phase 0). The iOS `build` target
# already embeds + compiles the watch targets; this builds the watch scheme
# directly so it can be launched standalone on the watch simulator.
$(TARGET_PREFIX)watch-build:
	@DESTINATION="$$( $(SCRIPTS_DIR)/resolve_watch_destination.sh --sim-name "$(WATCH_SIM_NAME)")"; \
	if [ -z "$$DESTINATION" ]; then echo "No watchOS Simulator found."; exit 1; fi; \
	LOG_DIR="$(LOG_DIR)" CACHE_ROOT="$(CACHE_ROOT)" TMPDIR="$(TMPDIR_PATH)" $(XCBUILD) --label "$(AGENT_NAME)" --action build -- \
		$(BUILD_FILE_FLAG) \
		-scheme $(WATCH_SCHEME) \
		-configuration $(CONFIGURATION) \
		-destination "$$DESTINATION" \
		-derivedDataPath $(DERIVED) \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		build

# Build, install, and launch the watch app on a watchOS Simulator.
$(TARGET_PREFIX)watch-run: $(TARGET_PREFIX)watch-build
	@UDID="$$( $(SCRIPTS_DIR)/resolve_watch_destination.sh --sim-name "$(WATCH_SIM_NAME)" | sed -n 's/.*id=//p')"; \
	if [ -z "$$UDID" ]; then echo "No concrete watchOS Simulator to launch."; exit 1; fi; \
	APP="$(DERIVED)/Build/Products/$(CONFIGURATION)-watchsimulator/Gaurava.app"; \
	if [ ! -d "$$APP" ]; then echo "Watch app not found at $$APP"; exit 1; fi; \
	xcrun simctl bootstatus "$$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$$UDID" || true; \
	xcrun simctl install "$$UDID" "$$APP"; \
	xcrun simctl launch "$$UDID" $(WATCH_BUNDLE_ID)

$(TARGET_PREFIX)build-and-run: $(TARGET_PREFIX)build $(TARGET_PREFIX)run

$(TARGET_PREFIX)build-and-run-background: $(TARGET_PREFIX)build
ifeq ($(APP_PLATFORM),ios)
	@$(SCRIPTS_DIR)/run_app_ios_sim.sh --app-path "$(APP_PATH)" --sim-name "$(SIM_NAME)" --background
else
	@$(SCRIPTS_DIR)/run_app_macos.sh --app-path "$(APP_PATH)" --background
endif

$(TARGET_PREFIX)clean:
	@$(SCRIPTS_DIR)/clean.sh

$(TARGET_PREFIX)check-process:
	@python3 $(SCRIPTS_DIR)/check_process.py

$(TARGET_PREFIX)check-device-install:
	@bash $(SCRIPTS_DIR)/tests/test_device_install.sh

$(TARGET_PREFIX)check-release-config:
	@python3 $(SCRIPTS_DIR)/check_release_config.py \
		--dry-run \
		--team "$(APPLE_TEAM_ID)" \
		--app-bundle-id "$(APP_BUNDLE_ID)" \
		--widget-bundle-id "$(WIDGET_BUNDLE_ID)" \
		--watch-bundle-id "$(WATCH_BUNDLE_ID)" \
		--watch-widget-bundle-id "$(WATCH_WIDGET_BUNDLE_ID)" \
		--release-profile-uuid "$(RELEASE_PROFILE_UUID)" \
		--widget-profile-uuid "$(WIDGET_RELEASE_PROFILE_UUID)" \
		--watch-profile-uuid "$(WATCH_RELEASE_PROFILE_UUID)" \
		--watch-widget-profile-uuid "$(WATCH_WIDGET_RELEASE_PROFILE_UUID)"
ifneq ($(CHECK_RELEASE_CONFIG_DRY_RUN),1)
	@rm -rf "$(RELEASE_CONFIG_DERIVED)"
	@xcodebuild \
		-project "$(APP_PROJECT)" \
		-scheme "$(APP_SCHEME)" \
		-configuration Release \
		-destination "generic/platform=iOS Simulator" \
		-derivedDataPath "$(RELEASE_CONFIG_DERIVED)" \
		CODE_SIGNING_ALLOWED=NO \
		GCC_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_TREAT_WARNINGS_AS_ERRORS=YES \
		SWIFT_STRICT_CONCURRENCY=complete \
		build
	@python3 $(SCRIPTS_DIR)/check_release_config.py \
		--built-watch-app "$(RELEASE_CONFIG_WATCH_APP)" \
		--team "$(APPLE_TEAM_ID)" \
		--app-bundle-id "$(APP_BUNDLE_ID)" \
		--widget-bundle-id "$(WIDGET_BUNDLE_ID)" \
		--watch-bundle-id "$(WATCH_BUNDLE_ID)" \
		--watch-widget-bundle-id "$(WATCH_WIDGET_BUNDLE_ID)" \
		--release-profile-uuid "$(RELEASE_PROFILE_UUID)" \
		--widget-profile-uuid "$(WIDGET_RELEASE_PROFILE_UUID)" \
		--watch-profile-uuid "$(WATCH_RELEASE_PROFILE_UUID)" \
		--watch-widget-profile-uuid "$(WATCH_WIDGET_RELEASE_PROFILE_UUID)"
endif

$(TARGET_PREFIX)release-readiness:
	@set -eu; \
	printf "Checking %s release readiness...\n" "$(APP_NAME)"; \
	printf "ASC app ID: %s\n" "$(ASC_APP_ID)"; \
	printf "Internal TestFlight group: %s\n" "$(ASC_TESTFLIGHT_GROUP)"; \
	if [ -z "$(ASC_APP_ID)" ]; then \
		printf "BLOCKED: ASC_APP_ID is missing.\n"; \
		exit 1; \
	fi; \
	if [ ! -f "$(RELEASE_PROFILE_PATH)" ]; then \
		printf "BLOCKED: provisioning profile is not installed at %s\n" "$(RELEASE_PROFILE_PATH)"; \
		exit 1; \
	fi; \
	profile_plist="$$(mktemp)"; \
	trap 'rm -f "$$profile_plist"' EXIT; \
	security cms -D -i "$(RELEASE_PROFILE_PATH)" > "$$profile_plist"; \
	profile_name="$$(/usr/libexec/PlistBuddy -c 'Print :Name' "$$profile_plist")"; \
	profile_uuid="$$(/usr/libexec/PlistBuddy -c 'Print :UUID' "$$profile_plist")"; \
	bundle_entitlement="$$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$$profile_plist" 2>/dev/null || true)"; \
	container_ids="$$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-identifiers' "$$profile_plist" 2>/dev/null || true)"; \
	dev_container_ids="$$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.icloud-container-development-container-identifiers' "$$profile_plist" 2>/dev/null || true)"; \
	ubiquity_container_ids="$$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.ubiquity-container-identifiers' "$$profile_plist" 2>/dev/null || true)"; \
	printf "Profile: %s (%s)\n" "$$profile_name" "$$profile_uuid"; \
	printf "Application entitlement: %s\n" "$$bundle_entitlement"; \
	if [ "$$profile_uuid" != "$(RELEASE_PROFILE_UUID)" ]; then \
		printf "BLOCKED: expected profile UUID %s, got %s\n" "$(RELEASE_PROFILE_UUID)" "$$profile_uuid"; \
		exit 1; \
	fi; \
	if ! printf "%s\n" "$$container_ids" | grep -F "$(CLOUDKIT_CONTAINER)" >/dev/null; then \
		printf "BLOCKED: profile production CloudKit containers do not include %s.\n" "$(CLOUDKIT_CONTAINER)"; \
		printf "Attach the container to com.nags.gaurava, regenerate the profile, and rerun this check before archive/upload.\n"; \
		exit 2; \
	fi; \
	if ! printf "%s\n" "$$dev_container_ids" | grep -F "$(CLOUDKIT_CONTAINER)" >/dev/null; then \
		printf "BLOCKED: profile development CloudKit containers do not include %s.\n" "$(CLOUDKIT_CONTAINER)"; \
		printf "Attach the container to com.nags.gaurava, regenerate the profile, and rerun this check before archive/upload.\n"; \
		exit 2; \
	fi; \
	if ! printf "%s\n" "$$ubiquity_container_ids" | grep -F "$(CLOUDKIT_CONTAINER)" >/dev/null; then \
		printf "BLOCKED: profile ubiquity containers do not include %s.\n" "$(CLOUDKIT_CONTAINER)"; \
		printf "Attach the container to com.nags.gaurava, regenerate the profile, and rerun this check before archive/upload.\n"; \
		exit 2; \
	fi; \
	printf "CloudKit and ubiquity containers are present in the release profile.\n"

$(TARGET_PREFIX)agent-verify:
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)check-process
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)check-device-install
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)check-release-config CHECK_RELEASE_CONFIG_DRY_RUN=1
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)check-screenshot-policy
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)build
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)test
	@python3 $(SCRIPTS_DIR)/check_localization.py lint
	@python3 $(SCRIPTS_DIR)/check_localization.py catalog --strict

# Localization hygiene: ban raw String(localized:)/NSLocalizedString in the app
# UI (so every label switches with the in-app picker) and report catalog gaps.
$(TARGET_PREFIX)localization-check:
	@python3 $(SCRIPTS_DIR)/check_localization.py

$(TARGET_PREFIX)bump-build:
	@CURRENT="$$(awk -F': ' '/CURRENT_PROJECT_VERSION:/ {print $$2; exit}' project.yml | tr -d '"')"; \
	case "$$CURRENT" in ''|*[!0-9]*) echo "Could not read numeric CURRENT_PROJECT_VERSION from project.yml" >&2; exit 2;; esac; \
	NEXT=$$((CURRENT + 1)); \
	perl -0pi -e "s/CURRENT_PROJECT_VERSION: $$CURRENT/CURRENT_PROJECT_VERSION: $$NEXT/g" project.yml; \
	if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate >/dev/null; \
	else \
		perl -0pi -e "s/CURRENT_PROJECT_VERSION = $$CURRENT;/CURRENT_PROJECT_VERSION = $$NEXT;/g" Gaurava.xcodeproj/project.pbxproj; \
	fi; \
	echo "Bumped iOS build $$CURRENT -> $$NEXT"

$(TARGET_PREFIX)testflight: $(TARGET_PREFIX)check-release-config $(TARGET_PREFIX)release-readiness
	@if ! command -v asc >/dev/null 2>&1; then echo "Missing required command: asc" >&2; exit 2; fi
	@mkdir -p "$(dir $(IOS_ARCHIVE_PATH))" "$(IOS_EXPORT_PATH)"
	@xcodebuild \
		-project "$(APP_PROJECT)" \
		-scheme "$(APP_SCHEME)" \
		-configuration Release \
		-destination "generic/platform=iOS" \
		-archivePath "$(IOS_ARCHIVE_PATH)" \
		DEVELOPMENT_TEAM="$(APPLE_TEAM_ID)" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="Apple Distribution" \
		clean archive
	@/usr/libexec/PlistBuddy -c "Clear dict" "$(IOS_EXPORT_OPTIONS)" 2>/dev/null || true
	@/usr/libexec/PlistBuddy -c "Add :destination string export" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :method string app-store-connect" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :signingStyle string manual" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :teamID string $(APPLE_TEAM_ID)" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$(APP_BUNDLE_ID) string $(RELEASE_PROFILE_SPECIFIER)" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$(WIDGET_BUNDLE_ID) string $(WIDGET_RELEASE_PROFILE_SPECIFIER)" "$(IOS_EXPORT_OPTIONS)"
	@# Watch app + watch widget profiles (Phase 1). Guarded: only mapped once the
	@# watch distribution profiles exist and the *_RELEASE_PROFILE_SPECIFIER vars
	@# are set, so the iOS-only export path stays unchanged in Phase 0.
	@if [ -n "$(WATCH_RELEASE_PROFILE_SPECIFIER)" ]; then \
		/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$(WATCH_BUNDLE_ID) string $(WATCH_RELEASE_PROFILE_SPECIFIER)" "$(IOS_EXPORT_OPTIONS)"; \
	fi
	@if [ -n "$(WATCH_WIDGET_RELEASE_PROFILE_SPECIFIER)" ]; then \
		/usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$(WATCH_WIDGET_BUNDLE_ID) string $(WATCH_WIDGET_RELEASE_PROFILE_SPECIFIER)" "$(IOS_EXPORT_OPTIONS)"; \
	fi
	@/usr/libexec/PlistBuddy -c "Add :stripSwiftSymbols bool true" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :testFlightInternalTestingOnly bool $(TESTFLIGHT_INTERNAL_TESTING_ONLY)" "$(IOS_EXPORT_OPTIONS)"
	@/usr/libexec/PlistBuddy -c "Add :uploadSymbols bool true" "$(IOS_EXPORT_OPTIONS)"
	@xcodebuild \
		-exportArchive \
		-archivePath "$(IOS_ARCHIVE_PATH)" \
		-exportPath "$(IOS_EXPORT_PATH)" \
		-exportOptionsPlist "$(IOS_EXPORT_OPTIONS)"
	@if [ ! -f "$(IOS_IPA_PATH)" ]; then echo "IPA not found at $(IOS_IPA_PATH)" >&2; exit 2; fi
	@asc publish testflight \
		--app "$(ASC_APP_ID)" \
		--ipa "$(IOS_IPA_PATH)" \
		--group "$(ASC_TESTFLIGHT_GROUP)" \
		--wait \
		--output "$(ASC_OUTPUT)"

$(TARGET_PREFIX)implement-testflight:
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)agent-verify
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)bump-build
	@$(MAKE) --no-print-directory $(TARGET_PREFIX)testflight
