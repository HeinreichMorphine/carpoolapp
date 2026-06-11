import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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

  // User Profile
  Map<String, dynamic>? _profile;
  bool _loadingProfile = true;

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
  String? _selectedPickup;
  String? _selectedDrop;
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
    if (_selectedPickup == null || _selectedDrop == null) return;
    setState(() {
      _calculatingRoute = true;
      _polylinePoints = [];
    });

    final pLoc = _mockLocations[_selectedPickup]!;
    final dLoc = _mockLocations[_selectedDrop]!;

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
          _polylinePoints = _decodePolyline(resData['polyline']);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
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

  Future<void> _requestRide() async {
    if (_routeEstimate == null) return;
    setState(() => _calculatingRoute = true);

    final pLoc = _mockLocations[_selectedPickup]!;
    final dLoc = _mockLocations[_selectedDrop]!;

    try {
      final userId = _supabase.auth.currentUser?.id;
      // Insert Ride
      final rideRes = await _supabase.from('rides').insert({
        'rider_id': userId,
        'status': 'requested',
        'pickup_latitude': pLoc.latitude,
        'pickup_longitude': pLoc.longitude,
        'pickup_address': _selectedPickup,
        'drop_latitude': dLoc.latitude,
        'drop_longitude': dLoc.longitude,
        'drop_address': _selectedDrop,
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No drivers nearby. Retrying search...')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _calculatingRoute = false);
    }
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
    final pLoc = _mockLocations[_selectedPickup] ?? const LatLng(2.19, 102.25);
    
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
          isDriver ? 'Driver Dashboard' : 'Carpool Malaysia',
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
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.carpool.malaysia',
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
                  if (_selectedPickup != null && _mockLocations[_selectedPickup] != null)
                    Marker(
                      point: _mockLocations[_selectedPickup]!,
                      child: const Icon(Icons.location_on, color: Colors.green, size: 36),
                    ),
                  if (_selectedDrop != null && _mockLocations[_selectedDrop] != null)
                    Marker(
                      point: _mockLocations[_selectedDrop]!,
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
                      final url = 'http://localhost:8080/track/${_activeRide!['id']}';
                      launchUrl(Uri.parse(url));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.canvasSoft, foregroundColor: AppTheme.ink),
                    child: const Text('🔗 Share Trip'),
                  ),
                ),
              ],
            ),
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
          const SizedBox(height: 16),
          // Pickup Selector
          DropdownButtonFormField<String>(
            initialValue: _selectedPickup,
            hint: const Text('Select Pickup Location'),
            items: _mockLocations.keys.map((name) {
              return DropdownMenuItem(value: name, child: Text(name));
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedPickup = val);
              _calculateRoute();
            },
          ),
          const SizedBox(height: 12),
          // Dropoff Selector
          DropdownButtonFormField<String>(
            initialValue: _selectedDrop,
            hint: const Text('Select Destination'),
            items: _mockLocations.keys.map((name) {
              return DropdownMenuItem(value: name, child: Text(name));
            }).toList(),
            onChanged: (val) {
              setState(() => _selectedDrop = val);
              _calculateRoute();
            },
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
