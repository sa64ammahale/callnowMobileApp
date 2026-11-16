import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:callnow_new/model/followup_model.dart';
import 'package:callnow_new/services/followup_service.dart';
import 'package:callnow_new/services/call_tracking_service.dart';

class CallbackAlertDialog extends StatelessWidget {
  final FollowupModel followup;

  const CallbackAlertDialog({
    super.key,
    required this.followup,
  });

  static bool _isDialogShowing = false;

  static Future<void> show(BuildContext context, FollowupModel followup) async {
    if (_isDialogShowing) return;
    _isDialogShowing = true;
    FollowupService.instance.markPromptedInSession(followup.id);

    try {
      HapticFeedback.vibrate();
    } catch (_) {}

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CallbackAlertDialog(followup: followup),
    );

    _isDialogShowing = false;
  }

  Future<void> _makeCall(BuildContext context) async {
    final cleanPhone = followup.phoneNumber.replaceAll(RegExp(r'\D'), '');
    Navigator.of(context).pop();

    try {
      await CallTrackingService.makePhoneCall(cleanPhone);
    } catch (_) {
      final uri = Uri.parse('tel:$cleanPhone');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final cleanPhone = followup.phoneNumber.replaceAll(RegExp(r'\D'), '');
    final msg =
        'Hello ${followup.customerName}, I am following up on our previous conversation regarding your inquiry.';
    await CallTrackingService.openWhatsApp(cleanPhone, message: msg);
  }

  Future<void> _snooze(BuildContext context) async {
    await FollowupService.instance.snoozeFollowup(
      followup.id,
      duration: const Duration(minutes: 15),
    );
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏰ Callback snoozed for 15 minutes.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _reschedule(BuildContext context) async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );

    if (pickedDate == null || !context.mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );

    if (pickedTime == null || !context.mounted) return;

    final newDateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    await FollowupService.instance.rescheduleFollowup(
      followup.id,
      newDateTime,
    );

    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '📅 Follow-up rescheduled to ${newDateTime.day}/${newDateTime.month} at ${newDateTime.hour.toString().padLeft(2, '0')}:${newDateTime.minute.toString().padLeft(2, '0')}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markCompleted(BuildContext context) async {
    await FollowupService.instance.markCompleted(followup.id);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Callback marked as completed.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOverdue = followup.isOverdue;
    final scheduledStr =
        '${followup.scheduledTime.day}/${followup.scheduledTime.month}/${followup.scheduledTime.year} at ${followup.scheduledTime.hour.toString().padLeft(2, '0')}:${followup.scheduledTime.minute.toString().padLeft(2, '0')}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 8,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Urgency Banner
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
              decoration: BoxDecoration(
                color: isOverdue ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOverdue ? const Color(0xFFFCA5A5) : const Color(0xFFBFDBFE),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.phone_callback_rounded,
                    color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                    size: 26,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOverdue ? 'CALLBACK OVERDUE' : 'SCHEDULED CALLBACK DUE',
                          style: TextStyle(
                            color: isOverdue ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          followup.timeRemainingText,
                          style: TextStyle(
                            color: isOverdue ? const Color(0xFF991B1B) : const Color(0xFF1E40AF),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Customer Details Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          followup.customerName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (followup.company != null && followup.company!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            followup.company!,
                            style: const TextStyle(
                              color: Color(0xFF3730A3),
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 6),
                      Text(
                        followup.phoneNumber,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 6),
                      Text(
                        'Scheduled: $scheduledStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  if (followup.notes.isNotEmpty) ...[
                    const Divider(height: 16, color: Color(0xFFE2E8F0)),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            followup.notes,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Primary Call Now Button
            ElevatedButton.icon(
              onPressed: () => _makeCall(context),
              icon: const Icon(Icons.phone, color: Colors.white, size: 20),
              label: const Text(
                'CALL CUSTOMER NOW',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
            const SizedBox(height: 10),

            // Secondary WhatsApp & Snooze Row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF25D366)),
                    label: const Text('WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _snooze(context),
                    icon: const Icon(Icons.snooze, size: 18, color: Color(0xFFF59E0B)),
                    label: const Text('+15m Snooze'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Bottom Actions (Reschedule, Mark Done, Dismiss)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _reschedule(context),
                  icon: const Icon(Icons.edit_calendar, size: 16),
                  label: const Text('Reschedule', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
                ),
                TextButton.icon(
                  onPressed: () => _markCompleted(context),
                  icon: const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF16A34A)),
                  label: const Text('Mark Done', style: TextStyle(fontSize: 12, color: Color(0xFF16A34A))),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Dismiss', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
