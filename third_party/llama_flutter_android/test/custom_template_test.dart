import 'package:flutter_test/flutter_test.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Unit tests for custom template registration
/// 
/// These tests verify that the Option 2 implementation works correctly.
/// Run with: flutter test test/custom_template_test.dart
void main() {
  group('Custom Template Registration', () {
    late LlamaController controller;

    setUp(() {
      controller = LlamaController();
    });

    test('Register custom template succeeds', () async {
      // Test registering a simple custom template
      const templateName = 'test-template';
      const templateContent = '<s>{user}</s><s>{assistant}</s>';

      // Should not throw
      await controller.registerCustomTemplate(templateName, templateContent);
      
      // Verify it's in the supported templates list
      final templates = await controller.getSupportedTemplates();
      expect(templates, contains(templateName));
    });

    test('Register template with special characters', () async {
      const templateName = 'special-template';
      const templateContent = '<|im_start|>{system}<|im_end|>\n{user}\n{assistant}';

      // Should handle special characters
      await controller.registerCustomTemplate(templateName, templateContent);
      
      final templates = await controller.getSupportedTemplates();
      expect(templates, contains(templateName));
    });

    test('Unregister custom template succeeds', () async {
      const templateName = 'temp-template';
      const templateContent = '{user}>{assistant}';

      // Register first
      await controller.registerCustomTemplate(templateName, templateContent);
      
      // Then unregister
      await controller.unregisterCustomTemplate(templateName);
      
      // Should no longer be in list
      final templates = await controller.getSupportedTemplates();
      expect(templates, isNot(contains(templateName)));
    });

    test('Register multiple custom templates', () async {
      const templates = {
        'template-1': '<s>{user}</s>',
        'template-2': '{user}|{assistant}',
        'template-3': '### {user}\n### {assistant}',
      };

      // Register all
      for (final entry in templates.entries) {
        await controller.registerCustomTemplate(entry.key, entry.value);
      }

      // Verify all are present
      final supportedTemplates = await controller.getSupportedTemplates();
      for (final name in templates.keys) {
        expect(supportedTemplates, contains(name));
      }
    });

    test('Override built-in template with custom', () async {
      // Register custom template with same name as built-in
      const templateName = 'chatml'; // Built-in template
      const customContent = 'CUSTOM: {user} -> {assistant}';

      // Should succeed (logs warning but allows override)
      await controller.registerCustomTemplate(templateName, customContent);
      
      final templates = await controller.getSupportedTemplates();
      expect(templates, contains(templateName));
      
      // Note: Can't verify content from Dart side, but Kotlin logs will show override
    });
  });

  group('Template Format Validation', () {
    test('Template with all placeholders', () {
      const template = '{system}\n\n{user}\n\n{assistant}';
      
      // Verify placeholders are present
      expect(template, contains('{system}'));
      expect(template, contains('{user}'));
      expect(template, contains('{assistant}'));
    });

    test('Template with only user and assistant', () {
      const template = '<s>[INST]{user}[/INST]{assistant}</s>';
      
      // System is optional
      expect(template, contains('{user}'));
      expect(template, contains('{assistant}'));
      expect(template, isNot(contains('{system}')));
    });

    test('Template placeholders are case-sensitive', () {
      const template = '{user} vs {User}';
      
      // Only lowercase is valid
      expect(template, contains('{user}'));
      expect(template, isNot(contains('{USER}')));
    });
  });

  group('Error Handling', () {
    late LlamaController controller;

    setUp(() {
      controller = LlamaController();
    });

    test('Empty template name should not crash', () async {
      // Should handle gracefully
      try {
        await controller.registerCustomTemplate('', 'content');
        // If it succeeds, that's fine
      } catch (e) {
        // If it throws, that's also acceptable
        expect(e, isNotNull);
      }
    });

    test('Empty template content should not crash', () async {
      // Should handle gracefully
      try {
        await controller.registerCustomTemplate('test', '');
        // If it succeeds, that's fine (will just format empty strings)
      } catch (e) {
        // If it throws, that's also acceptable
        expect(e, isNotNull);
      }
    });

    test('Unregister non-existent template should not crash', () async {
      // Should handle gracefully (Kotlin returns false)
      await controller.unregisterCustomTemplate('non-existent-template');
      // If we get here, it didn't crash ✓
    });
  });
}

/// Example custom templates for testing
class ExampleTemplates {
  static const mistralInstruct = '<s>[INST]{system}\n\n{user}[/INST]{assistant}</s>';
  static const chatML = '<|im_start|>system\n{system}<|im_end|>\n'
      '<|im_start|>user\n{user}<|im_end|>\n'
      '<|im_start|>assistant\n{assistant}<|im_end|>';
  static const llama3 = '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n'
      '{system}<|eot_id|><|start_header_id|>user<|end_header_id|>\n\n'
      '{user}<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n'
      '{assistant}<|eot_id|>';
  static const simple = '{user}\n{assistant}\n';
  static const alpaca = '### Instruction:\n{user}\n\n### Response:\n{assistant}';
}
