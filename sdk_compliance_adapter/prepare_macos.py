#!/usr/bin/env python3
"""Create an isolated native Flutter runner without changing SDK manifests."""
import argparse
from pathlib import Path
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
destination = args.destination.resolve()
if destination.exists():
    raise SystemExit('Destination must not exist (builds are isolated).')
destination.mkdir(parents=True)
for package in ('posthog_flutter', 'sdk_compliance_adapter'):
    shutil.copytree(root / package, destination / package,
                    ignore=shutil.ignore_patterns('.dart_tool', 'build', '.build', '.swiftpm'))
(destination / 'pubspec.yaml').write_text('''name: compliance_workspace
publish_to: none
environment:
  sdk: '>=3.6.0 <4.0.0'
workspace:
  - posthog_flutter
  - sdk_compliance_adapter
  - runner
''')
subprocess.run(['flutter', 'create', '--empty', '--no-pub', '--platforms=macos',
                '--project-name=flutter_compliance', '--org=com.posthog.compliance',
                str(destination / 'runner')], check=True)
runner = destination / 'runner'
(runner / 'pubspec.yaml').write_text('''name: flutter_compliance
publish_to: none
resolution: workspace
environment:
  sdk: '>=3.6.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  posthog_flutter_sdk_compliance_adapter:
    path: ../sdk_compliance_adapter
flutter:
  uses-material-design: true
''')
(runner / 'lib/main.dart').write_text('''import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:posthog_flutter_sdk_compliance_adapter/adapter_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  final adapter = ComplianceAdapter();
  await adapter.start(
    port: int.parse(Platform.environment['PORT'] ?? '18310'),
    proxyPort: int.parse(Platform.environment['PROXY_PORT'] ?? '19311'),
  );
}
''')
# The compliance runner needs inbound control traffic and outbound mock traffic.
# Disable the app sandbox only in this generated test application.
for entitlements in (runner / 'macos/Runner').glob('*.entitlements'):
    entitlements.write_text('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.cs.allow-jit</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
</dict></plist>
''')
info = runner / 'macos/Runner/Info.plist'
with info.open('rb') as stream:
    plist = plistlib.load(stream)
plist['com.posthog.posthog.AUTO_INIT'] = False
with info.open('wb') as stream:
    plistlib.dump(plist, stream)
# Keep dependency resolution on CocoaPods, irrespective of machine-wide SPM settings.
manifest = runner / 'pubspec.yaml'
manifest.write_text(manifest.read_text().replace('flutter:\n  uses-material-design:',
    'flutter:\n  config:\n    enable-swift-package-manager: false\n  uses-material-design:'))
print(destination)
