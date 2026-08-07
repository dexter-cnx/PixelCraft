import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class CameraFilmPreset {
  const CameraFilmPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.matrix,
  });

  final String id;
  final String name;
  final String description;
  final List<double> matrix;

  bool get isOriginal => id.isEmpty;

  ColorFilter colorFilter(double strength) => ColorFilter.matrix(
        interpolateColorMatrix(matrix, strength.clamp(0.0, 1.0)),
      );
}

const identityColorMatrix = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

List<double> interpolateColorMatrix(List<double> target, double strength) {
  assert(target.length == identityColorMatrix.length);
  return List<double>.generate(
    identityColorMatrix.length,
    (index) => lerpDouble(identityColorMatrix[index], target[index], strength)!,
    growable: false,
  );
}

/// Lightweight live-camera approximations of the Film Profile Pack v2 looks.
///
/// These matrices are intentionally used only for the camera viewfinder. The
/// accepted capture stays unmodified and Pixel Craft applies the selected
/// profile through the Rust 33³ LUT pipeline once the Editor opens.
const cameraFilmPresets = <CameraFilmPreset>[
  CameraFilmPreset(
    id: '',
    name: 'Original',
    description: 'Unfiltered camera preview',
    matrix: identityColorMatrix,
  ),
  CameraFilmPreset(
    id: 'provia_inspired',
    name: 'Provia Inspired',
    description: 'Balanced color with a clean slide-film feel',
    matrix: <double>[
      1.06, -0.02, -0.01, 0, -2,
      -0.01, 1.05, -0.01, 0, -1,
      -0.01, -0.01, 1.04, 0, -1,
      0, 0, 0, 1, 0,
    ],
  ),
  CameraFilmPreset(
    id: 'velvia_inspired',
    name: 'Velvia Inspired',
    description: 'Vivid saturation and deeper contrast',
    matrix: <double>[
      1.18, -0.06, -0.03, 0, -5,
      -0.04, 1.16, -0.03, 0, -4,
      -0.03, -0.04, 1.14, 0, -4,
      0, 0, 0, 1, 0,
    ],
  ),
  CameraFilmPreset(
    id: 'astia_inspired',
    name: 'Astia Inspired',
    description: 'Soft contrast with gentle warm skin tones',
    matrix: <double>[
      1.04, 0.01, -0.01, 0, 2,
      0.00, 1.01, 0.00, 0, 1,
      -0.01, 0.01, 0.98, 0, 2,
      0, 0, 0, 1, 0,
    ],
  ),
  CameraFilmPreset(
    id: 'e100_inspired',
    name: 'E100 Inspired',
    description: 'Neutral slide color with restrained saturation',
    matrix: <double>[
      1.03, -0.01, 0.00, 0, -1,
      -0.01, 1.04, -0.01, 0, -1,
      0.00, -0.01, 1.06, 0, 0,
      0, 0, 0, 1, 0,
    ],
  ),
  CameraFilmPreset(
    id: 'ektar_inspired',
    name: 'Ektar Inspired',
    description: 'Punchy warm color with strong reds and blues',
    matrix: <double>[
      1.16, -0.04, -0.02, 0, 1,
      -0.03, 1.08, -0.01, 0, -3,
      -0.01, -0.03, 1.13, 0, -2,
      0, 0, 0, 1, 0,
    ],
  ),
  CameraFilmPreset(
    id: 'chrome64_inspired',
    name: 'Chrome 64 Inspired',
    description: 'Warm nostalgic chrome with softened blues',
    matrix: <double>[
      1.09, 0.01, -0.02, 0, 4,
      0.00, 1.02, 0.00, 0, 1,
      -0.02, 0.01, 0.94, 0, -1,
      0, 0, 0, 1, 0,
    ],
  ),
];
