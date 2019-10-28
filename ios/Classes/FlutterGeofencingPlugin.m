#import "FlutterGeofencingPlugin.h"
#import <flutter_geofencing/flutter_geofencing-Swift.h>

@implementation FlutterGeofencingPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterGeofencingPlugin registerWithRegistrar:registrar];
}
@end
