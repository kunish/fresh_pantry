import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/_persistence_queue.dart';

class _Subject with PersistenceQueue {
  Future<void> queue(Future<void> Function() w) => queuePersistence(w);
}

void main() {
  group('PersistenceQueue', () {
    test('serializes writes', () async {
      final subject = _Subject();
      final order = <String>[];
      final f1 = subject.queue(() async {
        await Future.delayed(const Duration(milliseconds: 30));
        order.add('a');
      });
      final f2 = subject.queue(() async {
        order.add('b'); // would normally complete first since no delay
      });
      await Future.wait([f1, f2]);
      expect(order, ['a', 'b']);
    });

    test('failure does not block subsequent writes', () async {
      final subject = _Subject();
      final order = <String>[];
      // first throws
      final f1 = subject.queue(() async => throw StateError('boom'));
      // second succeeds
      final f2 = subject.queue(() async => order.add('after-failure'));
      // wait for f2 specifically (f1 swallows internally)
      await f2;
      expect(order, ['after-failure']);
      // f1 should also complete (not pending forever)
      await f1.timeout(const Duration(milliseconds: 100));
    });
  });
}
