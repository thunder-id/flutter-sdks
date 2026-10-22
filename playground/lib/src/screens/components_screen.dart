// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

import '../config.dart';
import '../event_log.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Component explorer: story chips, live preview of the real thunderid_flutter widget,
/// and a controls/code sheet with a Flutter snippet generated from the current props.
class ComponentsScreen extends StatefulWidget {
  final PlaygroundConfig config;

  const ComponentsScreen({super.key, required this.config});

  @override
  State<ComponentsScreen> createState() => _ComponentsScreenState();
}

enum _SheetTab { controls, code, actions }

class _ComponentsScreenState extends State<ComponentsScreen> {
  ComponentDef _component = componentDefs.first;
  late String _story = _component.stories.first.id;
  final Map<String, Map<String, Object>> _values = {};
  bool _dark = true;
  _SheetTab _tab = _SheetTab.controls;
  final List<String> _actions = [];

  @override
  void initState() {
    super.initState();
    for (final def in componentDefs) {
      _values[def.id] = {
        ...def.defaults,
        if (def.controls.any((c) => c.name == 'applicationId')) 'applicationId': widget.config.applicationId ?? '',
        if (def.stories.any((st) => (st.controls ?? def.controls).any((c) => c.name == 'ouId')))
          'ouId': widget.config.ouId ?? '',
        ...def.stories.first.preset,
      };
    }
  }

  Map<String, Object> get _current => _values[_component.id]!;

  void _pickComponent(ComponentDef def) => setState(() {
        _component = def;
        _story = def.stories.first.id;
        _values[def.id] = {..._values[def.id]!, ...def.stories.first.preset};
        _actions.clear();
      });

  void _pickStory(StoryDef story) => setState(() {
        _story = story.id;
        _values[_component.id] = {..._current, ...story.preset};
        _actions.clear();
      });

  void _set(String name, Object value) => setState(() => _values[_component.id] = {..._current, name: value});

  void _emit(String action) {
    EventLog.instance.add('component:${_component.name}', action, kind: LogKind.info);
    if (mounted) setState(() => _actions.insert(0, action));
  }

