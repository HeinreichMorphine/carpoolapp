import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/app_theme.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _supabase = Supabase.instance.client;
  double _balance = 0.0;
  bool _loading = false;
  final _amountController = TextEditingController();
  final _cardNoController = TextEditingController();
  final _cardExpiryController = TextEditingController();
  final _cardCvvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBalance();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _cardNoController.dispose();
    _cardExpiryController.dispose();
    _cardCvvController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final data = await _supabase
          .from('profiles')
          .select('wallet_balance')
          .eq('id', userId)
          .single();
      
      setState(() {
        _balance = double.parse(data['wallet_balance'].toString());
      });
    } catch (e) {
      debugPrint('Error loading wallet balance: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _topUpWallet(double amount) async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final newBalance = _balance + amount;
      await _supabase
          .from('profiles')
          .update({'wallet_balance': newBalance})
          .eq('id', userId);

      setState(() {
        _balance = newBalance;
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Top-up of RM ${amount.toStringAsFixed(2)} successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Top-up failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showTopUpBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            top: 24,
            left: 24,
            right: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Top up wallet',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.ink,
                  ),
                ),
                const SizedBox(height: 16),
                // Pre-defined amounts
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [10, 20, 50, 100].map((amt) {
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.canvasSoft,
                        foregroundColor: AppTheme.ink,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                        ),
                      ),
                      onPressed: () {
                        _amountController.text = amt.toString();
                      },
                      child: Text('RM $amt'),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (RM)',
                    hintText: 'Enter custom amount',
                  ),
                ),
                const SizedBox(height: 16),
                // Mock Credit Card Inputs
                TextFormField(
                  controller: _cardNoController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Card Number',
                    hintText: '4111 1111 1111 1111',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cardExpiryController,
                        decoration: const InputDecoration(labelText: 'Expiry Date', hintText: 'MM/YY'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _cardCvvController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'CVV', hintText: '123'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final amount = double.tryParse(_amountController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid amount')),
                        );
                        return;
                      }
                      _topUpWallet(amount);
                    },
                    child: const Text('Confirm Top Up (Stripe Sandbox)'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Wallet',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.ink),
        ),
        backgroundColor: AppTheme.canvas,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.ink),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Balance Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: AppTheme.cardDecoration(
                      color: AppTheme.primary,
                      radius: AppTheme.radiusXl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Balance',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: AppTheme.mute,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RM ${_balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: AppTheme.onPrimary,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.canvas,
                            foregroundColor: AppTheme.ink,
                          ),
                          onPressed: _showTopUpBottomSheet,
                          child: const Text('Top Up'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Transaction History',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.ink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // List of Mock Transaction Items
                  Expanded(
                    child: ListView(
                      children: [
                        _transactionItem('Top Up (Stripe)', '+ RM 50.00', 'June 11, 2026', true),
                        _transactionItem('Ride Payment (R-229)', '- RM 18.50', 'June 10, 2026', false),
                        _transactionItem('Ride Earnings (D-102)', '+ RM 22.00', 'June 09, 2026', true),
                      ],
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _transactionItem(String title, String amount, String date, bool isCredit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(color: AppTheme.canvasSoft, radius: AppTheme.radiusMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.ink),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: AppTheme.body),
              ),
            ],
          ),
          Text(
            amount,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isCredit ? Colors.green[700] : Colors.red[700],
            ),
          ),
        ],
      ),
    );
  }
}
