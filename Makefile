SCHEME  := Horizon
PROJECT := Horizon.xcodeproj
SIM_DEST := generic/platform=iOS Simulator

.PHONY: help gen open build simulator clean ship ship-mac

help:
	@echo "Horizon — make targets"
	@echo "  make gen        Regenerate $(PROJECT) from project.yml"
	@echo "  make open       gen + open in Xcode"
	@echo "  make build      Compile for iOS Simulator (no signing)"
	@echo "  make simulator  Boot sim + build"
	@echo "  make clean      Wipe DerivedData"
	@echo "  make ship       Archive + upload iOS to TestFlight"
	@echo "  make ship-mac   Archive + upload Mac (Catalyst) to TestFlight"

gen:
	xcodegen generate

open: gen
	open $(PROJECT)

build: gen
	xcodebuild build \
	  -scheme $(SCHEME) \
	  -project $(PROJECT) \
	  -destination '$(SIM_DEST)' \
	  -configuration Debug \
	  CODE_SIGNING_ALLOWED=NO

simulator: gen
	xcrun simctl boot 'iPhone 16 Pro' 2>/dev/null || true
	open -a Simulator
	xcodebuild build \
	  -scheme $(SCHEME) \
	  -project $(PROJECT) \
	  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
	  CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf ~/Library/Developer/Xcode/DerivedData/Horizon-*

ship:
	./scripts/upload-testflight.sh

ship-mac:
	./scripts/upload-testflight-mac.sh
