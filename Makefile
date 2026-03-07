.PHONY: format formatKotlin formatSwift formatDart checkDart installLinters test

format: formatSwift formatKotlin formatDart

installLinters:
	brew install ktlint
	brew install swiftformat

formatKotlin:
	ktlint --format --baseline=posthog_flutter/ktlint-baseline.xml posthog_flutter/android/**/*.kt

# swiftlint darwin/posthog_flutter/Sources --fix conflicts with swiftformat
formatSwift:
	swiftformat posthog_flutter/darwin/posthog_flutter/Sources/posthog_flutter --swiftversion 5.3

formatDart:
	dart format .

checkFormatDart:
	dart format --set-exit-if-changed ./

analyzeDart:
	dart analyze .

test: 
	cd posthog_flutter && flutter test -r expanded
