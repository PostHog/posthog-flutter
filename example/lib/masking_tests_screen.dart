import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Screen for testing various masking scenarios
class MaskingTestsScreen extends StatefulWidget {
  const MaskingTestsScreen({super.key});

  @override
  State<MaskingTestsScreen> createState() => _MaskingTestsScreenState();
}

class _MaskingTestsScreenState extends State<MaskingTestsScreen> {
  final TextEditingController _singleLineController = TextEditingController();
  final TextEditingController _multiLineController = TextEditingController();

  @override
  void dispose() {
    _singleLineController.dispose();
    _multiLineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Masking Tests'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                'Masking Test Cases',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Test 1: Simple Text
              _buildTestSection(
                'Test 1: Simple Text',
                const Text(
                  'This text should be fully masked when maskAllTexts is enabled',
                  style: TextStyle(fontSize: 16, color: Colors.black),
                ),
              ),

              // Test 2: RichText masking
              _buildTestSection(
                'Test 2: RichText',
                RichText(
                  text: const TextSpan(
                    style: TextStyle(fontSize: 16, color: Colors.black),
                    children: [
                      TextSpan(text: 'This is '),
                      TextSpan(
                        text: 'sensitive data',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      TextSpan(text: ' that should be masked.'),
                    ],
                  ),
                ),
              ),

              // Test 3: SelectableText masking
              _buildTestSection(
                'Test 3: SelectableText',
                const SelectableText(
                  'This SelectableText should also be masked',
                  style: TextStyle(fontSize: 14, color: Colors.blue),
                ),
              ),

              // Test 4: Scaled Text with Transform.scale
              _buildTestSection(
                'Test 4: Transform.scale (1.5x)',
                Transform.scale(
                  scale: 1.5,
                  child: const Text(
                    'Scaled 1.5x text',
                    style: TextStyle(fontSize: 14, color: Colors.purple),
                  ),
                ),
              ),

              // Test 5: Rotated Text
              _buildTestSection(
                'Test 5: Transform.rotate',
                Transform.rotate(
                  angle: math.pi / 12, // 15 degrees
                  child: const Text(
                    'Rotated text (15°)',
                    style: TextStyle(fontSize: 14, color: Colors.orange),
                  ),
                ),
              ),

              // Test 6: Image without transform
              _buildTestSection(
                'Test 6: Network Image (no transform)',
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'https://picsum.photos/200/100',
                    width: 150,
                    height: 75,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      width: 150,
                      height: 75,
                      color: Colors.grey[300],
                      child: const Icon(Icons.image, size: 40),
                    ),
                  ),
                ),
              ),

              // Test 7: Scaled Image with Transform.scale
              _buildTestSection(
                'Test 7: Image with Transform.scale (1.3x)',
                Transform.scale(
                  scale: 1.3,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      'https://picsum.photos/150/80',
                      width: 100,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Container(
                        width: 100,
                        height: 50,
                        color: Colors.blue[100],
                        child: const Icon(Icons.photo, size: 30),
                      ),
                    ),
                  ),
                ),
              ),

              // Test 8: Rotated Image
              _buildTestSection(
                'Test 8: Image with Transform.rotate',
                Transform.rotate(
                  angle: math.pi / 8, // 22.5 degrees
                  child: Image.network(
                    'https://picsum.photos/100/100',
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      width: 80,
                      height: 80,
                      color: Colors.green[100],
                      child: const Icon(Icons.rotate_right, size: 30),
                    ),
                  ),
                ),
              ),

              // Test 9: Combined Scale + Rotate
              _buildTestSection(
                'Test 9: Scale + Rotate combined',
                Transform.rotate(
                  angle: -math.pi / 10,
                  child: Transform.scale(
                    scale: 1.2,
                    child: const Text(
                      'Scaled & Rotated',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ),
              ),

              // Test 10: Single-line TextField
              _buildTestSection(
                'Test 10: Single-line TextField',
                TextField(
                  controller: _singleLineController,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Enter single line text...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              // Test 11: Multiline TextField
              _buildTestSection(
                'Test 11: Multiline TextField (3 lines)',
                TextField(
                  controller: _multiLineController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Enter multiline text...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),

              // Test 12: Dense TextField (potential layout issue)
              _buildTestSection(
                'Test 12: Dense TextField (isDense: true)',
                const TextField(
                  style: TextStyle(fontSize: 16),
                  decoration: InputDecoration(
                    hintText: 'Dense input field...',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ),

              // Test 13: PostHogMaskWidget manual masking
              _buildTestSection(
                'Test 13: PostHogMaskWidget',
                const PostHogMaskWidget(
                  child: Text(
                    'This is manually masked with PostHogMaskWidget',
                    style: TextStyle(fontSize: 14, color: Colors.indigo),
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestSection(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Center(child: child),
        ],
      ),
    );
  }
}
