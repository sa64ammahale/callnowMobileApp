import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';
import 'package:callnow_new/widgets/callback_alert_dialog.dart';

class FollowUpScreen extends StatefulWidget {
  final int initialTabIndex;

  const FollowUpScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<FollowUpScreen> createState() => _FollowUpScreenState();
}

class _FollowUpScreenState extends State<FollowUpScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<FollowupModel> _applySearch(List<FollowupModel> list) {
    if (_searchQuery.isEmpty) return list;
    return list.where((f) {
      final name = f.customerName.toLowerCase();
      final phone = f.phoneNumber.toLowerCase();
      final company = (f.company ?? '').toLowerCase();
      final notes = f.notes.toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          company.contains(_searchQuery) ||
          notes.contains(_searchQuery);
    }).toList();
  }

  Future<void> _makeCall(FollowupModel followup) async {
    final cleanPhone = followup.phoneNumber.replaceAll(RegExp(r'\D'), '');
    try {
      await CallTrackingService.makePhoneCall(cleanPhone);
    } catch (_) {
      final uri = Uri.parse('tel:$cleanPhone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<void> _openWhatsApp(FollowupModel followup) async {
    final cleanPhone = followup.phoneNumber.replaceAll(RegExp(r'\D'), '');
    final msg =
        'Hello ${followup.customerName}, following up on our previous conversation.';
    await CallTrackingService.openWhatsApp(cleanPhone, message: msg);
  }

  void _showAddFollowupModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final companyCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime scheduledTime = DateTime.now().add(const Duration(hours: 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Schedule Client Callback',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Customer Name *',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Number * (10 digits)',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: companyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Company / Loan Type (Optional)',
                        prefixIcon: Icon(Icons.business_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Callback Reason / Notes',
                        prefixIcon: Icon(Icons.sticky_note_2_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Quick Time Chips
                    const Text(
                      'Callback Time:',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ActionChip(
                            label: const Text('+15m'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(minutes: 15));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('+30m'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(minutes: 30));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('+1 Hour'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(hours: 1));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('+2 Hours'),
                            onPressed: () => setModalState(() {
                              scheduledTime =
                                  DateTime.now().add(const Duration(hours: 2));
                            }),
                          ),
                          const SizedBox(width: 6),
                          ActionChip(
                            label: const Text('Tomorrow 10 AM'),
                            onPressed: () => setModalState(() {
                              final tom =
                                  DateTime.now().add(const Duration(days: 1));
                              scheduledTime =
                                  DateTime(tom.year, tom.month, tom.day, 10, 0);
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Current Selected Time Display & Custom Picker
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final d = await showDatePicker(
                          context: context,
                          initialDate: scheduledTime,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 90)),
                        );
                        if (d != null && context.mounted) {
                          final t = await showTimePicker(
                            context: context,
                            initialTime:
                                TimeOfDay.fromDateTime(scheduledTime),
                          );
                          if (t != null) {
                            setModalState(() {
                              scheduledTime = DateTime(
                                  d.year, d.month, d.day, t.hour, t.minute);
                            });
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '⏰ ${scheduledTime.day}/${scheduledTime.month}/${scheduledTime.year} at ${scheduledTime.hour.toString().padLeft(2, '0')}:${scheduledTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                            const Text(
                              'Change',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save Button
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final name = nameCtrl.text.trim();
                        final phone = phoneCtrl.text.trim();
                        if (name.isEmpty || phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Name and Phone are required'),
                            ),
                          );
                          return;
                        }

                        await FollowupService.instance.addFollowup(
                          customerName: name,
                          phoneNumber: phone,
                          company: companyCtrl.text.trim().isNotEmpty
                              ? companyCtrl.text.trim()
                              : null,
                          notes: notesCtrl.text.trim(),
                          scheduledTime: scheduledTime,
                        );

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Callback scheduled & reminder set!'),
                              backgroundColor: Color(0xFF16A34A),
                            ),
                          );
                        }
                      },
                      child: const Text(
                        'Schedule & Set Notification',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FollowupService.instance,
      builder: (context, _) {
        final overdue = FollowupService.instance.getOverdue();
        final today = FollowupService.instance.getToday();
        final upcoming = FollowupService.instance.getUpcoming();
        final completed = FollowupService.instance.getCompleted();
        final pending = FollowupService.instance.getPending();

        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                Icon(Icons.calendar_month, size: 22, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Text(
                  'Follow-Up Pipeline',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_alarm, color: Color(0xFF2563EB)),
                tooltip: 'Add Callback',
                onPressed: () => _showAddFollowupModal(context),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(100),
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search follow-ups by name, phone, notes...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          contentPadding: EdgeInsets.zero,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Tab Bar
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: const Color(0xFF2563EB),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF2563EB),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    tabs: [
                      Tab(text: 'Due / Overdue (${overdue.length})'),
                      Tab(text: "Today's (${today.length})"),
                      Tab(text: 'Upcoming (${upcoming.length})'),
                      Tab(text: 'Completed (${completed.length})'),
                      Tab(text: 'All Pending (${pending.length})'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          body: Column(
            children: [
              // KPI Summary Row
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Row(
                  children: [
                    _buildKpiCard(
                      'Overdue',
                      overdue.length.toString(),
                      const Color(0xFFDC2626),
                      const Color(0xFFFEF2F2),
                      () => _tabController.animateTo(0),
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      "Today",
                      today.length.toString(),
                      const Color(0xFFD97706),
                      const Color(0xFFFFFBEB),
                      () => _tabController.animateTo(1),
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      'Upcoming',
                      upcoming.length.toString(),
                      const Color(0xFF2563EB),
                      const Color(0xFFEFF6FF),
                      () => _tabController.animateTo(2),
                    ),
                    const SizedBox(width: 8),
                    _buildKpiCard(
                      'Done',
                      completed.length.toString(),
                      const Color(0xFF16A34A),
                      const Color(0xFFF0FDF4),
                      () => _tabController.animateTo(3),
                    ),
                  ],
                ),
              ),
              const Divider(height: 12),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFollowupList(_applySearch(overdue), emptyMsg: 'No overdue follow-ups! You are caught up 🎉'),
                    _buildFollowupList(_applySearch(today), emptyMsg: 'No follow-ups scheduled for today.'),
                    _buildFollowupList(_applySearch(upcoming), emptyMsg: 'No upcoming follow-ups scheduled.'),
                    _buildFollowupList(_applySearch(completed), emptyMsg: 'No completed follow-ups yet.'),
                    _buildFollowupList(_applySearch(pending), emptyMsg: 'No pending follow-ups in queue.'),
                  ],
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddFollowupModal(context),
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_alarm),
            label: const Text('Add Follow-Up'),
          ),
        );
      },
    );
  }

  Widget _buildKpiCard(
    String label,
    String count,
    Color textColor,
    Color bgColor,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: textColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Text(
                count,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFollowupList(List<FollowupModel> list, {required String emptyMsg}) {
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_available, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                emptyMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        return _buildFollowupCard(item);
      },
    );
  }

  Widget _buildFollowupCard(FollowupModel item) {
    final isDone = item.status == 'completed';
    final isOverdue = item.isOverdue;
    final scheduledStr =
        '${item.scheduledTime.day}/${item.scheduledTime.month} at ${item.scheduledTime.hour.toString().padLeft(2, '0')}:${item.scheduledTime.minute.toString().padLeft(2, '0')}';

    Color cardBorderColor = const Color(0xFFE2E8F0);
    Color badgeBg = const Color(0xFFEFF6FF);
    Color badgeColor = const Color(0xFF2563EB);

    if (isDone) {
      cardBorderColor = const Color(0xFFCBD5E1);
      badgeBg = const Color(0xFFF1F5F9);
      badgeColor = const Color(0xFF64748B);
    } else if (isOverdue) {
      cardBorderColor = const Color(0xFFFCA5A5);
      badgeBg = const Color(0xFFFEF2F2);
      badgeColor = const Color(0xFFDC2626);
    } else if (item.isToday) {
      cardBorderColor = const Color(0xFFFCD34D);
      badgeBg = const Color(0xFFFFFBEB);
      badgeColor = const Color(0xFFD97706);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cardBorderColor),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Name, Company, Urgency Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDone ? const Color(0xFF64748B) : const Color(0xFF0F172A),
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (item.company != null && item.company!.isNotEmpty)
                        Text(
                          item.company!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDone ? Icons.check_circle : (isOverdue ? Icons.error_outline : Icons.alarm),
                        size: 13,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isDone ? 'Completed' : item.timeRemainingText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Middle Row: Phone & Scheduled Time
            Row(
              children: [
                const Icon(Icons.phone, size: 14, color: Color(0xFF64748B)),
                const SizedBox(width: 4),
                Text(
                  item.phoneNumber,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.calendar_today, size: 13, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Text(
                  scheduledStr,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),

            if (item.notes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  '“${item.notes}”',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF475569),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Bottom Action Row
            Row(
              children: [
                // Quick Call Button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _makeCall(item),
                    icon: const Icon(Icons.phone, size: 16),
                    label: const Text('Call Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // WhatsApp Button
                IconButton.filledTonal(
                  icon: const Icon(Icons.chat_bubble_outline, size: 16, color: Color(0xFF25D366)),
                  tooltip: 'WhatsApp',
                  onPressed: () => _openWhatsApp(item),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFDCFCE7),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(width: 6),

                // Snooze / Alert Modal
                IconButton.filledTonal(
                  icon: const Icon(Icons.notification_important_outlined, size: 16, color: Color(0xFF2563EB)),
                  tooltip: 'Open Alert Modal',
                  onPressed: () => CallbackAlertDialog.show(context, item),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFEFF6FF),
                    padding: const EdgeInsets.all(8),
                  ),
                ),
                const SizedBox(width: 6),

                // Complete Button
                if (!isDone)
                  IconButton.filledTonal(
                    icon: const Icon(Icons.check, size: 16, color: Color(0xFF16A34A)),
                    tooltip: 'Mark Done',
                    onPressed: () => FollowupService.instance.markCompleted(item.id),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF0FDF4),
                      padding: const EdgeInsets.all(8),
                    ),
                  ),

                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFF94A3B8)),
                  tooltip: 'Delete',
                  onPressed: () => FollowupService.instance.deleteFollowup(item.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

