APP = dist/TwentyTwo.app
DMG = dist/TwentyTwo.dmg

build: $(APP)

dist: $(DMG)

$(DMG): build
	cd dist && make

$(APP):
	. .codesign
	xcodebuild -project TwentyTwo.xcodeproj -target TwentyTwo -configuration Release CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" CONFIGURATION_BUILD_DIR=dist DWARF_DSYM_FOLDER_PATH=build/Release

run: build
	open $(APP)

.PHONY: clean
clean: dist-clean
	-rm -rf $(APP)

.PHONY: dist-clean
dist-clean:
	cd dist && make clean
