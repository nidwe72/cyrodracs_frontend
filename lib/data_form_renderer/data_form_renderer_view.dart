import 'package:flutter/material.dart';
import '../app_config_editor/app_config_service.dart';
import '../basic/form_renderer_view.dart';
import '../models/app_config_node.dart';
import '../models/data_form.dart';
import '../models/data_form_element.dart';

/// Converts a SCREAMING_SNAKE_CASE backend type value to the camelCase name
/// expected by [DataFormElementType.byName].
String _toCamelCase(String screaming) {
  final parts = screaming.toLowerCase().split('_');
  return parts.first +
      parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

DataForm _buildDataForm(AppConfigNode formNode) {
  final elements = <DataFormElement>[];
  for (final child in formNode.children) {
    if (child.isCollection && child.label == 'elements') {
      for (final elem in child.children) {
        final raw = elem.typeValue;
        DataFormElementType type = DataFormElementType.inputString;
        if (raw != null) {
          try {
            type = DataFormElementType.values.byName(_toCamelCase(raw));
          } catch (_) {}
        }
        elements.add(DataFormElement(
          key: elem.label,
          label: elem.label,
          type: type,
        ));
      }
    }
  }
  return DataForm(
    code: formNode.label,
    entityValue: formNode.entityValue,
    elements: elements,
  );
}

class DataFormRendererView extends StatefulWidget {
  const DataFormRendererView({super.key});

  @override
  State<DataFormRendererView> createState() => _DataFormRendererViewState();
}

class _DataFormRendererViewState extends State<DataFormRendererView> {
  final _service = AppConfigService();

  List<AppConfigNode> _forms = [];
  bool _loading = true;
  String? _error;
  AppConfigNode? _selectedForm;

  @override
  void initState() {
    super.initState();
    _fetchForms();
  }

  Future<void> _fetchForms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await _service.fetchTree();
      final forms = <AppConfigNode>[];
      if (root != null) {
        for (final child in root.children) {
          if (child.isCollection && child.label == 'dataForms') {
            forms.addAll(child.children.where((n) => n.isInstance));
          }
        }
      }
      setState(() {
        _forms = forms;
        _selectedForm = forms.isNotEmpty ? forms.first : null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchForms, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_forms.isEmpty) {
      return const Center(
        child: Text('No DataForms found. Add one in the Config editor.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    final form = _selectedForm != null ? _buildDataForm(_selectedForm!) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Form:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 12),
              DropdownButton<AppConfigNode>(
                value: _selectedForm,
                items: _forms
                    .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedForm = v),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                tooltip: 'Reload',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _fetchForms,
              ),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 1),
        if (form != null)
          Expanded(child: FormRendererView(form: form))
        else
          const Expanded(child: SizedBox.shrink()),
      ],
    );
  }
}
