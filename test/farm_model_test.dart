import 'package:flutter_test/flutter_test.dart';
import 'package:dreamlight_companion/farm_model.dart';
import 'package:dreamlight_companion/store.dart';

void main() {
  test('floating island uses 65 crop cells and reserves well footprint', () {
    final map = newLayout('Pumpkins', 'Plaza Island');
    expect(map['width'], 65);
    expect(canPlace(map, 29, 29, 1, 1), false);
    expect(canPlace(map, 64, 64, 1, 1), true);
    expect(canPlace(map, 64, 64, 2, 2), false);
    map['blocked'] = [0];
    expect(canPlace(map, 0, 0, 1, 1), false);
    expect(firstSpace(map, 4, 4), (1, 0));
    validateLayouts([map]);
  });
  test(
    'legacy layouts retain all coordinates and gain explicit calibration state',
    () {
      final map = <String, dynamic>{
        'name': 'Old farm',
        'plots': [
          {
            'crop': 'Pumpkin',
            'notes': '',
            'x': 30,
            'y': 30,
            'w': 2,
            'h': 2,
            'color': 0,
          },
        ],
      };
      migrateLayout(map);
      expect(map['width'], 32);
      expect(map['calibrated'], false);
      expect(map['plots'][0]['x'], 30);
      validateLayouts([map]);
    },
  );
}
