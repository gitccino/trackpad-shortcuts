.PHONY: build test
build:
	bash scripts/build.sh

test:
	@mkdir -p build
	$(CC) -std=c11 -Wall -Wextra -Werror -pedantic Sources/Gesture.c Tests/GestureTests.c -lm -o build/gesture-tests
	./build/gesture-tests
