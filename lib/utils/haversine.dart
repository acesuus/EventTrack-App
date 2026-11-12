import 'dart:math' show cos, sqrt, asin, sin, pi;

class HaversineUtils {
  /// Calculates the great-circle distance between two points on the Earth's surface
  /// using the Haversine formula.
  /// Returns the distance in meters.
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000.0; // Earth radius in meters

    // Convert degrees to radians
    double dLat = (lat2 - lat1) * (pi / 180.0);
    double dLon = (lon2 - lon1) * (pi / 180.0);

    double rLat1 = lat1 * (pi / 180.0);
    double rLat2 = lat2 * (pi / 180.0);

    // Haversine formula
    double a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(rLat1) * cos(rLat2);
    
    double c = 2 * asin(sqrt(a));
    double distance = earthRadius * c;

    print('User Lat: $lat1, Lng: $lon1');
    print('Target Lat: $lat2, Lng: $lon2');
    print('Calculated Distance: $distance meters');

    return distance;
  }
}
