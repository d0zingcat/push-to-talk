.PHONY: build clean

ROOT := ..
SOURCE_ROOT := $(ROOT)/Sources/PushToTalk
RESOURCE_ROOT := $(SOURCE_ROOT)/Resources
DIST := $(ROOT)/dist
SOURCES := $(shell find $(SOURCE_ROOT) -name '*.swift' | sort)

build:
	mkdir -p $(DIST)
	swiftc $(SOURCES) -target arm64-apple-macosx11.0 -framework Carbon -framework CoreGraphics -framework AppKit -framework SwiftUI -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(RESOURCE_ROOT)/Info.plist -o $(DIST)/pushtotalk-arm64
	swiftc $(SOURCES) -target x86_64-apple-macosx11.0 -framework Carbon -framework CoreGraphics -framework AppKit -framework SwiftUI -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker $(RESOURCE_ROOT)/Info.plist -o $(DIST)/pushtotalk-x86_64
	lipo -create $(DIST)/pushtotalk-arm64 $(DIST)/pushtotalk-x86_64 -output $(DIST)/pushtotalk
	rm -f $(DIST)/pushtotalk-arm64 $(DIST)/pushtotalk-x86_64
	mkdir -p $(DIST)/PushToTalk.app/Contents/MacOS
	cp $(DIST)/pushtotalk $(DIST)/PushToTalk.app/Contents/MacOS/PushToTalk
	cp $(RESOURCE_ROOT)/Info.plist $(DIST)/PushToTalk.app/Contents/Info.plist
	mkdir -p $(DIST)/PushToTalk.app/Contents/Resources
	cp $(RESOURCE_ROOT)/AppIcon.icns $(DIST)/PushToTalk.app/Contents/Resources/AppIcon.icns

clean:
	rm -f $(DIST)/pushtotalk $(DIST)/pushtotalk-arm64 $(DIST)/pushtotalk-x86_64
	rm -rf $(DIST)/PushToTalk.app $(DIST)/dmg_stage $(DIST)/PushToTalk.dmg $(DIST)/PushToTalk.zip