  StoryContext get _storyContext => StoryContext(
        story: _story,
        values: _current,
        emit: _emit,
        dark: _dark,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        _buildStoryChips(),
        _buildPreview(context),
        Expanded(child: _buildSheet(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: PopupMenuButton<ComponentDef>(
              tooltip: 'Choose component',
              color: PlaygroundColors.surface,
              onSelected: _pickComponent,
              itemBuilder: (context) => [
                for (final def in componentDefs)
                  PopupMenuItem(
                    value: def,
                    child: Row(
                      children: [
                        Expanded(child: Text(def.name)),
                        Text(def.category, style: TextStyle(fontSize: 11, color: PlaygroundColors.white(0.45))),
                      ],
                    ),
                  ),
              ],
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_component.category, style: TextStyle(fontSize: 11.5, color: PlaygroundColors.white(0.5))),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _component.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more_rounded, size: 18, color: PlaygroundColors.white(0.6)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Toggle preview theme',
            onPressed: () => setState(() => _dark = !_dark),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: PlaygroundColors.white(0.06),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: Icon(_dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryChips() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final story in _component.stories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Semantics(
                selected: story.id == _story,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _pickStory(story),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: story.id == _story ? PlaygroundColors.primary.withValues(alpha: 0.2) : PlaygroundColors.white(0.04),
                      border: Border.all(
                        color: story.id == _story ? PlaygroundColors.primary.withValues(alpha: 0.5) : PlaygroundColors.white(0.1),
                      ),
                    ),
                    child: Text(
                      story.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: story.id == _story ? PlaygroundColors.primarySoft : PlaygroundColors.white(0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final previewTheme = PlaygroundTheme.preview(dark: _dark);
    final bg = _dark ? const Color(0xFF071022) : const Color(0xFFEEF1F6);
    final dots = _dark ? PlaygroundColors.white(0.08) : const Color(0x1F0F172A);
    return Container(
      height: 260,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PlaygroundColors.white(0.08)),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: DotGridPainter(dots))),
          Positioned.fill(
            child: Theme(
              data: previewTheme,
              child: Material(
                type: MaterialType.transparency,
                child: DefaultTextStyle(
                  style: previewTheme.textTheme.bodyMedium!,
                  child: IconTheme(
                    data: previewTheme.iconTheme,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                        child: KeyedSubtree(
                          key: ValueKey('${_component.id}/$_story'),
                          child: Builder(builder: (context) => _component.build(context, _storyContext)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_actions.isNotEmpty)
            Positioned(
              left: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: PlaygroundColors.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_actions.first.split('(').first} × ${_actions.where((a) => a.split('(').first == _actions.first.split('(').first).length}',
                  style: PlaygroundTheme.monoStyle(size: 11, color: PlaygroundColors.primarySoft, weight: FontWeight.w500),
                ),
              ),
            ),
          Positioned(
            right: 12,
            bottom: 10,
            child: Text(
              _dark ? 'dark' : 'light',
              style: PlaygroundTheme.monoStyle(size: 11, color: _dark ? PlaygroundColors.white(0.45) : const Color(0x8C0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSheet(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: PlaygroundColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: PlaygroundColors.white(0.1))),
        boxShadow: const [BoxShadow(color: Color(0x59000000), blurRadius: 32, offset: Offset(0, -16))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: PlaygroundColors.white(0.2), borderRadius: BorderRadius.circular(999)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Segmented<_SheetTab>(
              options: [
                (_SheetTab.controls, 'Controls'),
                (_SheetTab.code, 'Code'),
                (_SheetTab.actions, _actions.isEmpty ? 'Actions' : 'Actions (${_actions.length})'),
              ],
              value: _tab,
              onChanged: (t) => setState(() => _tab = t),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: switch (_tab) {
                _SheetTab.controls => _buildControls(),
                _SheetTab.code => [
                    const SizedBox(height: 6),
                    CodeBlock(code: _component.code(_storyContext), language: 'Flutter'),
                  ],
                _SheetTab.actions => _buildActions(),
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildControls() {
    final controls = _component.controlsFor(_story);
    if (controls.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'This story has no props to edit. It renders from the SDK session state.',
            style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55)),
          ),
        ),
      ];
    }
    return [
      for (final control in controls)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: PlaygroundColors.white(0.06)))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      control.name,
                      style: PlaygroundTheme.monoStyle(size: 13, color: PlaygroundColors.accent, weight: FontWeight.w500),
                    ),
                  ),
                  if (control.kind == ControlKind.toggle)
                    Switch(
                      value: _current[control.name] == true,
                      onChanged: (v) => _set(control.name, v),
                    ),
                ],
              ),
              if (control.kind == ControlKind.text) ...[
                const SizedBox(height: 8),
                _TextControl(
                  key: ValueKey('${_component.id}/$_story/${control.name}'),
                  label: control.name,
                  initial: _current[control.name]?.toString() ?? '',
                  onChanged: (v) => _set(control.name, v),
                ),
              ],
              if (control.kind == ControlKind.choice) ...[
                const SizedBox(height: 8),
                Segmented<String>(
                  options: [for (final o in control.options) (o, o)],
                  value: _current[control.name]?.toString() ?? control.options.first,
                  onChanged: (v) => _set(control.name, v),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  List<Widget> _buildActions() {
    if (_actions.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'Callbacks fired by the component show up here.',
            style: TextStyle(fontSize: 13, color: PlaygroundColors.white(0.55)),
          ),
        ),
      ];
    }
    return [
      for (final action in _actions)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(action, style: PlaygroundTheme.monoStyle(size: 12.5, color: PlaygroundColors.primarySoft)),
        ),
    ];
  }
}

class _TextControl extends StatefulWidget {
  final String label;
  final String initial;
  final ValueChanged<String> onChanged;

  const _TextControl({super.key, required this.label, required this.initial, required this.onChanged});

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        style: const TextStyle(fontSize: 15),
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.label,
          filled: true,
          fillColor: PlaygroundColors.white(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: PlaygroundColors.white(0.12)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: PlaygroundColors.white(0.12)),
          ),
        ),
      );
}
