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
    var headLessRunner: FlutterEngine?
    var locationManager: CLLocationManager?
    private var distanceOnGeolocation = 1500.0
    var registrar: FlutterPluginRegistrar?
    var mainChannel: FlutterMethodChannel?
    var callbackChannel: FlutterMethodChannel?
    var initialized: Bool = false
    var eventQueue: [CLRegion:Int64]?
    let callbackMappingKey = "geofence_region_callback_mapping"
    static var instance: SwiftFlutterGeofencingPlugin?
    static var registerPlugins: FlutterPluginRegistrantCallback?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        if instance == nil {
            instance = SwiftFlutterGeofencingPlugin.init(reg: registrar)
            if let instance = instance {
                registrar.addApplicationDelegate(instance)
            }
        }
    }

    public init(reg: FlutterPluginRegistrar) {
        super.init()
        headLessRunner = FlutterEngine.init(name: "GeofencingIsolate", project: nil, allowHeadlessExecution: true)
        registrar = reg
        mainChannel = FlutterMethodChannel(name: "plugins.flutter.io/geofencing_plugin", binaryMessenger: reg.messenger())
        
        if let binaryMessenger = headLessRunner?.binaryMessenger {
            callbackChannel = FlutterMethodChannel(name: "plugins.flutter.io/geofencing_plugin_background", binaryMessenger: binaryMessenger)
        }
        
        if let mainChannel = mainChannel {
            reg.addMethodCallDelegate(self, channel: mainChannel)
        }
        
        eventQueue = [:]
        locationManager = CLLocationManager.init()
        locationManager?.delegate = self
        locationManager?.requestAlwaysAuthorization()
        if #available(iOS 9.0, *) {
            locationManager?.allowsBackgroundLocationUpdates = true
        }
    }
    
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        registerPlugins = callback
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
         if call.method == "GeofencingPlugin.initializeService" {
             let callback: Int64 = (call.arguments as? NSArray)![0] as! Int64
             self.startGeofencingService(callback: callback)
             result(true)
         } else if call.method == "GeofencingPlugin.registerGeofence" {
            if let args = call.arguments as? [Any] {
                self.register(args: args)
            }
            result(true)
         } else if call.method == "GeofencingPlugin.removeGeofence" {
            if let args = call.arguments as? [Any] {
                result(self.removeGeofence(args: args))
            }
            result(false)
         } else if call.method == "GeofencingService.initialized" {
             // TODO - add sync?
            initialized = true
            while eventQueue?.count ?? 0 > 0 {
                let event = eventQueue?.popFirst()
                if let key = event?.key, let value = event?.value {
                    sendLocationEvent(region: key, event: value)
                }
            }
            result(nil)
         }
    }
    
    func sendLocationEvent(region: CLRegion, event: Int64) {
        if let clCircularRegion = region as? CLCircularRegion {
            let center: CLLocationCoordinate2D = clCircularRegion.center
            let handle: Int64 = getCallbackHandleForRegionId(identifier: region.identifier)
            var args: [Any] = []
            args.append(handle)
            args.append([region.identifier])
            args.append([center.latitude, center.longitude])
            args.append(event)
            
            callbackChannel?.invokeMethod("", arguments: args)
        }
    }
    
    func getCallbackHandleForRegionId(identifier: String) -> Int64 {
        let mapping: [String: Any] = getRegionalCallbackMapping()
        let handle = mapping[identifier]
        if handle == nil {
            return 0
        }
        
        if let handle = handle as? Int64 {
          return handle
        }
        
        return 0
    }
    
    func getRegionalCallbackMapping() -> [String:Any] {
        var callbackDict = UserDefaults.standard.dictionary(forKey: callbackMappingKey)
        if (callbackDict == nil){
            callbackDict = [:]
            UserDefaults.standard.set(callbackDict, forKey: callbackMappingKey)
        }
        
        if let callbackDict = callbackDict {
            return callbackDict
        }
        
        return [:]
    }
    
    func startGeofencingService(callback: Int64) {
        let defaults = UserDefaults.standard
        defaults.set(callback, forKey: "callback_dispatcher_handle")
        
        let info: FlutterCallbackInformation = FlutterCallbackCache.lookupCallbackInformation(callback)
        
        let entryPoint = info.callbackName
        let uri = info.callbackLibraryPath
        
        headLessRunner?.run(withEntrypoint: entryPoint, libraryURI: uri)
        if let headlessRunner = headLessRunner, let registerPlugin = SwiftFlutterGeofencingPlugin.registerPlugins {
            registerPlugin(headlessRunner)
        }

        if let callbackHandler = callbackChannel {
            registrar?.addMethodCallDelegate(self, channel: callbackHandler)
        }
        
    }
    
    func register(args: [Any]) -> Void {
        let callbackHandle = args[0] as? Int64 ?? 0
        let id = args[1] as? String ?? ""
        let lat = args[2] as? Double ?? 0
        let long = args[3] as? Double ?? 0

        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: long), radius: distanceOnGeolocation, identifier: id)
        region.notifyOnExit = true
        region.notifyOnEntry = true
        
        sendLocationEvent(region: region, event: 1)
        
        setCallbackHandlerForRegionId(handle: callbackHandle, indentifier: id)
        locationManager?.startMonitoring(for: region)
    }
    
    func setCallbackHandlerForRegionId(handle: Int64, indentifier: String) {
        var mapping = getRegionalCallbackMapping()
        mapping[indentifier] = handle
        setRegionCallbackMapping(mapping: mapping)
    }
    
    func setRegionCallbackMapping(mapping: [String: Any]) {
        UserDefaults.standard.set(mapping, forKey: callbackMappingKey)
    }
    
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        
        if launchOptions[UIApplicationLaunchOptionsKey.location] != nil {
            startGeofencingService(callback: getcallbackDispatcherHandler())
        }
        
        return true
    }
    
    public func getcallbackDispatcherHandler() -> Int64 {
        if let handle = UserDefaults.standard.object(forKey: "callback_dispatcher_handle") as? Int64 {
            return handle
        }
        
        return 0
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        if initialized {
            sendLocationEvent(region: region, event: 1)
        } else {
            eventQueue?[region] = 1
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        if initialized {
            sendLocationEvent(region: region, event: 0)
        } else {
            eventQueue?[region] = 2
        }
    }
    
//    func removeRegionMonitering() {
//        if let regions = locationManager?.monitoredRegions {
//            for region in regions {
//                locationManager?.stopMonitoring(for: region)
//            }
//        }
//    }
    
    func removeGeofence(args: [Any]) -> Bool {
        let identifier = args[0] as? String
        if let regions = locationManager?.monitoredRegions {
            for region in regions {
                if identifier == region.identifier {
                   locationManager?.stopMonitoring(for: region)
                    removeCallbackHandleForRegionId(identifier: region.identifier)
                    return true
                }
            }
        }
        return false
    }
    
    func removeCallbackHandleForRegionId(identifier: String) {
        var mapping = getRegionalCallbackMapping()
        mapping.removeValue(forKey: identifier)
        setRegionCallbackMapping(mapping: mapping)
    }
    
}
