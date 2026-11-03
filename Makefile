.PHONY: build test test-macos
build:
	bash scripts/build.sh

test:
	@mkdir -p build
	$(CC) -std=c11 -Wall -Wextra -Werror -pedantic Sources/Gesture.c Tests/GestureTests.c -lm -o build/gesture-tests
	./build/gesture-tests
	$(CC) -std=c11 -Wall -Wextra -Werror -pedantic Sources/Gesture.c Sources/CursorPolicy.c Tests/CursorPolicyTests.c -lm -o build/cursor-policy-tests
	./build/cursor-policy-tests
	@if [ "$$(uname -s)" = Darwin ]; then $(MAKE) test-macos; fi

test-macos:
	@mkdir -p build
	xcrun clang -std=c11 -Wall -Wextra -Werror -framework ApplicationServices Sources/Gesture.c Sources/CursorPolicy.c Tests/CursorEventFilterTests.c -o build/cursor-event-tests
	./build/cursor-event-tests
	xcrun clang -std=c11 -Wall -Wextra -Werror -framework CoreGraphics Tests/WindowLayoutTests.c -o build/window-layout-tests
	./build/window-layout-tests
	xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation Sources/SessionLog.m Tests/SessionLogTests.m -o build/session-log-tests
	./build/session-log-tests
	xcrun clang -fobjc-arc -Wall -Wextra -Werror -framework Foundation Sources/Trackpad.m Sources/Gesture.c Tests/TrackpadReplayTests.m -o build/trackpad-replay-tests
	./build/trackpad-replay-tests
