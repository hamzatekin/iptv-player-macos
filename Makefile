DERIVED := .build/xcode
APP := $(DERIVED)/Build/Products/Debug/IPTVPlayer.app

.PHONY: gen build test run clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project IPTVPlayer.xcodeproj -scheme IPTVPlayer -configuration Debug \
		-derivedDataPath $(DERIVED) -skipPackagePluginValidation build -quiet
	./scripts/sign.sh $(APP)

test:
	cd Packages/IPTVCore && swift test

# Launches the app fresh and follows its log ($TMPDIR/iptvplayer-run.log). A .env file (gitignored) can hold
# IPTV_SERVER, IPTV_USERNAME, IPTV_PASSWORD (used while no login is saved) and IPTV_MPV_LOG (mpv log level).
run: build
	./scripts/run.sh

clean:
	rm -rf $(DERIVED) IPTVPlayer.xcodeproj
