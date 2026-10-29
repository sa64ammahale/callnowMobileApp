import 'package:flutter/material.dart';
import 'package:callnow_new/services/api_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class CallReportsScreen extends StatefulWidget {
  const CallReportsScreen({super.key});

  @override
  State<CallReportsScreen> createState() => _CallReportsScreenState();
}

class _CallReportsScreenState extends State<CallReportsScreen> {
  String _selectedPeriod = 'today';
  String _selectedTimingTier = 'all';
  String _selectedStatus = 'all';
  final TextEditingController _searchController = TextEditingController();

  DateTimeRange? _customDateRange;

  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _summaryData;
  List<Map<String, dynamic>> _callLogs = [];

  final List<Map<String, String>> _periodOptions = [
    {'id': 'today', 'label': 'Today'},
    {'id': 'yesterday', 'label': 'Yesterday'},
    {'id': 'week', 'label': 'This Week'},
    {'id': 'month', 'label': 'This Month'},
    {'id': 'custom', 'label': 'Custom'},
  ];

  final List<Map<String, String>> _statusFilters = [
    {'id': 'all', 'label': 'All Calls'},
    {'id': 'Interested', 'label': 'Interested'},
    {'id': 'Follow-up', 'label': 'Follow-up'},
    {'id': 'Converted', 'label': 'Converted'},
    {'id': 'Busy', 'label': 'Busy / Missed'},
  ];

