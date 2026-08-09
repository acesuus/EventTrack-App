import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GeofencingService {
  static DateTime? _lastAttemptTime;
  static int _failedAttempts = 0;
  static DateTime? _lockoutEndTime;

  static Future<bool> _isEnvironmentSecure(Position position) async {
    // TODO: Re-enable mock location block before production
    // if (position.isMocked) {
    //   return false;
    // }

    if (!kIsWeb) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        if (!androidInfo.isPhysicalDevice) return false;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        if (!iosInfo.isPhysicalDevice) return false;
      }
    }
    return true;
  }

  /// Validates if a student's current position is inside the event's polygon geofence.
  /// Uses the Ray-Casting (Point-in-Polygon) algorithm.
  static Future<bool> isStudentInsideEvent(Position studentPos, Map<String, dynamic> eventCoords, {bool useMock = false, Position? mockPosition}) async {
    final now = DateTime.now();

    if (_lockoutEndTime != null && _lockoutEndTime!.isAfter(now)) {
      throw Exception('SECURITY_VIOLATION: Too many failed attempts. Account temporarily locked.');
    }

    if (_lastAttemptTime != null && now.difference(_lastAttemptTime!) < const Duration(seconds: 2)) {
      throw Exception('SECURITY_VIOLATION: Request throttled. Please wait before trying again.');
    }
    _lastAttemptTime = now;

    if (useMock) {
      // Fallback mock position defaults to Gymnasium if no specific mock is provided
      studentPos = mockPosition ?? Position(
        latitude: 9.7785,
        longitude: 118.7328,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 0.0,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        altitudeAccuracy: 0.0,
        headingAccuracy: 0.0,
      );
      debugPrint("GeofencingService: Using MOCK position (Lat: ${studentPos.latitude}, Lng: ${studentPos.longitude})");
    }

    if (!(await _isEnvironmentSecure(studentPos))) {
      throw Exception('SECURITY_VIOLATION: Environment integrity compromised. Emulators and Mock Locations are strictly prohibited.');
    }

    try {
      // Extract the polygon points saved by the Admin during event creation
      final rawPoints = eventCoords['polygonPoints'] as List<dynamic>?;

      // Graceful fallback: A valid polygon requires at least 3 points (a triangle)
      if (rawPoints == null || rawPoints.length < 3) {
        debugPrint("GeofencingService: Missing or invalid polygon coordinates.");
        return false;
      }

      int intersectCount = 0;
      
      // Treat Latitude as Y and Longitude as X for the 2D Cartesian plane
      double pointLat = studentPos.latitude;  // Y
      double pointLng = studentPos.longitude; // X

      // Ray-Casting Algorithm: Perfectly handles N-sided polygons (like the 8-sided Amphitheater)
      for (int i = 0; i < rawPoints.length; i++) {
        int j = (i + 1) % rawPoints.length; // Connect the last point back to the first

        final Map<String, dynamic> v1 = Map<String, dynamic>.from(rawPoints[i]);
        final Map<String, dynamic> v2 = Map<String, dynamic>.from(rawPoints[j]);

        double v1Lat = (v1['lat'] as num).toDouble(); // v1.Y
        double v1Lng = (v1['lng'] as num).toDouble(); // v1.X
        double v2Lat = (v2['lat'] as num).toDouble(); // v2.Y
        double v2Lng = (v2['lng'] as num).toDouble(); // v2.X

        // 1. Check if the point's Y (Lat) is bounded by the edge's Y-coordinates
        if (((v1Lat > pointLat) != (v2Lat > pointLat))) {
          // 2. Calculate the X (Lng) intersection of the ray with the edge
          double intersectLng = v1Lng + (pointLat - v1Lat) * (v2Lng - v1Lng) / (v2Lat - v1Lat);
          
          // 3. If the intersection is to the right of the point, the ray crossed the edge
          if (pointLng < intersectLng) {
            intersectCount++;
          }
        }
      }

      // If the number of intersections is Odd, the point is INSIDE the polygon.
      bool isInside = (intersectCount % 2 != 0);

      if (isInside) {
        _failedAttempts = 0;
      } else {
        _failedAttempts++;
        if (_failedAttempts >= 3) {
          _lockoutEndTime = now.add(const Duration(seconds: 30));
        }
      }

      return isInside;
    } catch (e) {
      debugPrint("GeofencingService Error calculating bounds: $e");
      return false; // Fail securely by marking them outside if data is corrupted
    }
  }
}