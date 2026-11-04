// Generates the SDK reference Markdown from the doc comments with dartdoc_modern.
//
// dartdoc_modern renders one page per class. This script keeps the members it
// documents, groups them under the PostHog/sdk-specs capability named by a
// `posthog-capability: <slug>` doc comment line, and writes the front matter.
//
//     dart pub global activate dartdoc_modern 1.1.7
//     dart scripts/generate-markdown-reference.dart --sdk-specs DIR [--major 5]
import 'dart:io';

final root = File.fromUri(Platform.script).parent.parent.path;
final pkg = '$root/posthog_flutter';
// Public client classes get their own H2; every other public type goes in Types.
final clients = {
  ...'PostHogLogger PosthogObserver PostHogWidget PostHogMaskWidget PostHogUnmaskWidget PostHogPlatformView PostHogIsolateExtension'
      .split(' ')
};
const first = ['setup', 'capture', 'identify'];
const acronyms = {'id': 'ID', 'ai': 'AI', 'http': 'HTTP', 'mcp': 'MCP'};
final tagRe = RegExp(r'^[ \t]*posthog-capability:[ \t]*([a-z0-9-]+)[ \t]*$\n?',
    multiLine: true);

class Member {
  Member(this.heading);
  final String heading;
  final lines = <String>[];
  bool get skip => RegExp(r'text="(inherited|override)"').hasMatch(heading);
  bool get isExtension => heading.contains('text="extension"');
  bool get isCtor => heading.contains('{#ctor-');
  String get name => heading
      .replaceAll(RegExp(r'<Badge[^>]*/>|~~|\{#.*\}|^#+'), '')
      .trim()
      .replaceFirst(RegExp(r'\(\)$'), '');
}

class Doc {
  String name = '';
  // Enums list the `name` extension member, which isn't ours.
  bool get isExtension => intro.any((l) => l.contains('>extension<'));
  Iterable<Member> get public =>
      members.where((m) => !m.skip && (!m.isExtension || isExtension));
  final intro = <String>[];
  final members = <Member>[];
}

/// Splits a dartdoc_modern page into its description and its members.
Doc parse(String text) {
  final doc = Doc();
  Member? cur;
  var fence = false, inSection = false, operators = false;
  for (final l
      in text.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '').split('\n')) {
    if (l.startsWith('```')) fence = !fence;
    if (!fence && l.startsWith('# ')) {
      doc.name = l.substring(2).trim();
    } else if (!fence && l.startsWith('## ')) {
      inSection = true;
      cur = null;
      operators = l.startsWith('## Operators');
    } else if (!fence && l.startsWith('### ')) {
      cur = Member(l);
      if (!operators) doc.members.add(cur);
    } else if (cur != null) {
      cur.lines.add(l);
    } else if (!inSection) {
      doc.intro.add(l);
    }
  }
  return doc;
}

