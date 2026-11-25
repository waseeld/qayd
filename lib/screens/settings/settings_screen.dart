// ==============================================================================
// Settings Screen (API Keys)
// File: lib/screens/settings/settings_screen.dart
//
// Lets anyone enter their Groq Whisper and Gemini API keys once. Keys are
// persisted locally on the device (Hive) so they never have to be re-entered.
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/qayd_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _groqController;
  late final TextEditingController _geminiController;
  bool _obscureGroq = true;
  bool _obscureGemini = true;
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _groqController = TextEditingController();
    _geminiController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    final provider = context.read<QaydProvider>();
    _groqController.text = provider.groqApiKey;
    _geminiController.text = provider.geminiApiKey;
    _loaded = true;
  }

  @override
  void dispose() {
    _groqController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<QaydProvider>();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    setState(() => _saving = true);
    try {
      await provider.saveApiKeys(
        groqApiKey: _groqController.text,
        geminiApiKey: _geminiController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic ? 'تم حفظ مفاتيح API بنجاح' : 'API keys saved successfully',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    final provider = context.read<QaydProvider>();
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    _groqController.clear();
    _geminiController.clear();
    await provider.saveApiKeys(groqApiKey: '', geminiApiKey: '');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isArabic ? 'تم مسح مفاتيح API' : 'API keys cleared'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Text(isArabic ? 'الإعدادات' : 'Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Text(
            isArabic ? 'مفاتيح API' : 'API Keys',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'أدخل المفاتيح مرة واحدة فقط، وسيتم حفظها محلياً على هذا الجهاز.'
                : 'Enter your keys once. They are saved locally on this device.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // --- Groq Whisper key ---
          _buildSectionLabel(
            theme,
            isArabic ? 'مفتاح Groq (التفريغ الصوتي)' : 'Groq API Key (transcription)',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _groqController,
            obscureText: _obscureGroq,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'gsk_...',
              prefixIcon: const Icon(Icons.graphic_eq),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureGroq ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureGroq = !_obscureGroq),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'احصل عليه من console.groq.com → API Keys'
                : 'Get it from console.groq.com → API Keys',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // --- Gemini key ---
          _buildSectionLabel(
            theme,
            isArabic ? 'مفتاح Gemini (التلخيص)' : 'Gemini API Key (summarization)',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiController,
            obscureText: _obscureGemini,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'AIza...',
              prefixIcon: const Icon(Icons.auto_awesome),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureGemini ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscureGemini = !_obscureGemini),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isArabic
                ? 'احصل عليه من aistudio.google.com/apikey'
                : 'Get it from aistudio.google.com/apikey',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          // --- Actions ---
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(isArabic ? 'حفظ' : 'Save'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _clear,
            icon: const Icon(Icons.delete_outline),
            label: Text(isArabic ? 'مسح المفاتيح' : 'Clear keys'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
