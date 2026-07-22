.PHONY: build test release app dmg clean

build:
	swift build

test:
	swift test

release:
	swift build -c release

app:
	./Scripts/build-app.sh

dmg: app
	./Scripts/package-dmg.sh

clean:
	swift package clean
	rm -rf build