String unescape(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

/// The signature is HTML with one span per line. Render it as a Dart fence.
String signature(String html) {
  final lines = html
      .split('<span class="member-signature-line">')
      .skip(1)
      .map((l) => unescape(l.replaceAll(RegExp(r'<[^>]+>'), ''))
          .replaceAll(RegExp(r'([\[{(]) '), r'$1'))
      .toList();
  for (var i = 1; i < lines.length - 1; i++) {
    lines[i] = '  ${lines[i]}';
  }
  return '```dart\n${lines.join('\n')}\n```';
}

/// Drops dartdoc_modern's VitePress syntax. The site reads Markdown as MDX 1.
String clean(String s) {
  s = s.replaceAllMapped(
      RegExp(r'<div class="member-signature">.*</div></div>'),
      (m) => signature(m[0]!));
  s = s.replaceAll(RegExp(r':::details[\s\S]*?\n:::\n?'), '');
  s = s.replaceAllMapped(RegExp(r':::(\w+)[^\n]*\n([\s\S]*?)\n:::\n?'), (m) {
    if (m[1] != 'warning') return '';
    return '> **Deprecated.** ${m[2]!.replaceAll('\n', '\n> ')}\n';
  });
  // Links into the other generated pages point at anchors this page doesn't have.
  s = s.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((?:/api/|\./)[^)]*\)'), (m) => m[1]!);
  s = s.replaceAll(tagRe, '').replaceAll('<br>', '<br />');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Braces and angle brackets outside code are JSX in MDX 1, so escape them.
String mdx(String s) {
  final out = StringBuffer();
  var fence = false;
  for (final l in s.split('\n')) {
    if (l.startsWith('```')) fence = !fence;
    if (fence || l.startsWith('```')) {
      out.writeln(l);
      continue;
    }
    out.writeln(l.splitMapJoin(RegExp(r'`[^`]*`'),
        onMatch: (m) => m[0]!,
        onNonMatch: (t) => t
            .replaceAllMapped(RegExp(r'[{}]'), (m) => '\\${m[0]}')
            .replaceAllMapped(
                RegExp(r'<(?=[A-Za-z/])(?!br />)'), (m) => '&lt;')));
  }
  return out.toString().trimRight();
}

String body(Iterable<String> lines) => clean(lines.join('\n'));

/// The capability tags are the first thing read, so they are stripped by `clean` afterwards.
String? tagOf(Member m) => tagRe.firstMatch(m.lines.join('\n'))?[1];

/// Each sdk-specs capability's slug and sentence-case title, in the README's order.
Map<String, String> capabilities(String checkout) {
  final readme = File('$checkout/README.md').readAsStringSync();
  final rows = RegExp(
          r'^\| ([^|]+?) \| \[`openspec/specs/([a-z0-9-]+)/spec\.md`\]',
          multiLine: true)
      .allMatches(readme)
      .map((m) => MapEntry(
          m[2]!,
          m[1]!
              .split(' ')
              .map((w) => acronyms[w.toLowerCase()] ?? w.toLowerCase())
              .join(' ')))
      .toList();
  final order = [
    ...first,
    ...rows.map((r) => r.key).where((s) => !first.contains(s))
  ];
  final titles = {for (final r in rows) r.key: r.value};
  return {
    for (final s in order)
      if (titles.containsKey(s))
        s: titles[s]![0].toUpperCase() + titles[s]!.substring(1)
  };
}

String frontMatter(String title, List<String> sections) {
  final toc = [
    for (final h in sections
        .where((s) => s.startsWith('## '))
        .map((s) => s.split('\n').first.substring(3)))
      '  - value: "$h"\n    url: ${h.toLowerCase().replaceAll(RegExp(r'[^\w\- ]'), '').replaceAll(' ', '-')}\n    depth: 0'
  ];
  return [
    '---',
    'title: "$title"',
    'sidebar: Docs',
    'showTitle: true',
    'contentMaxWidthClass: max-w-full',
    'platformLogo: flutter',
    'tableOfContents:',
    ...toc,
    '---',
  ].join('\n');
}

/// Moves each heading down one level and drops the H1. Code stays as written.
String nest(String markdown) {
  var fence = false;
  return markdown
      .trim()
      .split('\n')
      .where((l) => !l.startsWith('# ') || fence)
      .map((l) {
    if (l.startsWith('```')) fence = !fence;
    return !fence && RegExp(r'#{1,5} ').hasMatch(l) ? '#$l' : l;
  }).join('\n');
}

List<String> reference(Map<String, Doc> docs, Map<String, String> caps) {
  final client = docs.remove('Posthog')!;
  String entry(String level, String cls, Member m) =>
      '$level ${m.isCtor ? '`${m.name}()`' : '`$cls.${m.name}`'}\n\n${body(m.lines)}';
  final members = client.public.toList();
  final out = <String>[];
  for (final MapEntry(key: slug, value: title) in caps.entries) {
    final tagged = members.where((m) => tagOf(m) == slug);
    if (tagged.isNotEmpty)
      out.addAll(
          ['## $title', ...tagged.map((m) => entry('###', 'Posthog', m))]);
  }
  out.addAll([
    '## SDK utils',
    ...members
        .where((m) => tagOf(m) == null)
        .map((m) => entry('###', 'Posthog', m))
  ]);
  for (final name in clients.where(docs.containsKey).toList()..sort()) {
    final d = docs[name]!;
    out.addAll([
      '## ${d.name}',
      body(d.intro),
      ...d.public.map((m) => entry('###', d.name, m))
    ]);
  }
  out.add('## Types');
  for (final d in docs.values.where((d) => !clients.contains(d.name))) {
    out.addAll([
      '### `${d.name}`',
      body(d.intro),
      ...d.public.map((m) => entry('####', d.name, m))
    ]);
  }
  return out.map(mdx).toList();
}

void write(String name, List<String> sections) {
  Directory('$root/references').createSync();
  File('$root/references/$name')
      .writeAsStringSync('${sections.join('\n\n')}\n');
  print('wrote references/$name');
}

void main(List<String> args) {
  final specs = args.indexOf('--sdk-specs');
  if (specs < 0) {
    stderr.writeln(
        'Usage: dart scripts/generate-markdown-reference.dart --sdk-specs DIR [--major N]');
    exit(64);
  }
  final declared = int.parse(RegExp(r'^version: (\d+)', multiLine: true)
      .firstMatch(File('$pkg/pubspec.yaml').readAsStringSync())![1]!);
  final majorArg = args.indexOf('--major');
  final major = majorArg < 0 ? declared : int.parse(args[majorArg + 1]);
  final out = Directory.systemTemp.createTempSync('posthog-flutter-docs').path;
  final run = Process.runSync(
      'dart',
      [
        'pub',
        'global',
        'run',
        'dartdoc_modern',
        '--format',
        'vitepress',
        '--output',
        out
      ],
      workingDirectory: pkg);
  if (run.exitCode != 0) {
    stderr.write(run.stderr);
    exit(run.exitCode);
  }
  final docs = {
    for (final f in Directory('$out/api/posthog_flutter')
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('index.md')))
      f.uri.pathSegments.last.replaceFirst('.md', ''):
          parse(f.readAsStringSync()),
  };
  final started =
      nest(File('$root/docs/getting-started.md').readAsStringSync());
  final sections = [
    '## Getting started',
    started,
    ...reference(docs, capabilities(args[specs + 1]))
  ];
  final suffix = declared >= major ? '' : ' (experimental)';
  write('posthog-flutter-$major.md', [
    frontMatter('PostHog Flutter SDK $major.x$suffix', sections),
    ...sections
  ]);
  if (declared >= major)
    write('posthog-flutter-reference.md',
        [frontMatter('PostHog Flutter SDK', sections), ...sections]);
  Directory(out).deleteSync(recursive: true);
}
