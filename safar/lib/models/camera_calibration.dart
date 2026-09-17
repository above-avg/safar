// Camera Calibration Models (Intrinsics & Extrinsics)
// Corresponding to files/calibration.py and files/config.yaml

import 'dart:math' as math;

class CameraIntrinsics {
  final double fx;
  final double fy;
  final double cx;
  final double cy;
  final List<double> dist; // k1, k2, p1, p2, k3

  const CameraIntrinsics({
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    this.dist = const [0.0, 0.0, 0.0, 0.0, 0.0],
  });

  factory CameraIntrinsics.fromFovGuess(int width, int height, {double hfovDeg = 67.0}) {
    final double f = (width / 2.0) / math.tan((hfovDeg * math.pi / 180.0) / 2.0);
    return CameraIntrinsics(
      fx: f,
      fy: f,
      cx: width / 2.0,
      cy: height / 2.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'fx': fx,
    'fy': fy,
    'cx': cx,
    'cy': cy,
    'dist': dist,
  };
}

class CameraExtrinsics {
  final double heightM; // Camera height above road surface (e.g. 1.40 m)
  final double pitchDeg; // Positive = nose down
  final double rollDeg;
  final double yawDeg;
  final String source; // ar_plane | vanishing_point | marking_prior | manual

  const CameraExtrinsics({
    required this.heightM,
    required this.pitchDeg,
    this.rollDeg = 0.0,
    this.yawDeg = 0.0,
    this.source = 'manual',
  });

  double get pitchRad => pitchDeg * math.pi / 180.0;
  double get rollRad => rollDeg * math.pi / 180.0;
  double get yawRad => yawDeg * math.pi / 180.0;

  CameraExtrinsics copyWith({
    double? heightM,
    double? pitchDeg,
    double? rollDeg,
    double? yawDeg,
    String? source,
  }) {
    return CameraExtrinsics(
      heightM: heightM ?? this.heightM,
      pitchDeg: pitchDeg ?? this.pitchDeg,
      rollDeg: rollDeg ?? this.rollDeg,
      yawDeg: yawDeg ?? this.yawDeg,
      source: source ?? this.source,
    );
  }

  Map<String, dynamic> toJson() => {
    'height_m': heightM,
    'pitch_deg': pitchDeg,
    'roll_deg': rollDeg,
    'yaw_deg': yawDeg,
    'source': source,
  };
}
