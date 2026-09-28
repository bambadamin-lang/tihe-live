/// JSON plumbing for the contract mirror. The shapes themselves are defined once, in
/// packages/contracts (zod); these Dart classes mirror them and are checked against the shared
/// fixtures in test/contracts_conformance_test.dart.
typedef Json = Map<String, Object?>;

Json asJson(Object? value) => (value as Map).cast<String, Object?>();

List<Json> asJsonList(Object? value) => [
  for (final item in value as List) asJson(item),
];

List<T> listOf<T>(Object? value) => (value as List).cast<T>();

/// Thrown when a message does not match the contract — a server or client out of date.
class ContractError implements Exception {
  ContractError(this.message);
  final String message;

  @override
  String toString() => 'ContractError: $message';
}

T byWire<T extends Enum>(
  List<T> values,
  Object? wire,
  String Function(T) wireOf,
) {
  for (final v in values) {
    if (wireOf(v) == wire) return v;
  }
  throw ContractError('unknown value "$wire" for $T');
}
