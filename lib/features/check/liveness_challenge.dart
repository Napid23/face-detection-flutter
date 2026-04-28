import 'dart:math' as math;

import 'package:google_ml_kit/google_ml_kit.dart';

/// Simple liveness challenge:
/// - Observe eyes open
/// - Observe blink (eyes closed then open again)
/// - Observe smile
///
/// Notes:
/// - Requires FaceDetectorOptions(enableClassification: true)
/// - For best results, use FaceDetectorMode.accurate.
class LivenessChallenge {
  LivenessChallenge({
    this.eyeOpenThreshold = 0.65,
    this.eyeClosedThreshold = 0.20,
    this.smileThreshold = 0.70,
    this.yawThresholdDegrees = 18,
    this.resetIfNoFaceFor = const Duration(seconds: 2),
    this.maxChallengeTime = const Duration(seconds: 12),
  });

  final double eyeOpenThreshold;
  final double eyeClosedThreshold;
  final double smileThreshold;
  final double yawThresholdDegrees;
  final Duration resetIfNoFaceFor;
  final Duration maxChallengeTime;

  DateTime? _startedAt;
  DateTime? _lastFaceAt;

  int? _trackingId;

  bool _sawEyesOpen = false;
  bool _sawEyesClosedAfterOpen = false;
  bool _blinkCompleted = false;
  bool _smileCompleted = false;
  bool _turnLeftCompleted = false;
  bool _turnRightCompleted = false;

  bool get isPassed =>
      _blinkCompleted && _smileCompleted && _turnLeftCompleted && _turnRightCompleted;

  String get prompt {
    if (isPassed) return 'Challenge terpenuhi.';
    if (!_blinkCompleted) return 'Tantangan 1/3: kedipkan mata';
    if (!_smileCompleted) return 'Tantangan 2/3: tersenyum';
    if (!_turnLeftCompleted || !_turnRightCompleted) {
      final parts = <String>[];
      if (!_turnLeftCompleted) parts.add('kiri');
      if (!_turnRightCompleted) parts.add('kanan');
      return 'Tantangan 3/3: noleh ${parts.join(' & ')}';
    }
    return 'Tantangan: kedip, senyum, noleh';
  }

  void reset() {
    _startedAt = null;
    _lastFaceAt = null;
    _trackingId = null;
    _sawEyesOpen = false;
    _sawEyesClosedAfterOpen = false;
    _blinkCompleted = false;
    _smileCompleted = false;
    _turnLeftCompleted = false;
    _turnRightCompleted = false;
  }

  /// Update state from the current [face].
  ///
  /// Returns true if challenge passed.
  bool update(Face face) {
    final now = DateTime.now();
    _startedAt ??= now;
    _lastFaceAt = now;

    // Reset if the tracked face changes (if trackingId is available).
    final tid = face.trackingId;
    if (_trackingId != null && tid != null && tid != _trackingId) {
      reset();
      _startedAt = now;
      _lastFaceAt = now;
      _trackingId = tid;
    } else {
      _trackingId ??= tid;
    }

    // Reset if it takes too long (avoid "stuck" state).
    final startedAt = _startedAt;
    if (startedAt != null && now.difference(startedAt) > maxChallengeTime) {
      reset();
      _startedAt = now;
      _lastFaceAt = now;
      _trackingId ??= tid;
    }

    // Enforce order: blink -> smile -> head turns.
    if (!_blinkCompleted) {
      final eyesOpenProb = _eyesOpenProbability(face);
      if (eyesOpenProb != null) {
        if (eyesOpenProb > eyeOpenThreshold) {
          _sawEyesOpen = true;
          if (_sawEyesClosedAfterOpen) {
            _blinkCompleted = true; // closed -> open
          }
        } else if (_sawEyesOpen && eyesOpenProb < eyeClosedThreshold) {
          _sawEyesClosedAfterOpen = true; // open -> closed
        }
      }
      return isPassed;
    }

    if (!_smileCompleted) {
      final smileProb = face.smilingProbability;
      if (smileProb != null && smileProb > smileThreshold) {
        _smileCompleted = true;
      }
      return isPassed;
    }

    // Head turn challenge (yaw): face.headEulerAngleY
    final yaw = face.headEulerAngleY;
    if (yaw != null) {
      if (yaw <= -yawThresholdDegrees) {
        _turnLeftCompleted = true;
      } else if (yaw >= yawThresholdDegrees) {
        _turnRightCompleted = true;
      }
    }

    return isPassed;
  }

  /// Call periodically when you have no faces in frame.
  void onNoFace() {
    final last = _lastFaceAt;
    if (last == null) return;
    if (DateTime.now().difference(last) > resetIfNoFaceFor) {
      reset();
    }
  }

  double? _eyesOpenProbability(Face face) {
    final l = face.leftEyeOpenProbability;
    final r = face.rightEyeOpenProbability;
    if (l == null && r == null) return null;
    if (l == null) return r;
    if (r == null) return l;
    // Use the "most closed" eye for stricter blink detection.
    return math.min(l, r);
  }
}
