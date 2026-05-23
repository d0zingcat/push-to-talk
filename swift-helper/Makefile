.PHONY: build clean

SOURCES := $(wildcard *.swift)

build:
	swiftc $(SOURCES) -target arm64-apple-macosx11.0 -framework Carbon -framework CoreGraphics -framework AppKit -framework SwiftUI -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist -o ../assets/pushtotalk-arm64
	swiftc $(SOURCES) -target x86_64-apple-macosx11.0 -framework Carbon -framework CoreGraphics -framework AppKit -framework SwiftUI -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist -o ../assets/pushtotalk-x86_64
	lipo -create ../assets/pushtotalk-arm64 ../assets/pushtotalk-x86_64 -output ../assets/pushtotalk
	rm -f ../assets/pushtotalk-arm64 ../assets/pushtotalk-x86_64
	mkdir -p ../assets/PushToTalk.app/Contents/MacOS
	cp ../assets/pushtotalk ../assets/PushToTalk.app/Contents/MacOS/PushToTalk
	cp Info.plist ../assets/PushToTalk.app/Contents/Info.plist
	mkdir -p ../assets/PushToTalk.app/Contents/Resources
	cp AppIcon.icns ../assets/PushToTalk.app/Contents/Resources/AppIcon.icns

clean:
	rm -f ../assets/pushtotalk ../assets/pushtotalk-arm64 ../assets/pushtotalk-x86_64
	rm -rf ../assets/PushToTalk.app
