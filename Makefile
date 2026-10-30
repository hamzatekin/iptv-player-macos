DERIVED := .build/xcode

.PHONY: gen build test run clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project IPTVPlayer.xcodeproj -scheme IPTVPlayer -configuration Debug \
		-derivedDataPath $(DERIVED) -skipPackagePluginValidation build -quiet

test:
	cd Packages/IPTVCore && swift test

# Launches the app fresh and follows its log ($TMPDIR/iptvplayer-run.log). A .env file (gitignored) can hold
# IPTV_SERVER, IPTV_USERNAME, IPTV_PASSWORD and IPTV_MPV_LOG (mpv log level) for debug runs.
run: build
	./scripts/run.sh

clean:
	rm -rf $(DERIVED) IPTVPlayer.xcodeproj
