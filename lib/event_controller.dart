import 'package:flutter/foundation.dart';

class LocalEventProvider extends ChangeNotifier {
  // Singleton pattern to ensure we only have one mock database instance
  static final LocalEventProvider _instance = LocalEventProvider._internal();

  factory LocalEventProvider() {
    return _instance;
  }

  LocalEventProvider._internal();

  final List<Map<String, dynamic>> _mockEvents = [];

  List<Map<String, dynamic>> get mockEvents => _mockEvents;

  Future<void> saveEvent(Map<String, dynamic> data) async {
    // Simulate a 1-second network delay
    await Future.delayed(const Duration(seconds: 1));
    
    _mockEvents.add(data);
    debugPrint('✅ SUCCESS: Event saved locally (Offline Mode). Total events: ${_mockEvents.length}');
    
    notifyListeners();
  }
}