  @override
  void initState() {
    super.initState();
    _loadReportData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    // Debounce search
    setState(() {});
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String? dateFrom;
      String? dateTo;
      if (_selectedPeriod == 'custom' && _customDateRange != null) {
        dateFrom = _customDateRange!.start.toIso8601String().substring(0, 10);
        dateTo = _customDateRange!.end.toIso8601String().substring(0, 10);
      }

      final summary = await ApiService.getCallReportSummary(
        period: _selectedPeriod,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );

      final historyResponse = await ApiService.getCallHistory(
        period: _selectedPeriod,
        timingTier: _selectedTimingTier != 'all' ? _selectedTimingTier : null,
        status: _selectedStatus != 'all' ? _selectedStatus : null,
        dateFrom: dateFrom,
        dateTo: dateTo,
        search: _searchController.text.trim().isNotEmpty ? _searchController.text.trim() : null,
        limit: 50,
      );

      final rawCalls = historyResponse['data'] ?? historyResponse['calls'];
      final List<Map<String, dynamic>> parsedCalls = (rawCalls is List)
          ? rawCalls
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : [];

      if (mounted) {
        setState(() {
          _summaryData = summary;
          _callLogs = parsedCalls;
          _isLoading = false;
        });
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

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedPeriod = 'custom';
      });
      _loadReportData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadReportData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Period Selector Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _periodOptions.map((opt) {
                    final isSelected = _selectedPeriod == opt['id'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          opt['id'] == 'custom' && _customDateRange != null
                              ? '${_customDateRange!.start.day}/${_customDateRange!.start.month} - ${_customDateRange!.end.day}/${_customDateRange!.end.month}'
                              : opt['label']!,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        onSelected: (val) {
                          if (opt['id'] == 'custom') {
                            _pickCustomDateRange();
                          } else {
                            setState(() {
                              _selectedPeriod = opt['id']!;
                              _customDateRange = null;
                            });
                            _loadReportData();
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              if (_isLoading && _summaryData == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null && _summaryData == null)
                _buildErrorCard()
              else ...[
                // Top KPI Summary Metrics Grid
                _buildKpiMetricsGrid(colorScheme),
                const SizedBox(height: 16),

                // Spoken Duration Timing Breakdown
                _buildTimingTiersCard(colorScheme),
                const SizedBox(height: 20),

                // Dialed Calls Feed Header & Search
                const Text(
                  'Dialed Call History',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),

                // Search Bar
                TextField(
                  controller: _searchController,
                  onSubmitted: (_) => _loadReportData(),
                  decoration: InputDecoration(
                    hintText: 'Search by client name, mobile, notes...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _loadReportData();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),

                // Status Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _statusFilters.map((flt) {
                      final isSelected = _selectedStatus == flt['id'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 6.0),
                        child: ChoiceChip(
                          label: Text(flt['label']!, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          onSelected: (val) {
                            if (val) {
                              setState(() => _selectedStatus = flt['id']!);
                              _loadReportData();
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 14),

                // Call Logs List
                if (_callLogs.isEmpty)
                  _buildEmptyCallLogsCard()
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _callLogs.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      return _buildCallLogItem(context, _callLogs[index]);
                    },
                  ),
              ],
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: Colors.red.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 36),
            const SizedBox(height: 8),
            Text(
              'Error loading reports: $_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadReportData,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(dynamic rawSeconds) {
    final totalSeconds = rawSeconds is int ? rawSeconds : (int.tryParse(rawSeconds?.toString() ?? '') ?? 0);
    if (totalSeconds <= 0) return '0s';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    if (minutes == 0) return '${seconds}s';
    if (seconds == 0) return '${minutes}m';
    return '${minutes}m ${seconds}s';
  }

  Widget _buildKpiMetricsGrid(ColorScheme colorScheme) {
    final summary = _summaryData ?? {};
    final totalCalls = summary['total_calls'] ?? 0;
    final rawDuration = summary['total_duration_seconds'] ?? summary['total_duration'] ?? 0;
    final totalDuration = summary['total_duration_formatted'] ?? _formatDuration(rawDuration);
    final connectionRate = summary['connection_rate_percent'] ?? summary['connection_rate'] ?? 0;
    final avgDuration = summary['avg_duration_seconds'] ?? summary['avg_duration'] ?? 0;

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: [
        _buildMetricTile(
          title: 'Total Dialed',
          value: totalCalls.toString(),
          subtitle: 'calls completed',
          icon: Icons.phone_forwarded,
          iconColor: Colors.blue,
          onTap: () {
            setState(() {
              _selectedStatus = 'all';
              _selectedTimingTier = 'all';
            });
            _loadReportData();
          },
        ),
        _buildMetricTile(
          title: 'Total Talk Time',
          value: totalDuration.toString(),
          subtitle: 'cumulative spoken',
          icon: Icons.timer_outlined,
          iconColor: Colors.teal,
          onTap: () {
            setState(() {
              _selectedTimingTier = 'conversation';
            });
            _loadReportData();
          },
        ),
        _buildMetricTile(
          title: 'Connection Rate',
          value: '$connectionRate%',
          subtitle: 'picked up by clients',
          icon: Icons.check_circle_outline,
          iconColor: Colors.green,
          onTap: () {
            setState(() {
              _selectedStatus = 'all';
            });
            _loadReportData();
          },
        ),
        _buildMetricTile(
          title: 'Avg Duration',
          value: '${avgDuration}s',
          subtitle: 'per call dialed',
          icon: Icons.speed_rounded,
          iconColor: Colors.purple,
          onTap: () {
            setState(() {
              _selectedTimingTier = 'conversation';
            });
            _loadReportData();
          },
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Icon(icon, size: 20, color: iconColor),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: iconColor,
                    ),
                  ),
                  Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimingTiersCard(ColorScheme colorScheme) {
    final summary = _summaryData ?? {};
    final rawTiers = summary['timing_tiers'];
    final Map tiers = rawTiers is Map ? rawTiers : {};
    final notConnected = int.tryParse((tiers['not_connected'] ?? tiers['notConnected'])?.toString() ?? '0') ?? 0;
    final shortCalls = int.tryParse((tiers['connected_short'] ?? tiers['short_call'])?.toString() ?? '0') ?? 0;
    final conversations = int.tryParse((tiers['connected_conversation'] ?? tiers['conversation'])?.toString() ?? '0') ?? 0;
    final total = notConnected + shortCalls + conversations;

    final double convoPct = total > 0 ? (conversations / total) * 100 : 0.0;
    final double shortPct = total > 0 ? (shortCalls / total) * 100 : 0.0;
    final double notConnPct = total > 0 ? (notConnected / total) * 100 : 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Spoken Duration Classification',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Icon(Icons.pie_chart_outline, size: 20, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Sharp categorization based on actual seconds spoken with client',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 14),

            // Segmented Distribution Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: total == 0
                    ? Container(color: Colors.grey.shade300)
                    : Row(
                        children: [
                          if (conversations > 0)
                            Expanded(
                              flex: conversations,
                              child: Container(color: Colors.green.shade600),
                            ),
                          if (shortCalls > 0)
                            Expanded(
                              flex: shortCalls,
                              child: Container(color: Colors.amber.shade600),
                            ),
                          if (notConnected > 0)
                            Expanded(
                              flex: notConnected,
                              child: Container(color: Colors.red.shade400),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // Interactive 3-tier chips
            Row(
              children: [
                Expanded(
                  child: _buildTierFilterButton(
                    label: 'Convo (>20s)',
                    count: conversations,
                    percentage: convoPct,
                    color: Colors.green,
                    tierId: 'conversation',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTierFilterButton(
                    label: 'Short (1-20s)',
                    count: shortCalls,
                    percentage: shortPct,
                    color: Colors.amber.shade800,
                    tierId: 'short_call',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTierFilterButton(
                    label: 'Missed (0s)',
                    count: notConnected,
                    percentage: notConnPct,
                    color: Colors.red.shade600,
                    tierId: 'not_connected',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierFilterButton({
    required String label,
    required int count,
    required double percentage,
    required Color color,
    required String tierId,
  }) {
    final isSelected = _selectedTimingTier == tierId;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedTimingTier = isSelected ? 'all' : tierId;
        });
        _loadReportData();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCallLogsCard() {
    return Card(
      elevation: 0,
      color: Colors.grey.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 36.0, horizontal: 20.0),
        child: Column(
          children: [
            Icon(Icons.call_end_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No dialed calls found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            SizedBox(height: 4),
            Text(
              'Calls you log in the Calling Desk will automatically show up here with sharp duration metrics.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallLogItem(BuildContext context, Map<String, dynamic> call) {
    final name = (call['customer_name'] ?? call['client_name'] ?? call['name'] ?? 'Unnamed Client').toString();
    final mobile = (call['customer_mobile'] ?? call['phone_number'] ?? call['mobile'] ?? '').toString();
    final company = (call['customer_company'] ?? call['company'] ?? '').toString();
    final status = (call['call_status'] ?? call['status'] ?? 'Completed').toString();
    final duration = int.tryParse((call['call_duration'] ?? call['duration_seconds'])?.toString() ?? '0') ?? 0;
    final timingTier = (call['timing_classification'] ?? 'NOT_CONNECTED').toString();
    final createdAt = (call['call_time'] ?? call['created_at'] ?? '').toString();
    final notes = (call['notes'] ?? '').toString();
    final followup = (call['next_followup'] ?? '').toString();
    final source = (call['source'] ?? 'TEMPORARY').toString().toUpperCase();

    final isMain = source == 'MAIN';

    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showCallDetailsSheet(context, call),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Client Name, Source Badge, Status Chip
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (company.isNotEmpty)
                          Text(
                            company,
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                      ],
                    ),
                  ),
                  _buildStatusPill(status),
                ],
              ),
              const SizedBox(height: 10),

              // Middle Row: Mobile & Call Duration Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        mobile,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  _buildTimingTierBadge(timingTier, duration),
                ],
              ),

              if (notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    notes,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],

              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 6),

              // Bottom footer: Source & Timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isMain ? Icons.verified : Icons.inventory_2_outlined,
                        size: 12,
                        color: isMain ? Colors.blue : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMain ? 'Priority' : 'New Lead',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isMain ? Colors.blue.shade900 : Colors.orange.shade900,
                        ),
                      ),
                      if (followup.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.schedule, size: 12, color: Colors.orange),
                        const SizedBox(width: 3),
                        Text(
                          'Next: ${followup.length > 16 ? followup.substring(0, 16) : followup}',
                          style: const TextStyle(fontSize: 11, color: Colors.orange),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    _formatTimestamp(createdAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimingTierBadge(String tier, int seconds) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (tier) {
      case 'CONNECTED_CONVERSATION':
        bg = Colors.green.withValues(alpha: 0.15);
        fg = Colors.green.shade900;
        label = '${seconds}s • Convo';
        icon = Icons.chat_bubble;
        break;
      case 'CONNECTED_SHORT':
        bg = Colors.amber.withValues(alpha: 0.2);
        fg = Colors.amber.shade900;
        label = '${seconds}s • Short';
        icon = Icons.timer;
        break;
      case 'NOT_CONNECTED':
      default:
        bg = Colors.red.withValues(alpha: 0.1);
        fg = Colors.red.shade800;
        label = '0s • Missed';
        icon = Icons.phone_missed;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    Color color = Colors.blueGrey;
    final s = status.toLowerCase();
    if (s.contains('interest') || s.contains('hot')) {
      color = Colors.green;
    } else if (s.contains('follow')) {
      color = Colors.orange;
    } else if (s.contains('convert')) {
      color = Colors.teal;
    } else if (s.contains('busy') || s.contains('missed') || s.contains('cancel')) {
      color = Colors.amber.shade800;
    } else if (s.contains('voicemail') || s.contains('machine') || s.contains('ivr')) {
      color = Colors.deepPurple;
    } else if (s.contains('wrong') || s.contains('not interest')) {
      color = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  void _showCallDetailsSheet(BuildContext context, Map<String, dynamic> call) {
    final name = (call['customer_name'] ?? call['client_name'] ?? call['name'] ?? 'Unnamed Client').toString();
    final mobile = (call['customer_mobile'] ?? call['phone_number'] ?? call['mobile'] ?? '').toString();
    final company = (call['customer_company'] ?? call['company'] ?? 'Individual').toString();
    final pkg = (call['customer_package'] ?? call['package'] ?? 'General Enquiry').toString();
    final status = (call['call_status'] ?? call['status'] ?? 'Completed').toString();
    final duration = int.tryParse((call['call_duration'] ?? call['duration_seconds'])?.toString() ?? '0') ?? 0;
    final notes = (call['notes'] ?? 'No notes recorded').toString();
    final followup = (call['next_followup'] ?? '').toString();
    final source = (call['source'] ?? 'TEMPORARY').toString().toUpperCase();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('$company • $pkg', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      ],
                    ),
                  ),
                  _buildStatusPill(status),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),

              // Detail Tiles
              _buildDetailRow(Icons.phone, 'Mobile Number', mobile),
              _buildDetailRow(
                Icons.timer,
                'Call Duration',
                '$duration seconds',
              ),
              _buildDetailRow(Icons.label_outline, 'Lead Category', source == 'MAIN' ? 'Priority Client' : 'New Lead'),
              if (followup.isNotEmpty)
                _buildDetailRow(Icons.event, 'Scheduled Follow-up', followup),
              _buildDetailRow(Icons.notes, 'Telecaller Remarks', notes),

              const SizedBox(height: 20),

              // Quick Action Buttons: Redial & WhatsApp
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        CallTrackingService.openWhatsApp(
                          mobile,
                          message: 'Hello $name, following up regarding your enquiry on CallNow.',
                        );
                      },
                      icon: const Icon(Icons.chat, color: Colors.green),
                      label: const Text('WhatsApp', style: TextStyle(color: Colors.green)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        CallTrackingService.makePhoneCall(mobile);
                      },
                      icon: const Icon(Icons.call),
                      label: const Text('Call Again'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
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

  String _formatTimestamp(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return timestamp.length > 16 ? timestamp.substring(0, 16) : timestamp;
    }
  }
}
