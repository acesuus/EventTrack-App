import 'package:latlong2/latlong.dart';

// GLOBAL TESTING FLAG
const bool isTestingMode = true;

// HOME TESTING POLYGON COORDINATES
final List<LatLng> homeTestPolygon = [
  LatLng(9.733739, 118.731009), // C1
  LatLng(9.734215, 118.733295), // C2
  LatLng(9.731275, 118.734046), // C4
  LatLng(9.730990, 118.732028), // C3
];

// HOME TESTING CENTER
final LatLng homeCenter = const LatLng(9.732500, 118.732500);

// RAY-CASTING (EVEN-ODD) ALGORITHM
bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
  bool isInside = false;
  int j = polygon.length - 1;

  for (int i = 0; i < polygon.length; i++) {
    if ((polygon[i].longitude > point.longitude) != (polygon[j].longitude > point.longitude) &&
        (point.latitude <
            (polygon[j].latitude - polygon[i].latitude) *
                    (point.longitude - polygon[i].longitude) /
                    (polygon[j].longitude - polygon[i].longitude) +
                polygon[i].latitude)) {
      isInside = !isInside;
    }
    j = i;
  }

  return isInside;
}
