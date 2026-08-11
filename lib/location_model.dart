import 'package:latlong2/latlong.dart';

class CampusLocation {
  final String name;
  final double latitude;
  final double longitude;
  final List<LatLng> polygonPoints;

  const CampusLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.polygonPoints,
  });

  static final List<CampusLocation> psuLocations = [
    CampusLocation(
      name: 'Gymnasium',
      latitude: 9.7788,
      longitude: 118.7325,
      polygonPoints: [
        LatLng(9.779094, 118.732641), // L1: Top Left
        LatLng(9.779089, 118.733028), // L2: Top Right
        LatLng(9.778777, 118.733028), // L4: Bottom Right
        LatLng(9.778780, 118.732652), // L3: Bottom Left
      ],
    ),
  ];
}