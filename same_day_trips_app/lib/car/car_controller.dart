import 'package:flutter_carplay/flutter_carplay.dart';

class CarController {
  static final CarController _instance = CarController._internal();

  factory CarController() {
    return _instance;
  }

  CarController._internal();

  void initialize() {
    FlutterCarplay.setRootTemplate(
      rootTemplate: CPListTemplate(
        sections: [
          CPListSection(
            items: [
              CPListItem(
                text: "Same-Day Trips",
                detailText: "Find trips from your location",
                onPress: (complete, item) {
                  // TODO: Navigate to search or show trips
                  complete();
                },
                image: 'assets/images/logo.png', // Ensure this asset exists or remove
              ),
              CPListItem(
                text: "Saved Trips",
                detailText: "View your planned itineraries",
                onPress: (complete, item) {
                  complete();
                },
              ),
            ],
            header: "Menu",
          ),
        ],
        title: "Same-Day Trips",
        systemIcon: "house.fill",
      ),
      animated: true,
    );
  }
}
