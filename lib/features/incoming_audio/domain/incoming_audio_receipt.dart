class IncomingAudioReceipt {
  final String id;
  final int copiedCount;
  final int failedCount;
  final int ignoredCount;

  const IncomingAudioReceipt({
    required this.id,
    required this.copiedCount,
    required this.failedCount,
    required this.ignoredCount,
  });

  factory IncomingAudioReceipt.fromMap(Map<Object?, Object?> map) {
    return IncomingAudioReceipt(
      id: map['id'] as String,
      copiedCount: map['copiedCount'] as int? ?? 0,
      failedCount: map['failedCount'] as int? ?? 0,
      ignoredCount: map['ignoredCount'] as int? ?? 0,
    );
  }
}
