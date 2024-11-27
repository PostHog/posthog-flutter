.PHONY: formatKotlin formatSwift formatDart checkDart

# brew install ktlint
formatKotlin:
	ktlint --format --baseline=ktlint-baseline.xml

# brew install swiftlint
# TODO: add swiftlint steps in CI
formatSwift:
	swiftformat ios/Classes --swiftversion 5.3
	swiftlint ios/Classes --fix

formatDart:
	dart format .

checkFormatDart:
	dart format --set-exit-if-changed ./

analyzeDart:
	dart analyze .
