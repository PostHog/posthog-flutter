.PHONY: format formatKotlin formatSwift formatDart checkDart installLinters test testDart

format: formatSwift formatKotlin formatDart

installLinters:
	brew install ktlint
	brew install swiftformat

formatKotlin:
	ktlint --format --baseline=posthog_flutter/ktlint-baseline.xml posthog_flutter/android/**/*.kt

# swiftlint ios/Classes --fix conflicts with swiftformat
formatSwift:
	swiftformat posthog_flutter/ios/Classes --swiftversion 5.3

formatDart:
	dart format .

checkFormatDart:
	dart format --set-exit-if-changed ./

analyzeDart:
	@output=$$(dart analyze . 2>&1); \
	echo "$$output"; \
	filtered=$$(echo "$$output" | grep -v "invalid_dependency"); \
	if echo "$$filtered" | grep -q " error -"; then \
		exit 1; \
	fi

test: 
	cd posthog_flutter && flutter test -r expanded

testDart:
	cd posthog_dart && dart test -r expanded

testAll: test testDart
