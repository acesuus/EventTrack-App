import 'package:latlong2/latlong.dart';

class PSUCampus {
  final String name;
  final double latitude;
  final double longitude;
  final List<LatLng> polygonPoints;

  const PSUCampus({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.polygonPoints,
  });

  static final List<PSUCampus> locations = [
    PSUCampus(
      name: 'HOME TEST ZONE',
      latitude: 9.732500,
      longitude: 118.732500,
      polygonPoints: [
        LatLng(9.733739, 118.731009), // C1
        LatLng(9.734215, 118.733295), // C2
        LatLng(9.731275, 118.734046), // C4
        LatLng(9.730990, 118.732028), // C3
      ],
    ),
    PSUCampus(
      name: 'Gymnasium',
      latitude: 9.778936,
      longitude: 118.732841,
      polygonPoints: [
        LatLng(9.779087, 118.732647), // C1 (Top Left)
        LatLng(9.779094, 118.733031), // C2 (Top Right)
        LatLng(9.778785, 118.733039), // C4 (Bottom Right)
        LatLng(9.778788, 118.732636), // C3 (Bottom Left)
      ],
    ),
    PSUCampus(
      name: 'Performing Arts Center',
      latitude: 9.777662,
      longitude: 118.732424,
      polygonPoints: [
        LatLng(9.777744, 118.732207), // C1
        LatLng(9.777728, 118.732647), // C2
        LatLng(9.777580, 118.732642), // C4
        LatLng(9.777580, 118.732204), // C3
      ],
    ),
    PSUCampus(
      name: 'Library',
      latitude: 9.777583,
      longitude: 118.734858,
      polygonPoints: [
        LatLng(9.777746, 118.734766), // C1
        LatLng(9.777744, 118.734951), // C2
        LatLng(9.777421, 118.734962), // C4
        LatLng(9.777413, 118.734766), // C3
      ],
    ),
    PSUCampus(
      name: 'Basketball Court',
      latitude: 9.777095,
      longitude: 118.733552,
      polygonPoints: [
        LatLng(9.777220, 118.733414), // C1
        LatLng(9.777223, 118.733693), // C2
        LatLng(9.776959, 118.733688), // C4
        LatLng(9.776967, 118.733411), // C3
      ],
    ),
    PSUCampus(
      name: 'Tennis Court',
      latitude: 9.776787,
      longitude: 118.733660,
      polygonPoints: [
        LatLng(9.776940, 118.733575), // C1
        LatLng(9.776943, 118.733757), // C2
        LatLng(9.776634, 118.733755), // C4
        LatLng(9.776634, 118.733564), // C3
      ],
    ),
    PSUCampus(
      name: 'Field',
      latitude: 9.777054,
      longitude: 118.734120,
      polygonPoints: [
        LatLng(9.777474, 118.733824), // C1
        LatLng(9.777469, 118.734417), // C2
        LatLng(9.776626, 118.734417), // C4
        LatLng(9.776634, 118.733824), // C3
      ],
    ),
    PSUCampus(
      name: 'College of Sciences',
      latitude: 9.778336,
      longitude: 118.734625,
      polygonPoints: [
        LatLng(9.778460, 118.734288), // C1
        LatLng(9.778476, 118.734932), // C2
        LatLng(9.778220, 118.734935), // C4
        LatLng(9.778196, 118.734315), // C3
      ],
    ),
    PSUCampus(
      name: 'IT Building',
      latitude: 9.778565,
      longitude: 118.733996,
      polygonPoints: [
        LatLng(9.778653, 118.733835), // C1
        LatLng(9.778674, 118.734157), // C2
        LatLng(9.778547, 118.734157), // C6
        LatLng(9.778539, 118.733956), // C5
        LatLng(9.778457, 118.733950), // C4
        LatLng(9.778457, 118.733859), // C3
      ],
    ),
    PSUCampus(
      name: 'Amphitheater',
      latitude: 9.778908,
      longitude: 118.733270,
      polygonPoints: [
        LatLng(9.778965, 118.733183), // C1
        LatLng(9.778986, 118.733258), // C2
        LatLng(9.779044, 118.733258), // C3
        LatLng(9.779071, 118.733358), // C4
        LatLng(9.778746, 118.733384), // C8
        LatLng(9.778748, 118.733293), // C7
        LatLng(9.778791, 118.733283), // C6
        LatLng(9.778806, 118.733183), // C5
      ],
    ),
  ];
}