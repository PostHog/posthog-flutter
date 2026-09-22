import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'main.dart' show exampleReplayConfig;

/// A wallet-style screen for trying `sessionReplayConfig.textMaskPolicy`.
///
/// Every value on this screen is a plain `Text`, a `RichText`, or a text
/// input, so the policy picker at the top shows exactly which glyphs each
/// policy masks in the captured replay frame.
class TextMaskPolicyScreen extends StatefulWidget {
  const TextMaskPolicyScreen({super.key});

  @override
  State<TextMaskPolicyScreen> createState() => _TextMaskPolicyScreenState();
}

enum _Policy { off, digits, reveal, custom }

class _TextMaskPolicyScreenState extends State<TextMaskPolicyScreen> {
  _Policy _policy = _Policy.digits;
  late final _amount = TextEditingController(text: '25,000');
  late final _note = TextEditingController(text: 'Rent for flat 402');
  late final _email = TextEditingController(text: 'ada@example.com');

  static final _email$ = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _digits$ = RegExp(r'\d[\d.,\- ]*\d|\d');

  @override
  void initState() {
    super.initState();
    _apply(_policy);
  }

  @override
  void dispose() {
    exampleReplayConfig?.textMaskPolicy = null;
    _amount.dispose();
    _note.dispose();
    _email.dispose();
    super.dispose();
  }

  void _apply(_Policy policy) {
    exampleReplayConfig?.textMaskPolicy = switch (policy) {
      _Policy.off => null,
      _Policy.digits => PostHogTextMaskPolicies.digits(),
      _Policy.reveal => PostHogTextMaskPolicies.reveal(
        RegExp(r'\b(Total balance|Send money|Recent|VISA|EXP|NGN)\b'),
      ),
      _Policy.custom => (text, widget) => PostHogTextMask.only([
        for (final m in _email$.allMatches(text))
          TextRange(start: m.start, end: m.end),
        for (final m in _digits$.allMatches(text))
          TextRange(start: m.start, end: m.end),
      ]),
    };
    setState(() => _policy = policy);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Text mask policy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Policy>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Policy.off, label: Text('Off')),
              ButtonSegment(value: _Policy.digits, label: Text('Digits')),
              ButtonSegment(value: _Policy.reveal, label: Text('Reveal')),
              ButtonSegment(value: _Policy.custom, label: Text('Custom')),
            ],
            selected: {_policy},
            onSelectionChanged: (s) => _apply(s.single),
          ),
          const SizedBox(height: 8),
          Text(switch (_policy) {
            _Policy.off => 'No policy: maskAllTexts decides.',
            _Policy.digits =>
              'PostHogTextMaskPolicies.digits(): numbers masked, words kept.',
            _Policy.reveal =>
              'PostHogTextMaskPolicies.reveal(...): only listed labels kept.',
            _Policy.custom => 'Custom policy: emails and numbers masked.',
          }, style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          _BalanceCard(),
          const SizedBox(height: 16),
          _PaymentCard(),
          const SizedBox(height: 24),
          Text('Recent', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final tx in _transactions) _TransactionRow(tx),
          const SizedBox(height: 24),
          Text('Send money', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (NGN)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Recipient email (sensitive input, always masked)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B2A86), Color(0xFF1B6CA8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total balance',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          RichText(
            text: const TextSpan(
              style: TextStyle(color: Colors.white),
              children: [
                TextSpan(text: '₦', style: TextStyle(fontSize: 22)),
                TextSpan(
                  text: '2,450,000',
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '.00', style: TextStyle(fontSize: 22)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Ada Lovelace · Account 0123456789',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 4),
          const Text(
            'ada.lovelace@example.com · +234 801 234 5678',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          const Text(
            'Updated 2 min ago',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'VISA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              Text('Debit', style: TextStyle(color: Colors.white70)),
            ],
          ),
          SizedBox(height: 28),
          Text(
            '4111 1111 1111 1111',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              letterSpacing: 2,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ADA LOVELACE', style: TextStyle(color: Colors.white)),
              Text('EXP 09/28', style: TextStyle(color: Colors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Transaction {
  const _Transaction(this.merchant, this.date, this.amount, this.icon);

  final String merchant;
  final String date;
  final String amount;
  final IconData icon;
}

const _transactions = [
  _Transaction('Ikeja Electric', '12 Sep 2026', '-₦12,500.00', Icons.bolt),
  _Transaction('Salary · Roqqu', '10 Sep 2026', '+₦850,000.00', Icons.work),
  _Transaction('Transfer to Bob', '9 Sep 2026', '-₦40,000.00', Icons.send),
  _Transaction('Netflix', '1 Sep 2026', '-₦7,000.00', Icons.tv),
];

class _TransactionRow extends StatelessWidget {
  const _TransactionRow(this.tx);

  final _Transaction tx;

  @override
  Widget build(BuildContext context) {
    final credit = tx.amount.startsWith('+');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(child: Icon(tx.icon)),
      title: Text(tx.merchant),
      subtitle: Text(tx.date),
      trailing: Text.rich(
        TextSpan(
          text: tx.amount,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: credit ? Colors.green.shade700 : null,
          ),
        ),
      ),
    );
  }
}
