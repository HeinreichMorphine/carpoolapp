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

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToChat();
  }

  @override
  void dispose() {
    _msgController.dispose();
    _supabase.removeChannel(_chatChannel);
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
          SnackBar(content: Text('Failed to send message: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'In-App Chat',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink),
        ),
        backgroundColor: AppTheme.canvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet. Send a greeting!'))
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
            color: AppTheme.canvas,
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
                  color: AppTheme.primary,
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
          color: isMe ? AppTheme.primary : AppTheme.canvasSoft,
          radius: AppTheme.radiusLg,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isMe ? AppTheme.onPrimary : AppTheme.ink,
            fontFamily: 'Inter',
          ),
        ),
      ),
    );
  }
}
