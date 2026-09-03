.PHONY: build install test open

build:
	./scripts/build.sh

install:
	./scripts/install.sh

test: build
	./build/Diff.app/Contents/MacOS/Diff --self-test

open:
	OPEN_AFTER_INSTALL=1 ./scripts/install.sh
