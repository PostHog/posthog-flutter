import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'error_example.dart';

/// Manual testing for [Posthog.addExceptionStep].
///
/// Exception steps are buffered breadcrumbs that the embedded native SDK
/// attaches to the next `$exception` event as `$exception_steps`. Use the
/// buttons to seed steps, then trigger an exception and confirm the steps ride
/// along on the captured event in PostHog.
class ExceptionStepsScreen extends StatefulWidget {
  const ExceptionStepsScreen({super.key});

  @override
  State<ExceptionStepsScreen> createState() => _ExceptionStepsScreenState();
}

class _ExceptionStepsScreenState extends State<ExceptionStepsScreen> {
  static const _exampleChannel = MethodChannel('posthog_flutter_example');
  final _posthog = Posthog();
  final List<String> _log = [];

  void _note(String message) {
    setState(() => _log.insert(0, message));
  }

  Future<void> _addSingleStep() async {
    final at = DateTime.now().toIso8601String();
    await _posthog.addExceptionStep('Manual breadcrumb at $at');
    _note('Added 1 step');
  }

  Future<void> _addBatchWithMixedProperties() async {
    await _posthog.addExceptionStep('App launched test flow');
    await _posthog.addExceptionStep(
      'User tapped Checkout',
      properties: {
        'screen': 'cart',
        'item_count': 3,
        'total': 42.5,
        'is_member': true,
        'at': DateTime.now(),
        'tags': ['promo', 'first_order'],
        'meta': {'experiment': 'b'},
      },
    );
    await _posthog.addExceptionStep(
      'Network request started',
      properties: {'url': 'https://example.com/pay', 'method': 'POST'},
    );
    _note('Added 3 steps (mixed properties)');
  }

  /// High-frequency flood meant to exceed the default 32 KB byte budget so the
  /// native FIFO buffer evicts the oldest steps; only the most recent survive.
  Future<void> _floodSteps() async {
    const total = 300;
    final payload = 'x' * 128;
    for (var i = 0; i < total; i++) {
      await _posthog.addExceptionStep(
        'Flood step $i',
        properties: {'iteration': i, 'payload': payload},
      );
    }
    _note('Flooded $total steps (oldest should be evicted)');
  }

  Future<void> _stepsThenHandledException() async {
    await _addBatchWithMixedProperties();
    await ErrorExample().causeHandledDivisionError();
    _note('Captured handled exception — check \$exception_steps');
  }

  Future<void> _stepsThenUnhandledError() async {
    await _addBatchWithMixedProperties();
    _note('Throwing unhandled error — check \$exception_steps');
    // Distinct type from the handled path's IntegerDivisionByZeroException so
    // this surfaces as its own issue in PostHog.
    throw const UnhandledExceptionStepsError(
      'Unhandled error from the Exception Steps screen',
    );
  }

  Future<void> _stepsThenNativeCrash() async {
    await _addBatchWithMixedProperties();
    _note('Crashing — steps should survive and attach on next launch');
    await Future.delayed(const Duration(seconds: 1));
    await _exampleChannel.invokeMethod('triggerNativeCrash');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exception Steps')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _section('Add steps'),
              ElevatedButton(
                onPressed: _addSingleStep,
                child: const Text('Add single step'),
              ),
              ElevatedButton(
                onPressed: _addBatchWithMixedProperties,
                child: const Text('Add 3 steps (mixed properties)'),
              ),
              ElevatedButton(
                onPressed: _floodSteps,
                child: const Text('Flood 300 steps (high-frequency)'),
              ),
              _section('Trigger exception — steps should attach'),
              ElevatedButton(
                onPressed: _stepsThenHandledException,
                child: const Text('Steps → handled exception'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _stepsThenUnhandledError,
                child: const Text('Steps → unhandled Flutter error'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                onPressed: _stepsThenNativeCrash,
                child: const Text('Steps → native crash (will crash app!)'),
              ),
              const Divider(),
              const Text('Activity', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final entry in _log)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(entry),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
}

/// Thrown by the "unhandled Flutter error" test so it groups as its own issue in
/// PostHog, separate from the handled path's IntegerDivisionByZeroException.
class UnhandledExceptionStepsError implements Exception {
  const UnhandledExceptionStepsError(this.message);

  final String message;

  @override
  String toString() => 'UnhandledExceptionStepsError: $message';
}
