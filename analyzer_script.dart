import 'dart:convert';
import 'dart:io';

void main() {
  final result = Process.runSync('dart', ['analyze', '--format=machine'], runInShell: true);
  final lines = LineSplitter.split(result.stdout.toString()).toList();
  final errors = lines.where((l) => l.contains('ERROR')).toList();
  File('dart_errors.txt').writeAsStringSync(errors.join('\n'));
}
