import 'biometric_model.dart';

/// [Dev B] Bộ đệm cửa sổ trượt (Sliding Window Buffer) lưu 256 mẫu gia tốc (5.12s @ 50Hz)
class AccelBuffer {
  static const int windowSize = 256;
  final List<ImuSample> _samples = [];

  void addSample(ImuSample sample) {
    if (_samples.length >= windowSize) {
      _samples.removeAt(0);
    }
    _samples.add(sample);
  }

  bool get isFull => _samples.length == windowSize;

  List<ImuSample> get currentWindow => List.unmodifiable(_samples);

  void clear() => _samples.clear();
}
