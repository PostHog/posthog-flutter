.PHONY: formatKotlin formatSwift formatDart checkDart installLinters

installLinters:
	brew install ktlint
	brew install swiftformat

formatKotlin:
	ktlint --format --baseline=ktlint-baseline.xml

# swiftlint ios/Classes --fix conflicts with swiftformat
formatSwift:
	swiftformat ios/Classes --swiftversion 5.3

formatDart:
	dart format .

checkFormatDart:
	dart format --set-exit-if-changed ./

analyzeDart:
	dart analyze .
