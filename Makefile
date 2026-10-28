.PHONY: app build run test clean

app:
	./Scripts/build-app.sh

build:
	./Scripts/build-app.sh

run: app
	open dist/SwiftNX.app

test:
	swift test

clean:
	swift package clean
	rm -rf dist
