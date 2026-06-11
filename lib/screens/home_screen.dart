import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
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
  final String _corporateEmailDomain = "";
  
  bool _calculatingRoute = false;
  Map<String, dynamic>? _routeEstimate;
  List<LatLng> _polylinePoints = [];

  // Active Ride Info
  Map<String, dynamic>? _activeRide;
  RealtimeChannel? _rideSubscription;
  LatLng? _driverLocation;
  Timer? _gpsTimer;

  // Driver states
  bool _isOnline = false;
  List<Map<String, dynamic>> _incomingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    if (_rideSubscription != null) {
      _supabase.removeChannel(_rideSubscription!);
    }
    _pickupController.dispose();
    _dropController.dispose();
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
      // Call our calculate-fare Edge Function
      final response = await _supabase.functions.invoke('calculate-fare', body: {
        'pickup_lat': pLoc.latitude,
        'pickup_lng': pLoc.longitude,
        'drop_lat': dLoc.latitude,
        'drop_lng': dLoc.longitude,
      });

      final resData = response.data;
      if (response.status == 200 && resData != null) {
        setState(() {
          _routeEstimate = resData;
          final polyStr = resData['polyline'] as String?;
          if (polyStr != null && polyStr.isNotEmpty) {
            _polylinePoints = _decodePolyline(polyStr);
          } else {
            // Fallback: Draw straight line between pickup and destination
            _polylinePoints = [pLoc, dLoc];
          }
        });

        // Fit map bounds
        _mapController.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds(pLoc, dLoc),
          padding: const EdgeInsets.all(50),
        ));
      } else {
        throw Exception(resData['error'] ?? 'Route calculation failed');
      }
    } catch (e) {
      debugPrint('Routing Edge Function failed: $e. Using local straight-line distance fallback.');
      
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
      final totalFare = (baseFare + distanceFare + timeFare) < 5.00 ? 5.00 : (baseFare + distanceFare + timeFare);

      setState(() {
        _routeEstimate = {
          'distance_km': double.parse(distanceKm.toStringAsFixed(2)),
          'duration_mins': double.parse(durationMins.toStringAsFixed(1)),
          'fare': double.parse(totalFare.toStringAsFixed(2)),
          'polyline': '',
        };
        _polylinePoints = [pLoc, dLoc];
      });

      // Fit map bounds
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
      // Insert Ride
      final rideRes = await _supabase.from('rides').insert({
        'rider_id': userId,
        'status': 'requested',
        'pickup_latitude': pLoc.latitude,
        'pickup_longitude': pLoc.longitude,
        'pickup_address': _pickupAddress ?? 'Custom Pickup Location',
        'drop_latitude': dLoc.latitude,
        'drop_longitude': dLoc.longitude,
        'drop_address': _dropAddress ?? 'Custom Destination',
        'distance_km': _routeEstimate!['distance_km'],
        'duration_mins': _routeEstimate!['duration_mins'],
        'fare': _routeEstimate!['fare'],
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
          const SnackBar(content: Text('No drivers nearby. Retrying search...')),
        );
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
              _showCompletedRatingSheet();
              _rideSubscription?.unsubscribe();
            } else if (_activeRide?['status'] == 'cancelled') {
              _handleRideCancelled();
            } else if (_activeRide?['driver_id'] != null) {
              _listenToDriverGPS(_activeRide!['driver_id']);
            }
          },
        );
    _rideSubscription!.subscribe();
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

  Future<void> _loadIncomingRequests() async {
    try {
      final data = await _supabase
          .from('rides')
          .select('*')
          .eq('status', 'requested')
          .order('created_at', ascending: false);

      setState(() {
        _incomingRequests = List<Map<String, dynamic>>.from(data);
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
        final rId = _activeRide?['rider_id'];
        final fareAmount = double.parse(_activeRide?['fare'].toString() ?? '0.0');
        if (rId != null && fareAmount > 0) {
          // Get rider balance
          final rProfile = await _supabase.from('profiles').select('wallet_balance').eq('id', rId).single();
          final currentBal = double.parse(rProfile['wallet_balance'].toString());
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isDriver ? 'Driver Dashboard' : 'JomRide',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink),
        ),
        backgroundColor: AppTheme.canvas,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.ink),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.ink),
            onPressed: () => _supabase.auth.signOut(),
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
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                      child: const Icon(Icons.location_on, color: Colors.green, size: 36),
                    ),
                  if (_dropLatLng != null)
                    Marker(
                      point: _dropLatLng!,
                      child: const Icon(Icons.flag, color: Colors.red, size: 36),
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
                        color: _mapSelectMode == 'pickup' ? Colors.green : Colors.red,
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
    if (_activeRide != null) {
      final status = _activeRide!['status'];
      return Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(hasShadow: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Trip Status: ${status.toString().toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.ink),
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(rideId: _activeRide!['id'])),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('From: ${_activeRide!['pickup_address']}'),
            Text('To: ${_activeRide!['drop_address']}'),
            Text('Fare: RM ${double.parse(_activeRide!['fare'].toString()).toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.canvasSoft, foregroundColor: AppTheme.ink),
                    child: const Text('🔗 Share Trip'),
                  ),
                ),
              ],
            ),
            if (status == 'requested' || status == 'accepted' || status == 'arrived') ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    foregroundColor: Colors.red,
                    elevation: 0,
                  ),
                  onPressed: () => _updateRideStatus(_activeRide!['id'], 'cancelled'),
                  child: const Text('Cancel Ride'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(hasShadow: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Request a Ride',
            style: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.ink),
          ),
          const SizedBox(height: 12),
          
          // Presets (Quick Chips)
          const Text(
            'Quick Presets:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _mockLocations.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ActionChip(
                    backgroundColor: AppTheme.canvasSoft,
                    side: const BorderSide(color: AppTheme.canvasSoft),
                    label: Text(entry.key.split(' ').first), // Short label
                    onPressed: () {
                      setState(() {
                        if (_pickupLatLng == null || _mapSelectMode == 'pickup') {
                          _pickupLatLng = entry.value;
                          _pickupAddress = entry.key;
                          _pickupController.text = entry.key;
                          _mapSelectMode = null;
                        } else {
                          _dropLatLng = entry.value;
                          _dropAddress = entry.key;
                          _dropController.text = entry.key;
                          _mapSelectMode = null;
                        }
                      });
                      _calculateRoute();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),

          // Pickup Field
          TextField(
            controller: _pickupController,
            decoration: InputDecoration(
              labelText: 'Pickup Location',
              hintText: 'Search address or tap map...',
              prefixIcon: const Icon(Icons.location_on, color: Colors.green),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.grey),
                    tooltip: 'Choose on Map',
                    onPressed: () {
                      setState(() {
                        _mapSelectMode = 'pickup';
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: AppTheme.primary),
                    onPressed: () => _searchForAddress(_pickupController.text, 'pickup'),
                  ),
                ],
              ),
            ),
            onSubmitted: (val) => _searchForAddress(val, 'pickup'),
          ),
          const SizedBox(height: 12),

          // Dropoff Field
          TextField(
            controller: _dropController,
            decoration: InputDecoration(
              labelText: 'Destination',
              hintText: 'Search address or tap map...',
              prefixIcon: const Icon(Icons.flag, color: Colors.red),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.map, color: Colors.grey),
                    tooltip: 'Choose on Map',
                    onPressed: () {
                      setState(() {
                        _mapSelectMode = 'drop';
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: AppTheme.primary),
                    onPressed: () => _searchForAddress(_dropController.text, 'drop'),
                  ),
                ],
              ),
            ),
            onSubmitted: (val) => _searchForAddress(val, 'drop'),
          ),

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
                color: AppTheme.canvasSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.canvasSoft),
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
                      style: const TextStyle(fontSize: 13),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12),
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
          // Preferences
          Row(
            children: [
              Checkbox(
                value: _womenOnly,
                onChanged: (val) => setState(() => _womenOnly = val ?? false),
              ),
              const Text('Women-only driver matching'),
            ],
          ),
          const SizedBox(height: 16),
          if (_calculatingRoute)
            const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          else if (_routeEstimate != null) ...[
            Text('Distance: ${_routeEstimate!['distance_km']} km'),
            Text('ETA: ${_routeEstimate!['duration_mins']} mins'),
            Text(
              'Fare Estimate: RM ${_routeEstimate!['fare'].toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.ink),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requestRide,
                child: const Text('Confirm Ride Booking'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Driver Bottom Sheet
  Widget _buildDriverSheet() {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(hasShadow: true),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _isOnline ? 'You are ONLINE' : 'You are OFFLINE',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _isOnline ? Colors.green : AppTheme.body),
              ),
              Switch(
                value: _isOnline,
                onChanged: _toggleOnline,
                activeThumbColor: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isOnline) ...[
            if (_incomingRequests.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Text('Searching for ride requests in Malaysia...'),
                ),
              )
            else ...[
              const Text('Incoming Requests:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SizedBox(
                height: 150,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _incomingRequests.length,
                  itemBuilder: (ctx, idx) {
                    final req = _incomingRequests[idx];
                    return Card(
                      color: AppTheme.canvasSoft,
                      child: ListTile(
                        title: Text('To: ${req['drop_address']}'),
                        subtitle: Text('Fare: RM ${req['fare']} | Dist: ${req['distance_km']}km'),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                          onPressed: () {
                            setState(() {
                              _activeRide = req;
                            });
                            _updateRideStatus(req['id'], 'accepted');
                          },
                          child: const Text('Accept'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]
          ],
          if (_activeRide != null && _activeRide!['status'] != 'requested') ...[
            const Divider(),
            Text('Active Job: Rider ID ${_activeRide!['rider_id'].toString().substring(0, 5)}'),
            Text('Pickup: ${_activeRide!['pickup_address']}'),
            Text('Drop-off: ${_activeRide!['drop_address']}'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (_activeRide!['status'] == 'accepted')
                      ElevatedButton(
                        onPressed: () => _updateRideStatus(_activeRide!['id'], 'arrived'),
                        child: const Text('Arrived at Pickup'),
                      ),
                    if (_activeRide!['status'] == 'arrived')
                      ElevatedButton(
                        onPressed: () => _updateRideStatus(_activeRide!['id'], 'picked_up'),
                        child: const Text('Start Trip'),
                      ),
                    if (_activeRide!['status'] == 'picked_up')
                      ElevatedButton(
                        onPressed: () => _updateRideStatus(_activeRide!['id'], 'completed'),
                        child: const Text('Complete Trip'),
                      ),
                    if (_activeRide!['status'] == 'accepted' || _activeRide!['status'] == 'arrived') ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () => _updateRideStatus(_activeRide!['id'], 'cancelled'),
                        child: const Text('Cancel Job'),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ChatScreen(rideId: _activeRide!['id'])),
                  ),
                ),
              ],
            ),
          ]
        ],
      ),
    );
  }
}
