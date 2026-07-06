import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../services/app_theme.dart';
import 'chat_screen.dart';
import 'wallet_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final MapController _mapController = MapController();

  static const String adminTrackUrl = 'http://localhost:8080';

  // User Profile
  Map<String, dynamic>? _profile;
  bool _loadingProfile = true;

  // Selected Locations Coordinates and Addresses
  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;
  String? _pickupAddress;
  String? _dropAddress;

  // Text Editing Controllers for Search Inputs
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();

  // Map Selection mode: null, 'pickup', 'drop'
  String? _mapSelectMode;

  // Nominatim Search variables
  List<Map<String, dynamic>> _searchResults = [];
  bool _searchingAddress = false;
  String? _activeSearchField; // 'pickup' or 'drop'

  // Malaysia boundaries
  final LatLngBounds _malaysiaBounds = LatLngBounds(
    const LatLng(0.8, 99.5),
    const LatLng(7.5, 119.5),
  );

  // Mock Locations inside Melaka, Malaysia for easy offline testing
  final Map<String, LatLng> _mockLocations = {
    "Jonker Street Night Market": const LatLng(2.1944, 102.2492),
    "Christ Church Melaka": const LatLng(2.1940, 102.2490),
    "Klebang Beach": const LatLng(2.2163, 102.1931),
    "Melaka Sentral Bus Terminal": const LatLng(2.2212, 102.2494),
    "A Famosa Fort": const LatLng(2.1923, 102.2501),
  };

  // State Variables
  bool _womenOnly = false;
  bool _prefChatty = false;
  bool _prefPets = false;
  bool _prefMusic = false;
  bool _prefSmoking = false;
  int _seatsRequested = 1;

  final String _corporateEmailDomain = "";
  
  bool _calculatingRoute = false;
  Map<String, dynamic>? _routeEstimate;
  List<LatLng> _polylinePoints = [];

  // Active Ride Info (Rider)
  Map<String, dynamic>? _activeRide;
  
  // Active Rides (Driver)
  List<Map<String, dynamic>> _activeDriverRides = [];
  
  RealtimeChannel? _rideSubscription;
  LatLng? _driverLocation;
  Timer? _gpsTimer;

  // Scheduled Time
  DateTime? _scheduledTime;

  // Driver states
  bool _isOnline = false;
  LatLng? _driverRouteStart;
  LatLng? _driverRouteEnd;
  final TextEditingController _driverStartController = TextEditingController();
  final TextEditingController _driverEndController = TextEditingController();
  List<Map<String, dynamic>> _incomingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    if (_rideSubscription != null) {
      _supabase.removeChannel(_rideSubscription!);
    }
    _pickupController.dispose();
    _dropController.dispose();
    _driverStartController.dispose();
    _driverEndController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .single();

      setState(() {
        _profile = data;
        _isOnline = data['is_online'] ?? false;
      });

      if (_profile?['role'] == 'driver') {
        _listenToRideRequests();
        _loadActiveDriverRides();
        if (_isOnline) _startGPSDaemon();
      } else {
        _checkForActiveRide();
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      setState(() => _loadingProfile = false);
    }
  }

  Future<void> _loadActiveDriverRides() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await _supabase
          .from('rides')
          .select('*')
          .eq('driver_id', userId)
          .neq('status', 'completed')
          .neq('status', 'cancelled')
          .order('created_at', ascending: false);
      setState(() {
        _activeDriverRides = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Error loading active driver rides: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return;
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      final latLng = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _pickupLatLng = latLng;
      });
      
      // Move camera to user's location
      _mapController.move(latLng, 15);
      
      // Try to get address for the text field
      final address = await _reverseGeocode(latLng);
      setState(() {
        _pickupAddress = address;
        _pickupController.text = address;
      });
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  // --------------------------------------------------
  // Rider Flows
  // --------------------------------------------------

  Future<void> _calculateRoute() async {
    if (_pickupLatLng == null || _dropLatLng == null) return;
    setState(() {
      _calculatingRoute = true;
      _polylinePoints = [];
      _routeEstimate = null;
    });

    final pLoc = _pickupLatLng!;
    final dLoc = _dropLatLng!;

    try {
      final String orsKey = 'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImFiZTAwNjliOWI1NjQ3Yzk4YzAyZGQ2NmQyMjMxMmNhIiwiaCI6Im11cm11cjY0In0=';
      final orsUrl = 'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$orsKey&start=${pLoc.longitude},${pLoc.latitude}&end=${dLoc.longitude},${dLoc.latitude}';
      
      final response = await http.get(Uri.parse(orsUrl)).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['features'] != null && data['features'].isNotEmpty) {
          final feature = data['features'][0];
          final summary = feature['properties']['summary'];
          final coordsList = feature['geometry']['coordinates'] as List;
          
          final distanceKm = summary['distance'] / 1000.0;
          final durationMins = summary['duration'] / 60.0;
          
          final baseFare = 5.00;
          final distanceFare = distanceKm * 1.20;
          final timeFare = durationMins * 0.30;
          final costPerSeat = (baseFare + distanceFare + timeFare) < 5.00 ? 5.00 : (baseFare + distanceFare + timeFare);

          setState(() {
            _routeEstimate = {
              'distance_km': double.parse(distanceKm.toStringAsFixed(2)),
              'duration_mins': double.parse(durationMins.toStringAsFixed(1)),
              'cost_per_seat': double.parse(costPerSeat.toStringAsFixed(2)),
              'base_fare': double.parse(baseFare.toStringAsFixed(2)),
              'distance_fare': double.parse(distanceFare.toStringAsFixed(2)),
              'time_fare': double.parse(timeFare.toStringAsFixed(2)),
            };
            // ORS returns [longitude, latitude]
            _polylinePoints = coordsList.map((c) => LatLng(c[1], c[0])).toList();
          });

          // Fit map bounds
          _mapController.fitCamera(CameraFit.bounds(
            bounds: LatLngBounds(pLoc, dLoc),
            padding: const EdgeInsets.all(50),
          ));
          return;
        }
      }
      throw Exception('Failed to fetch route from ORS: ${response.body}');
    } catch (e) {
      debugPrint('Routing failed: $e. Using local straight-line distance fallback.');
      
      // Local Haversine calculation fallback
      final R = 6371; // Earth radius in km
      final dLat = (dLoc.latitude - pLoc.latitude) * math.pi / 180;
      final dLon = (dLoc.longitude - pLoc.longitude) * math.pi / 180;
      final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
                math.cos(pLoc.latitude * math.pi / 180) * math.cos(dLoc.latitude * math.pi / 180) *
                math.sin(dLon / 2) * math.sin(dLon / 2);
      final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
      final distanceKm = R * c;
      final durationMins = distanceKm * 1.5; // Estimate 1.5 mins per km

      final baseFare = 5.00;
      final distanceFare = distanceKm * 1.20;
      final timeFare = durationMins * 0.30;
      final costPerSeat = (baseFare + distanceFare + timeFare) < 5.00 ? 5.00 : (baseFare + distanceFare + timeFare);

      setState(() {
        _routeEstimate = {
          'distance_km': double.parse(distanceKm.toStringAsFixed(2)),
          'duration_mins': double.parse(durationMins.toStringAsFixed(1)),
          'cost_per_seat': double.parse(costPerSeat.toStringAsFixed(2)),
          'base_fare': double.parse(baseFare.toStringAsFixed(2)),
          'distance_fare': double.parse(distanceFare.toStringAsFixed(2)),
          'time_fare': double.parse(timeFare.toStringAsFixed(2)),
        };
        _polylinePoints = [pLoc, dLoc];
      });

      _mapController.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(pLoc, dLoc),
        padding: const EdgeInsets.all(50),
      ));
    } finally {
      setState(() => _calculatingRoute = false);
    }
  }

  // Decodes OSRM default google polyline geometries
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  // Nominatim Address Search
  Future<void> _searchForAddress(String query, String field) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _searchingAddress = true;
      _activeSearchField = field;
      _searchResults = [];
    });

    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/search?format=json&q=${Uri.encodeComponent(query)}&countrycodes=my&limit=5'),
        headers: {'User-Agent': 'JomRide_Carpool_App_Melaka'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        setState(() {
          _searchResults = data.map<Map<String, dynamic>>((item) {
            return {
              'display_name': item['display_name'] ?? '',
              'lat': double.parse(item['lat'] ?? '0.0'),
              'lon': double.parse(item['lon'] ?? '0.0'),
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Geocoding search error: $e');
    } finally {
      setState(() => _searchingAddress = false);
    }
  }

  // Nominatim Reverse Geocoding
  Future<String> _reverseGeocode(LatLng point) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=${point.latitude}&lon=${point.longitude}&zoom=16'),
        headers: {'User-Agent': 'JomRide_Carpool_App_Melaka'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null) {
          final parts = displayName.split(',');
          if (parts.length > 3) {
            return parts.sublist(0, 3).join(',').trim();
          }
          return displayName;
        }
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
    return '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}';
  }

  // Handle map tap events
  Future<void> _handleMapTap(TapPosition tapPosition, LatLng point) async {
    if (_mapSelectMode == null) return;
    
    final mode = _mapSelectMode;
    setState(() {
      _mapSelectMode = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Retrieving address...'), duration: Duration(milliseconds: 1500)),
    );

    final address = await _reverseGeocode(point);

    setState(() {
      if (mode == 'pickup') {
        _pickupLatLng = point;
        _pickupAddress = address;
        _pickupController.text = address;
      } else if (mode == 'drop') {
        _dropLatLng = point;
        _dropAddress = address;
        _dropController.text = address;
      }
    });

    _calculateRoute();
  }

  Future<void> _requestRide() async {
    if (_routeEstimate == null || _pickupLatLng == null || _dropLatLng == null) return;
    setState(() => _calculatingRoute = true);

    final pLoc = _pickupLatLng!;
    final dLoc = _dropLatLng!;

    try {
      final userId = _supabase.auth.currentUser?.id;
      final costPerSeat = _routeEstimate!['cost_per_seat'];
      final platformFee = 1.50;
      final totalFare = (costPerSeat * _seatsRequested) + platformFee;

      // Insert Ride
      final rideRes = await _supabase.from('rides').insert({
        'rider_id': userId,
        'status': 'requested',
        'pickup_latitude': pLoc.latitude,
        'pickup_longitude': pLoc.longitude,
        'pickup_address': (_scheduledTime != null ? '[Schedule: ${_scheduledTime!.day}/${_scheduledTime!.month} ${_scheduledTime!.hour}:${_scheduledTime!.minute.toString().padLeft(2, '0')}] ' : '') + (_pickupAddress ?? 'Custom Pickup Location'),
        'drop_latitude': dLoc.latitude,
        'drop_longitude': dLoc.longitude,
        'drop_address': _dropAddress ?? 'Custom Destination',
        'distance_km': _routeEstimate!['distance_km'],
        'duration_mins': _routeEstimate!['duration_mins'],
        'fare': totalFare,
        // TODO: Uncomment these lines once you've run the ALTER TABLE SQL script in your Supabase Dashboard!
        // 'cost_per_seat': costPerSeat,
        // 'seats': _seatsRequested,
        // 'platform_fee': platformFee,
        // 'chatty': _prefChatty,
        // 'pets_allowed': _prefPets,
        // 'music_allowed': _prefMusic,
        // 'smoking_allowed': _prefSmoking,
        'women_only': _womenOnly,
        'trust_circle_domain': _corporateEmailDomain.isNotEmpty ? _corporateEmailDomain : null,
      }).select().single();

      setState(() {
        _activeRide = rideRes;
      });

      // Call Telegram bot webhook for new requested ride
      _notifyTelegram(rideRes['id'], 'requested');

      // Call match-driver Edge Function to assign driver
      final matchRes = await _supabase.functions.invoke('match-driver', body: {
        'ride_id': rideRes['id'],
      });

      if (matchRes.status == 200 && matchRes.data['success'] == true) {
        _subscribeToRideUpdates(rideRes['id']);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No real drivers nearby. Simulating a Dummy Driver...')),
        );
        _subscribeToRideUpdates(rideRes['id']);
        _simulateDummyDriver(rideRes['id']);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _calculatingRoute = false);
    }
  }

  Future<void> _simulateDummyDriver(String rideId) async {
    final userId = _supabase.auth.currentUser?.id;
    
    // Simulate Accept
    await Future.delayed(const Duration(seconds: 3));
    if (_activeRide?['id'] != rideId || _activeRide?['status'] == 'cancelled') return;
    await _supabase.from('rides').update({'status': 'accepted', 'driver_id': userId, 'updated_at': DateTime.now().toIso8601String()}).eq('id', rideId);
    
    // Simulate Arrive
    await Future.delayed(const Duration(seconds: 4));
    if (_activeRide?['id'] != rideId || _activeRide?['status'] == 'cancelled') return;
    await _supabase.from('rides').update({'status': 'arrived', 'updated_at': DateTime.now().toIso8601String()}).eq('id', rideId);

    // Simulate Pick Up
    await Future.delayed(const Duration(seconds: 3));
    if (_activeRide?['id'] != rideId || _activeRide?['status'] == 'cancelled') return;
    await _supabase.from('rides').update({'status': 'picked_up', 'updated_at': DateTime.now().toIso8601String()}).eq('id', rideId);

    // Simulate Complete (Wait longer so rider can test chat)
    await Future.delayed(const Duration(seconds: 15));
    if (_activeRide?['id'] != rideId || _activeRide?['status'] == 'cancelled') return;
    await _supabase.from('rides').update({'status': 'completed', 'updated_at': DateTime.now().toIso8601String()}).eq('id', rideId);
  }

  void _handleRideCancelled() {
    _rideSubscription?.unsubscribe();
    setState(() {
      _activeRide = null;
      _polylinePoints = [];
      _routeEstimate = null;
      _pickupLatLng = null;
      _dropLatLng = null;
      _pickupController.clear();
      _dropController.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip has been cancelled.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _subscribeToRideUpdates(String rideId) {
    _rideSubscription = _supabase
        .channel('active-ride-$rideId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: rideId,
          ),
          callback: (payload) {
            setState(() {
              _activeRide = payload.newRecord;
            });
            if (_activeRide?['status'] == 'completed') {
              _rideSubscription?.unsubscribe();
              if (_profile?['role'] == 'rider') {
                _processPaymentSimulation();
              } else {
                _showCompletedRatingSheet();
              }
            } else if (_activeRide?['status'] == 'cancelled') {
              _handleRideCancelled();
            } else if (_activeRide?['driver_id'] != null) {
              _listenToDriverGPS(_activeRide!['driver_id']);
            }
          },
        );
    _rideSubscription!.subscribe();
  }

  Future<void> _processPaymentSimulation() async {
    final fare = _activeRide?['fare']?.toString() ?? '0.00';
    // Dummy Driver Data as requested
    final driverName = 'Ali bin Abu';
    final carPlate = 'Perodua Myvi - VEX 1234';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Theme.of(context).primaryColor),
                const SizedBox(height: 24),
                Text(
                  'Processing E-Wallet Payment...',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Deducting RM $fare from JomRide Wallet', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text('Paying Driver:', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                Text(driverName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                Text(carPlate, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
              ],
            ),
          ),
        );
      },
    );

    // Simulate 3 seconds processing
    await Future.delayed(const Duration(seconds: 3));

    if (!mounted) return;
    Navigator.of(context).pop(); // Close loading dialog

    // Show Success Dialog
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 24),
                Text(
                  'Payment Successful!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                ),
                const SizedBox(height: 8),
                Text('RM $fare has been securely paid to $driverName.', textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Continue to Rating'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _showCompletedRatingSheet();
  }

  void _listenToDriverGPS(String driverId) {
    _supabase
        .channel('driver-gps-$driverId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_locations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: driverId,
          ),
          callback: (payload) {
            final rec = payload.newRecord;
            setState(() {
              _driverLocation = LatLng(rec['latitude'], rec['longitude']);
            });
          },
        )
        .subscribe();
  }

  Future<void> _checkForActiveRide() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final data = await _supabase
        .from('rides')
        .select('*')
        .eq('rider_id', userId)
        .neq('status', 'completed')
        .neq('status', 'cancelled')
        .order('created_at', ascending: false)
        .limit(1);

    if (data.isNotEmpty) {
      setState(() {
        _activeRide = data.first;
      });
      _subscribeToRideUpdates(_activeRide!['id']);
      if (_activeRide!['driver_id'] != null) {
        _listenToDriverGPS(_activeRide!['driver_id']);
      }
    }
  }

  void _triggerSOS() async {
    if (_activeRide == null) return;
    final pLoc = _pickupLatLng ?? const LatLng(2.19, 102.25);
    
    // Call Telegram notify with special SOS format
    await _supabase.functions.invoke('telegram-notify', body: {
      'ride_id': _activeRide!['id'],
      'status': 'sos',
      'details': {
        'rider_name': _profile?['name'] ?? 'Rider',
        'latitude': pLoc.latitude,
        'longitude': pLoc.longitude,
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🚨 SOS Alert Dispatched to Telegram Admins!'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // --------------------------------------------------
  // Driver Flows
  // --------------------------------------------------

  Future<void> _toggleOnline(bool online) async {
    if (online) {
      if (_driverRouteStart == null) {
        _driverRouteStart = _mockLocations.values.first;
        _driverStartController.text = _mockLocations.keys.first;
      }
      if (_driverRouteEnd == null) {
        _driverRouteEnd = _mockLocations.values.last;
        _driverEndController.text = _mockLocations.keys.last;
      }
    }
    setState(() => _isOnline = online);
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    await _supabase
        .from('profiles')
        .update({'is_online': online})
        .eq('id', userId);

    if (online) {
      _startGPSDaemon();
    } else {
      _gpsTimer?.cancel();
    }
  }

  void _startGPSDaemon() {
    _gpsTimer?.cancel();
    // Start periodic location publisher
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Simulate location moving slightly over Melaka
    double baseLat = 2.19;
    double baseLng = 102.25;
    double offset = 0.0;

    _gpsTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      offset += 0.0002;
      try {
        await _supabase.from('driver_locations').upsert({
          'driver_id': userId,
          'latitude': baseLat + offset,
          'longitude': baseLng + offset,
          'heading': 45.0,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('GPS Daemon error: $e');
      }
    });
  }

  void _listenToRideRequests() {
    _supabase
        .channel('ride-offers')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rides',
          callback: (payload) {
            _loadIncomingRequests();
          },
        )
        .subscribe();
    _loadIncomingRequests();
  }

  double _getDistanceKm(LatLng p1, LatLng p2) {
    final R = 6371; // Earth radius in km
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(p1.latitude * math.pi / 180) * math.cos(p2.latitude * math.pi / 180) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  Future<void> _loadIncomingRequests() async {
    try {
      final data = await _supabase
          .from('rides')
          .select('*')
          .eq('status', 'requested')
          .order('created_at', ascending: false);

      setState(() {
        List<Map<String, dynamic>> rawRequests = List<Map<String, dynamic>>.from(data);
        if (_driverRouteStart != null && _driverRouteEnd != null) {
          rawRequests = rawRequests.where((req) {
            final reqStart = LatLng(double.parse(req['pickup_latitude'].toString()), double.parse(req['pickup_longitude'].toString()));
            final reqEnd = LatLng(double.parse(req['drop_latitude'].toString()), double.parse(req['drop_longitude'].toString()));
            final distStart = _getDistanceKm(_driverRouteStart!, reqStart);
            final distEnd = _getDistanceKm(_driverRouteEnd!, reqEnd);
            return distStart <= 5.0 && distEnd <= 5.0; // Within 5km of start and end nodes
          }).toList();
        }
        _incomingRequests = rawRequests;
      });
    } catch (e) {
      debugPrint('Error loading ride offers: $e');
    }
  }

  Future<void> _updateRideStatus(String rideId, String status) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final updateData = <String, dynamic>{
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      if (status == 'accepted') {
        updateData['driver_id'] = userId;
      }

      await _supabase.from('rides').update(updateData).eq('id', rideId);
      _notifyTelegram(rideId, status);

      // Handle automatic wallet deduction on completion
      if (status == 'completed') {
        final targetRide = _activeDriverRides.firstWhere((r) => r['id'] == rideId, orElse: () => _activeRide ?? {});
        final rId = targetRide['rider_id'];
        final fareAmount = double.tryParse(targetRide['fare']?.toString() ?? '0.0') ?? 0.0;
        
        if (rId != null && fareAmount > 0) {
          // Get rider balance
          final rProfile = await _supabase.from('profiles').select('wallet_balance').eq('id', rId).single();
          final currentBal = double.tryParse(rProfile['wallet_balance']?.toString() ?? '0') ?? 0.0;
          await _supabase.from('profiles').update({'wallet_balance': currentBal - fareAmount}).eq('id', rId);
        }
      }

      _loadUserProfile(); // Reload profile & active ride state
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update trip: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _notifyTelegram(String rideId, String status) async {
    try {
      await _supabase.functions.invoke('telegram-notify', body: {
        'ride_id': rideId,
        'status': status,
      });
    } catch (e) {
      debugPrint('Telegram notify failed: $e');
    }
  }

  void _showCompletedRatingSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Arrived at Destination!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('How was your trip? Please rate your driver.'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (idx) {
                  return IconButton(
                    icon: const Icon(Icons.star_border, size: 36),
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _activeRide = null;
                        _polylinePoints = [];
                        _routeEstimate = null;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Thank you for your rating!')),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  // --------------------------------------------------
  // View Rendering
  // --------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final isDriver = _profile?['role'] == 'driver';

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: isDriver
            ? Text(
                'Driver Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
              )
            : Image.asset('assets/images/logo.jpeg', height: 32, fit: BoxFit.contain),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: IconButton(
              icon: Icon(Icons.account_balance_wallet_outlined, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: IconButton(
              icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () {
                Provider.of<ThemeNotifier>(context, listen: false).toggleTheme();
              },
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: IconButton(
              icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.onSurface),
              onPressed: () => _supabase.auth.signOut(),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map Canvas
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(2.1944, 102.2492), // Center in Melaka
              initialZoom: 14.0,
              cameraConstraint: CameraConstraint.contain(bounds: _malaysiaBounds),
              onTap: _handleMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: isDark 
                    ? 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.jomride.app',
              ),
              // Draw OSRM route lines
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      strokeWidth: 5,
                      color: AppTheme.primary,
                    ),
                  ],
                ),
              // Marker Layer (Pickup, Drop, Driver Location)
              MarkerLayer(
                markers: [
                  if (_pickupLatLng != null)
                    Marker(
                      point: _pickupLatLng!,
                      child: const Icon(Icons.location_on, color: AppTheme.primary, size: 36),
                    ),
                  if (_dropLatLng != null)
                    Marker(
                      point: _dropLatLng!,
                      child: const Icon(Icons.flag, color: AppTheme.accent, size: 36),
                    ),
                  if (_driverLocation != null)
                    Marker(
                      point: _driverLocation!,
                      child: const Icon(Icons.directions_car, color: AppTheme.primary, size: 36),
                    ),
                ],
              ),
            ],
          ),

          // Floating Selection Instruction Banner
          if (_mapSelectMode != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                color: AppTheme.ink,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(
                        _mapSelectMode == 'pickup' ? Icons.location_on : Icons.flag,
                        color: _mapSelectMode == 'pickup' ? AppTheme.primary : AppTheme.accent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _mapSelectMode == 'pickup'
                              ? 'Tap on the map to set Pickup Location'
                              : 'Tap on the map to set Destination',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => setState(() => _mapSelectMode = null),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Sheet Interface
          Align(
            alignment: Alignment.bottomCenter,
            child: isDriver ? _buildDriverSheet() : _buildRiderSheet(),
          ),
        ],
      ),
    );
  }

  // Rider Bottom Sheet
  Widget _buildRiderSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    if (_activeRide != null) {
      final status = _activeRide!['status'];
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 30,
              offset: const Offset(0, -10),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trip Status: ${status.toString().toUpperCase()}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.onSurface),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  color: AppTheme.primary,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(rideId: _activeRide!['id'])),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('From: ${_activeRide!['pickup_address']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            Text('To: ${_activeRide!['drop_address']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
            Text('Fare: RM ${double.parse(_activeRide!['fare'].toString()).toStringAsFixed(2)}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: isDark ? Colors.red.shade900 : Colors.red, foregroundColor: Colors.white),
                    onPressed: _triggerSOS,
                    child: const Text('🚨 SOS Alert'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final url = '$adminTrackUrl/track/${_activeRide!['id']}';
                      launchUrl(Uri.parse(url));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, foregroundColor: Theme.of(context).colorScheme.onSurface),
                    child: const Text('🔗 Share Trip'),
                  ),
                ),
              ],
            ),
            if (status == 'requested' || status == 'accepted' || status == 'arrived') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                  ),
                  onPressed: () => _updateRideStatus(_activeRide!['id'], 'cancelled'),
                  child: const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.6 : 0.1),
            blurRadius: 30,
            offset: const Offset(0, -10),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Choose a Ride',
            style: TextStyle(fontFamily: 'Inter', fontSize: 24, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          
          // Stacked Location Inputs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    const Icon(Icons.circle, size: 12, color: AppTheme.primary),
                    Container(height: 30, width: 2, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
                    const Icon(Icons.stop, size: 12, color: AppTheme.accent),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _pickupController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Pickup Location',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                        onSubmitted: (val) => _searchForAddress(val, 'pickup'),
                      ),
                      Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1), height: 16),
                      TextField(
                        controller: _dropController,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Destination',
                          hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                        ),
                        onSubmitted: (val) => _searchForAddress(val, 'drop'),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    IconButton(
                      icon: Icon(Icons.map, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
                      onPressed: () => setState(() => _mapSelectMode = 'pickup'),
                    ),
                    IconButton(
                      icon: Icon(Icons.map, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), size: 20),
                      onPressed: () => setState(() => _mapSelectMode = 'drop'),
                    ),
                  ],
                )
              ],
            ),
          ),

          // Popular Destinations Recommender
          if (_routeEstimate == null && _searchResults.isEmpty && !_searchingAddress) ...[
            const SizedBox(height: 16),
            Text(
              'Popular in Melaka',
              style: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _mockLocations.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ActionChip(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                      side: BorderSide.none,
                      label: Text(entry.key),
                      avatar: const Icon(Icons.place, size: 16, color: AppTheme.accent),
                      onPressed: () {
                        setState(() {
                          _dropLatLng = entry.value;
                          _dropAddress = entry.key;
                          _dropController.text = entry.key;
                        });
                        _calculateRoute();
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Search Results View
          if (_searchingAddress)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: CircularProgressIndicator(color: AppTheme.primary),
              ),
            )
          else if (_searchResults.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                itemBuilder: (context, idx) {
                  final item = _searchResults[idx];
                  return ListTile(
                    dense: true,
                    title: Text(
                      item['display_name'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                    onTap: () {
                      setState(() {
                        final latLng = LatLng(item['lat'], item['lon']);
                        if (_activeSearchField == 'pickup') {
                          _pickupLatLng = latLng;
                          _pickupAddress = item['display_name'];
                          _pickupController.text = item['display_name'];
                        } else {
                          _dropLatLng = latLng;
                          _dropAddress = item['display_name'];
                          _dropController.text = item['display_name'];
                        }
                        _searchResults = [];
                      });
                      _calculateRoute();
                    },
                  );
                },
              ),
            ),

          const SizedBox(height: 16),
          // Seats & Route Estimate Styled as a "Carpool" card
          if (_calculatingRoute)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppTheme.primary)))
          else if (_routeEstimate != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primary.withOpacity(0.15), AppTheme.primaryDark.withOpacity(0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: const Icon(Icons.directions_car, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Carpool', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        Text('${_routeEstimate!['duration_mins']} mins • ${_routeEstimate!['distance_km']} km', 
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('RM ${((_routeEstimate!['cost_per_seat'] * _seatsRequested) + 1.50).toStringAsFixed(2)}', 
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary)),
                      Row(
                        children: [
                          Icon(Icons.person, size: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
                          Text(' x $_seatsRequested', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // Seat Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Seats Required', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.remove, color: Theme.of(context).colorScheme.onSurface),
                        onPressed: () {
                          if (_seatsRequested > 1) setState(() => _seatsRequested--);
                        },
                      ),
                      Text('$_seatsRequested', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
                      IconButton(
                        icon: Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface),
                        onPressed: () {
                          if (_seatsRequested < 4) setState(() => _seatsRequested++);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Scheduled Ride Picker
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
                    ),
                    icon: Icon(Icons.calendar_today, size: 18, color: Theme.of(context).colorScheme.onSurface),
                    label: Text(
                      _scheduledTime != null 
                        ? '${_scheduledTime!.day}/${_scheduledTime!.month} ${_scheduledTime!.hour}:${_scheduledTime!.minute.toString().padLeft(2, '0')}'
                        : 'Schedule Later',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (date != null) {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() {
                            _scheduledTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                          });
                        }
                      }
                    },
                  ),
                ),
                if (_scheduledTime != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.clear, color: Colors.red),
                      onPressed: () => setState(() => _scheduledTime = null),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: AppTheme.primary,
                ),
                onPressed: _requestRide,
                child: const Text('Book Carpool', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Driver Bottom Sheet
  Widget _buildDriverSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.6 : 0.1),
            blurRadius: 30,
            offset: const Offset(0, -10),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver Status',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                  ),
                  Text(
                    _isOnline ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: _isOnline ? AppTheme.primary : Theme.of(context).colorScheme.onSurface),
                  ),
                ],
              ),
              Switch(
                value: _isOnline,
                onChanged: _toggleOnline,
                activeColor: Colors.white,
                activeTrackColor: AppTheme.primary,
                inactiveThumbColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isOnline) ...[
            Text('Set Your Commute Route', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text('We will match you with riders along this path.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
            const SizedBox(height: 12),
            TextField(
              controller: _driverStartController,
              decoration: InputDecoration(
                hintText: 'Start Location',
                prefixIcon: const Icon(Icons.location_on, color: AppTheme.primary),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide.none),
              ),
              onSubmitted: (v) {
                _driverRouteStart = _mockLocations.values.first; // Mock mapping for prototype
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _driverEndController,
              decoration: InputDecoration(
                hintText: 'End Destination',
                prefixIcon: const Icon(Icons.flag, color: AppTheme.accent),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMd), borderSide: BorderSide.none),
              ),
              onSubmitted: (v) {
                _driverRouteEnd = _mockLocations.values.last; // Mock mapping for prototype
              },
            ),
            const SizedBox(height: 16),
          ],
          if (_isOnline) ...[
            if (_incomingRequests.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  child: Text(
                    'Waiting for ride requests...',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                  ),
                ),
              )
            else ...[
              Text('Incoming Requests', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 12),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _incomingRequests.length,
                  itemBuilder: (ctx, idx) {
                    final req = _incomingRequests[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Pickup: ${req['pickup_address']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.flag, size: 16, color: AppTheme.accent),
                                const SizedBox(width: 8),
                                Expanded(child: Text('Dropoff: ${req['drop_address']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('RM ${req['fare']}', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                                    Text('${req['distance_km']}km • ${req['seats'] ?? 1} seats', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                                  ],
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                                        side: BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                      ),
                                      onPressed: () => _updateRideStatus(req['id'], 'cancelled'),
                                      child: Text('Decline', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          req['status'] = 'accepted';
                                          _activeDriverRides.add(req);
                                          _incomingRequests.removeWhere((r) => r['id'] == req['id']);
                                        });
                                        _updateRideStatus(req['id'], 'accepted');
                                      },
                                      child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]
          ],
          if (_activeDriverRides.isNotEmpty) ...[
            Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.1)),
            const SizedBox(height: 8),
            Text('Active Trips', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
            const SizedBox(height: 8),
            ..._activeDriverRides.map((ride) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                  border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rider ID: ${ride['rider_id'].toString().substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 16, color: AppTheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(ride['pickup_address'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.flag, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(ride['drop_address'], maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Theme.of(context).colorScheme.onSurface))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDriverActionButton(ride),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chat_bubble_outline),
                            color: AppTheme.primary,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ChatScreen(rideId: ride['id'])),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (ride['status'] == 'accepted' || ride['status'] == 'arrived') ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
                          ),
                          onPressed: () => _updateRideStatus(ride['id'], 'cancelled'),
                          child: const Text('Cancel Trip', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ]
        ],
      ),
    );
  }

  Widget _buildDriverActionButton(Map<String, dynamic> ride) {
    String label = '';
    String nextStatus = '';
    
    if (ride['status'] == 'accepted') {
      label = 'Arrived at Pickup';
      nextStatus = 'arrived';
    } else if (ride['status'] == 'arrived') {
      label = 'Start Trip';
      nextStatus = 'picked_up';
    } else if (ride['status'] == 'picked_up') {
      label = 'Complete Trip';
      nextStatus = 'completed';
    } else {
      return const SizedBox.shrink();
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: nextStatus == 'completed' ? Colors.green : AppTheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusPill)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      onPressed: () => _updateRideStatus(ride['id'], nextStatus),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
