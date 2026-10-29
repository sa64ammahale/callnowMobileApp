import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class LeadsScreen extends StatefulWidget {
  final VoidCallback? onOpenCallingDesk;
  final Function(Map<String, dynamic> lead)? onLeadCallRequested;

  const LeadsScreen({
    super.key,
    this.onOpenCallingDesk,
    this.onLeadCallRequested,
  });

  @override
  State<LeadsScreen> createState() => _LeadsScreenState();
}

class _LeadsScreenState extends State<LeadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allLeads = [];
  List<Map<String, dynamic>> _filteredLeads = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _activeFilter = 'all'; // 'all', 'not_called', 'called'

  @override
  void initState() {
    super.initState();
    _fetchLeads();
    _searchController.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLeads() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batch = await ApiService.getBatchLeads(limit: 50);
      if (mounted) {
        setState(() {
          _allLeads = batch;
          _isLoading = false;
        });
        _applyFilters();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredLeads = _allLeads.where((lead) {
        final name = (lead['name'] ?? lead['customer_name'] ?? '').toString().toLowerCase();
        final mobile = (lead['mobile'] ?? lead['customer_mobile'] ?? '').toString();
        final company = (lead['company'] ?? lead['customer_company'] ?? '').toString().toLowerCase();
        final lastStatus = (lead['last_status'] ?? '').toString().toLowerCase();

        final matchesSearch = query.isEmpty ||
            name.contains(query) ||
            mobile.contains(query) ||
            company.contains(query);

        if (!matchesSearch) return false;

        if (_activeFilter == 'not_called') {
          return lastStatus == 'not called' || lastStatus.isEmpty;
        } else if (_activeFilter == 'called') {
          return lastStatus.isNotEmpty && lastStatus != 'not called';
        }
        return true;
      }).toList();
    });
  }

  Future<void> _callLead(Map<String, dynamic> lead) async {
    final mobile = (lead['mobile'] ?? lead['customer_mobile'] ?? '').toString();
    if (mobile.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No mobile number available for this contact.')),
      );
      return;
    }

    if (widget.onLeadCallRequested != null) {
      widget.onLeadCallRequested!(lead);
    } else {
      await CallTrackingService.makePhoneCall(mobile);
      if (widget.onOpenCallingDesk != null) {
        widget.onOpenCallingDesk!();
      }
    }
  }

  Future<void> _messageWhatsApp(Map<String, dynamic> lead) async {
    final mobile = (lead['mobile'] ?? lead['customer_mobile'] ?? '').toString();
    final name = (lead['name'] ?? lead['customer_name'] ?? 'Sir/Madam').toString();
    if (mobile.isEmpty) return;

    final msg = 'Hello $name, I am connecting with you regarding your enquiry with InCredit Solutions.';
    await CallTrackingService.openWhatsApp(mobile, message: msg);
  }

  void _showLeadDetails(Map<String, dynamic> lead) {
    final name = (lead['name'] ?? lead['customer_name'] ?? 'Lead Details').toString();
    final mobile = (lead['mobile'] ?? lead['customer_mobile'] ?? 'N/A').toString();
    final company = (lead['company'] ?? lead['customer_company'] ?? 'Individual').toString();
    final pkg = (lead['package'] ?? lead['customer_package'] ?? 'General Enquiry').toString();
    final otherInfo = (lead['other_info'] ?? '').toString();
    final status = (lead['last_status'] ?? 'Not Called').toString();
    final uploadTime = (lead['upload_time'] ?? '').toString();
    final source = (lead['source'] ?? 'TEMPORARY').toString().toUpperCase();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      source,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                company,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Divider(),
              _detailRow(Icons.phone, 'Mobile', mobile),
              _detailRow(Icons.currency_rupee, 'Package / Loan Amount', pkg),
              if (otherInfo.isNotEmpty) _detailRow(Icons.info_outline, 'Other Info', otherInfo),
              _detailRow(Icons.flag_outlined, 'Status', status),
              if (uploadTime.isNotEmpty) _detailRow(Icons.calendar_today_outlined, 'Assigned On', uploadTime),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _messageWhatsApp(lead);
                      },
                      icon: const Icon(Icons.chat, color: Colors.green),
                      label: const Text('WhatsApp', style: TextStyle(color: Colors.green)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Colors.green),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _callLead(lead);
                      },
                      icon: const Icon(Icons.phone),
                      label: const Text('Call Now'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final notCalledCount = _allLeads.where((l) => (l['last_status'] ?? '').toString().toLowerCase() == 'not called').length;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchLeads,
        child: Column(
          children: [
            // Header stats card
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade800, Colors.indigo.shade900],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCol('Total In Queue', _allLeads.length.toString(), Colors.white),
                    Container(height: 32, width: 1, color: Colors.white24),
                    _buildStatCol('Not Called', notCalledCount.toString(), Colors.orangeAccent),
                    Container(height: 32, width: 1, color: Colors.white24),
                    _buildStatCol('Showing', _filteredLeads.length.toString(), Colors.lightGreenAccent),
                  ],
                ),
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search leads by name, phone or company...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: [
                  _filterChip('all', 'All Leads (${_allLeads.length})'),
                  const SizedBox(width: 8),
                  _filterChip('not_called', 'Not Called ($notCalledCount)'),
                  const SizedBox(width: 8),
                  _filterChip('called', 'Called (${_allLeads.length - notCalledCount})'),
                ],
              ),
            ),
            const Divider(height: 16),

            // Leads List / State
            Expanded(
              child: _buildBody(colorScheme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCol(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _filterChip(String id, String label) {
    final isSelected = _activeFilter == id;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _activeFilter = id);
          _applyFilters();
        }
      },
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(
                'Failed to load leads: $_errorMessage',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchLeads,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredLeads.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search_outlined, size: 54, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              const Text(
                'No leads found matching criteria',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _searchController.text.isNotEmpty
                    ? 'Try clearing the search query.'
                    : 'Pull down to refresh assigned leads batch from server.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: _filteredLeads.length,
      itemBuilder: (context, index) {
        final lead = _filteredLeads[index];
        return _buildLeadCard(context, lead, colorScheme);
      },
    );
  }

  Widget _buildLeadCard(BuildContext context, Map<String, dynamic> lead, ColorScheme colorScheme) {
    final name = (lead['name'] ?? lead['customer_name'] ?? 'Unnamed Lead').toString();
    final mobile = (lead['mobile'] ?? lead['customer_mobile'] ?? '').toString();
    final company = (lead['company'] ?? lead['customer_company'] ?? '').toString();
    final pkg = (lead['package'] ?? lead['customer_package'] ?? '').toString();
    final lastStatus = (lead['last_status'] ?? 'Not Called').toString();
    final isNotCalled = lastStatus.toLowerCase() == 'not called';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showLeadDetails(lead),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Lead Name & Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isNotCalled
                        ? Colors.blue.withValues(alpha: 0.15)
                        : Colors.green.withValues(alpha: 0.15),
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'L',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isNotCalled ? Colors.blue.shade800 : Colors.green.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (company.isNotEmpty)
                          Text(
                            company,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isNotCalled ? Colors.orange.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isNotCalled ? Colors.orange.shade300 : Colors.green.shade300,
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      lastStatus,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isNotCalled ? Colors.orange.shade900 : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Phone & Package details row
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    mobile,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  if (pkg.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    Icon(Icons.currency_rupee, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        pkg,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Quick Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _messageWhatsApp(lead),
                    icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                    label: const Text('WhatsApp', style: TextStyle(fontSize: 12, color: Colors.green)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      side: const BorderSide(color: Colors.green, width: 0.8),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _callLead(lead),
                    icon: const Icon(Icons.phone_in_talk, size: 16),
                    label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

