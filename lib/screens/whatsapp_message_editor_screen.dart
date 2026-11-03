import 'package:flutter/material.dart';
import 'package:callnow_new/services/whatsapp_message_service.dart';

class WhatsAppMessageEditorScreen extends StatefulWidget {
  const WhatsAppMessageEditorScreen({super.key});

  @override
  State<WhatsAppMessageEditorScreen> createState() =>
      _WhatsAppMessageEditorScreenState();
}

class _WhatsAppMessageEditorScreenState
    extends State<WhatsAppMessageEditorScreen> {
  final TextEditingController _messageController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    try {
      final template = await WhatsAppMessageService.loadTemplate();
      if (!mounted) return;
      _messageController.text = template;
      setState(() => _isLoading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load WhatsApp message: $error')),
      );
    }
  }

  Future<void> _saveTemplate() async {
    setState(() => _isSaving = true);
    try {
      await WhatsAppMessageService.saveTemplate(_messageController.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save WhatsApp message: $error')),
      );
    }
  }

  void _restoreDefault() {
    setState(() {
      _messageController.text = WhatsAppMessageService.defaultTemplate;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WhatsApp message',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading || _isSaving ? null : _restoreDefault,
            child: const Text('Restore default'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                    child: Text(
                      'This message opens in WhatsApp with customer details filled in. '
                      'Edit the remaining [placeholders] to match your offer.',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: TextField(
                        controller: _messageController,
                        minLines: 16,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: 'Write your WhatsApp message',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF16A34A),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveTemplate,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving…' : 'Save message'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
