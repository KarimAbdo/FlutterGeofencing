import Flutter
import UIKit
import CoreLocation

class FLGeofence {
    var callback: Int
    var lat: String
    var long: String
    var id: String
    
    init(callback: Int, id: String, lat: String, long: String) {
        self.callback = callback
        self.lat = lat
        self.long = long
        self.id = id
    }
}
public class SwiftFlutterGeofencingPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate {
    var flGeofences: [FLGeofence] = []
    
    private var locationManager: CLLocationManager = CLLocationManager()
    var callBackHandler: FlutterMethodChannel?
    private var distanceOnGeolocation = 1500.0
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftFlutterGeofencingPlugin()
        instance.setupCallHandler(registrar: registrar)
    }
    
    func setupCallHandler(registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "plugins.flutter.io/geofencing_plugin", binaryMessenger: registrar.messenger())
        channel.setMethodCallHandler { (call: FlutterMethodCall, result: FlutterResult) in
            // Ask for permission
            if call.method == "GeofencingPlugin.initializeService" {
                result("iOS " + UIDevice.current.systemVersion)
                self.locationManager.delegate = self
                self.locationManager.requestAlwaysAuthorization()
                let resultMap: [String: String] = [:]
                result(resultMap)
            } else if call.method == "GeofencingPlugin.registerGeofence" {
                if let nsArray = call.arguments as? NSArray {
                    let callbackHandle = nsArray[0] as? Int
                    let id = nsArray[1] as? String
                    let lat = nsArray[2] as? Double
                    let long = nsArray[3] as? Double
                    if let id = id, let lat = lat, let long = long {
                        let flGeofence: FLGeofence = FLGeofence(callback: callbackHandle ?? 0, id: id, lat: lat.description, long: long.description)
                        self.register(flGeofenceList: [flGeofence])
                    }
                }
                let resultMap: [String: String] = [:]
                result(resultMap)
            } else if call.method == "GeofencingPlugin.removeGeofence" {
                self.removeRegionMonitering()
                let resultMap: [String: String] = [:]
                result(resultMap)
            }
        }

        callBackHandler = FlutterMethodChannel(name: "plugins.flutter.io/geofencing_plugin_background", binaryMessenger: registrar.messenger())
        callBackHandler?.setMethodCallHandler { (call: FlutterMethodCall, result: FlutterResult) in
            if call.method == "GeofencingService.initialized" {
                result(nil)
            }
        }
    }
    
    func register(flGeofenceList: [FLGeofence]) -> Void {
        let currentLocation: CLLocation = self.locationManager.location ?? CLLocation(latitude: 0, longitude: 0)
        flGeofences = flGeofenceList
        
        // Apple only support 20 region locations for the same app
        if flGeofences.count > 20 {
            flGeofences.sort { (a, b) -> Bool in
                let latA = Double(a.lat) ?? 0
                let longA = Double(a.long) ?? 0
                let latB = Double(b.lat) ?? 0
                let longB = Double(b.long) ?? 0
                return CLLocation(latitude: latA, longitude: longA).distance(from: currentLocation) < CLLocation(latitude: latB, longitude: longB).distance(from: currentLocation)
            }
            
            flGeofences = flGeofences.enumerated().compactMap{ $0.offset < 19 ? $0.element : nil }
        }
        
        // Subscribing to geofence with the location list
        for location in flGeofences {
            let lat = Double(location.lat) ?? 0
            let long = Double(location.long) ?? 0
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: long), radius: distanceOnGeolocation, identifier: location.id)
            region.notifyOnExit = true
            region.notifyOnEntry = true
            
            self.locationManager.startMonitoring(for: region)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        invoke(event: 1)
    }
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        invoke(event: 2)
    }
    
    func removeRegionMonitering() {
        let regions = locationManager.monitoredRegions
        
        for region in regions {
            locationManager.stopMonitoring(for: region)
        }
    }
    
    func invoke(event: Int) {
        var args: [Any] = []
        var identifiers: [String] = []
        let regions = locationManager.monitoredRegions
        
        if !regions.isEmpty {
          identifiers = regions.compactMap { $0.identifier }
        }
        
        args.append(identifiers)
        callBackHandler?.invokeMethod("", arguments: args)
    }
}
