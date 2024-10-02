.PHONY: formatKotlin formatSwift formatDart

# brew install ktlint
# TODO: add ktlint steps in CI
formatKotlin:
	ktlint --format

# brew install swiftlint
# TODO: add swiftlint steps in CI
formatSwift:
	swiftformat ios/Classes --swiftversion 5.3
	swiftlint ios/Classes --fix

formatDart:
	dart format .
	dart analyze .
