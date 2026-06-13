import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String rideId;
  const ChatScreen({super.key, required this.rideId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _supabase = Supabase.instance.client;
  final _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  late RealtimeChannel _chatChannel;
  late RealtimeChannel _rideStatusChannel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToChat();
    _subscribeToRideStatus();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _supabase.removeChannel(_chatChannel);
    _supabase.removeChannel(_rideStatusChannel);
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final data = await _supabase
          .from('chats')
          .select('*')
          .eq('ride_id', widget.rideId)
          .order('created_at', ascending: true);

      setState(() {
        _messages.addAll(List<Map<String, dynamic>>.from(data));
      });
    } catch (e) {
      debugPrint('Error loading chats: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _subscribeToChat() {
    _chatChannel = _supabase.channel('ride-chats-${widget.rideId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'chats',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'ride_id',
          value: widget.rideId,
        ),
        callback: (payload) {
          if (mounted) {
            setState(() {
              _messages.add(payload.newRecord);
            });
          }
        },
      );
    _chatChannel.subscribe();
  }

  void _subscribeToRideStatus() {
    _rideStatusChannel = _supabase.channel('ride-status-${widget.rideId}')
      .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'rides',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.rideId,
        ),
        callback: (payload) {
          if (mounted) {
            final status = payload.newRecord['status'];
            if (status == 'completed') {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Trip completed safely. Chat automatically closed.'),
                  backgroundColor: AppTheme.primary,
                ),
              );
            }
          }
        },
      );
    _rideStatusChannel.subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _supabase.from('chats').insert({
        'ride_id': widget.rideId,
        'sender_id': userId,
        'message': text,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e'), backgroundColor: AppTheme.accent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'In-App Chat',
          style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
                : _messages.isEmpty
                    ? Text('No messages yet. Send a greeting!', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (ctx, idx) {
                          final msg = _messages[idx];
                          final isMe = msg['sender_id'] == currentUserId;
                          return _chatBubble(msg['message'] ?? '', isMe);
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'Type message...',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).primaryColor,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _chatBubble(String text, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: AppTheme.cardDecoration(
          context,
          radius: AppTheme.radiusLg,
        ).copyWith(
          color: isMe ? Theme.of(context).primaryColor : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? Colors.white : Theme.of(context).colorScheme.onSurface,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}
