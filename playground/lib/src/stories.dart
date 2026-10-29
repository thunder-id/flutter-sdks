// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

import 'admin_stories.dart';
import 'custom_render_stories.dart';
import 'theme.dart';

enum ControlKind { text, toggle, choice }

class ControlDef {
  final String name;
  final ControlKind kind;
  final List<String> options;

  const ControlDef.text(this.name)
      : kind = ControlKind.text,
        options = const [];
  const ControlDef.toggle(this.name)
      : kind = ControlKind.toggle,
        options = const [];
  const ControlDef.choice(this.name, this.options) : kind = ControlKind.choice;
}

class StoryDef {
  final String id;
  final String name;
  final Map<String, Object> preset;

  /// Controls shown for this story; defaults to the component's controls.
  final List<ControlDef>? controls;

  const StoryDef(this.id, this.name, {this.preset = const {}, this.controls});
}

/// Inputs a story needs to render: current prop values and an action sink.
class StoryContext {
  final String story;
  final Map<String, Object> values;
  final void Function(String action) emit;

  /// Whether the preview is dark, for components themed through preferences (the Admin ones).
  final bool dark;

  const StoryContext({required this.story, required this.values, required this.emit, this.dark = true});

  String text(String key) => values[key]?.toString() ?? '';
  bool flag(String key) => values[key] == true;
  double number(String key, double fallback) => double.tryParse(text(key)) ?? fallback;
}

class ComponentDef {
  final String id;
  final String name;
  final String category;
  final List<StoryDef> stories;
  final List<ControlDef> controls;
  final Map<String, Object> defaults;
  final Widget Function(BuildContext context, StoryContext story) build;
  final String Function(StoryContext story) code;

  const ComponentDef({
    required this.id,
    required this.name,
    required this.category,
    required this.stories,
    required this.build,
    required this.code,
    this.controls = const [],
    this.defaults = const {},
  });

  List<ControlDef> controlsFor(String storyId) =>
      stories.firstWhere((s) => s.id == storyId, orElse: () => stories.first).controls ?? controls;
}

/// Dart string literal for generated snippets.
String lit(String value) => "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

const _variants = ['solid', 'outline', 'text'];

/// The custom look used by Base* button stories, driven by the variant/fullWidth controls.
Widget _customButton(BuildContext context, StoryContext s, {bool danger = false}) {
  final color = danger ? PlaygroundColors.fail : PlaygroundColors.primary;
  final variant = s.text('variant');
  final child = Container(
    constraints: const BoxConstraints(minHeight: 48, minWidth: 44),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      gradient: variant == 'solid' && !danger ? PlaygroundColors.primaryGradient : null,
      color: variant == 'solid' && danger ? color : null,
      border: variant == 'outline' ? Border.all(color: color) : null,
    ),
    child: Text(
      s.text('label'),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: variant == 'solid' ? Colors.white : color,
      ),
    ),
  );
  return s.flag('fullWidth') ? SizedBox(width: double.infinity, child: child) : child;
}

String _customButtonCode(String widget, StoryContext s, List<String> callbacks) {
  final variant = s.text('variant');
  final decoration = switch (variant) {
    'solid' => '    decoration: BoxDecoration(\n      color: Theme.of(context).colorScheme.primary,\n      borderRadius: BorderRadius.circular(12),\n    ),\n',
    'outline' => '    decoration: BoxDecoration(\n      border: Border.all(color: Theme.of(context).colorScheme.primary),\n      borderRadius: BorderRadius.circular(12),\n    ),\n',
    _ => '',
  };
  return '$widget(\n'
      '${callbacks.map((c) => '  $c: () {},\n').join()}'
      '  builder: (context${widget == 'BaseSignInButton' ? '' : ', isLoading'}) => Container(\n'
      '${s.flag('fullWidth') ? '    width: double.infinity,\n' : ''}'
      '    constraints: const BoxConstraints(minHeight: 48),\n'
      '    alignment: Alignment.center,\n'
      '$decoration'
      '    child: Text(${lit(s.text('label'))}),\n'
      '  ),\n'
      ')';
}

const _buttonControls = [
  ControlDef.text('label'),
  ControlDef.choice('variant', _variants),
  ControlDef.toggle('fullWidth'),
];

final List<ComponentDef> componentDefs = [
  ComponentDef(
    id: 'signInButton',
    name: 'SignInButton',
    category: 'Actions',
    defaults: const {'label': 'Sign In', 'variant': 'solid', 'fullWidth': true},
    controls: const [ControlDef.text('label')],
    stories: const [
      StoryDef('styled', 'Styled', preset: {'label': 'Sign In'}),
      StoryDef('base', 'Base (custom)', preset: {'label': 'Continue with ThunderID'}, controls: _buttonControls),
    ],
    build: (context, s) => s.story == 'base'
        ? BaseSignInButton(
            onSignInComplete: () => s.emit('onSignInComplete'),
            onError: () => s.emit('onError'),
            builder: (ctx) => _customButton(ctx, s),
          )
        : SignInButton(
            label: s.text('label'),
            onSignInComplete: () => s.emit('onSignInComplete'),
            onError: () => s.emit('onError'),
          ),
    code: (s) => s.story == 'base'
        ? _customButtonCode('BaseSignInButton', s, ['onSignInComplete'])
        : 'SignInButton(\n  label: ${lit(s.text('label'))},\n  onSignInComplete: () {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'signOutButton',
    name: 'SignOutButton',
    category: 'Actions',
    defaults: const {'label': 'Sign out', 'variant': 'outline', 'fullWidth': true},
    stories: const [
      StoryDef('styled', 'Styled'),
      StoryDef('base', 'Base (custom)', controls: _buttonControls),
    ],
    build: (context, s) => s.story == 'base'
        ? BaseSignOutButton(
            onSuccess: () => s.emit('onSuccess'),
            onError: () => s.emit('onError'),
            builder: (ctx, isLoading) =>
                Opacity(opacity: isLoading ? 0.5 : 1, child: _customButton(ctx, s, danger: true)),
          )
        : SignOutButton(onSuccess: () => s.emit('onSuccess'), onError: () => s.emit('onError')),
    code: (s) => s.story == 'base'
        ? _customButtonCode('BaseSignOutButton', s, ['onSuccess'])
        : 'SignOutButton(\n  onSuccess: () {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'signUpButton',
    name: 'SignUpButton',
    category: 'Actions',
    defaults: const {'label': 'Create account', 'variant': 'solid', 'fullWidth': false},
    stories: const [
      StoryDef('styled', 'Styled'),
      StoryDef('base', 'Base (custom)', controls: _buttonControls),
    ],
    build: (context, s) => s.story == 'base'
        ? BaseSignUpButton(
            onFlowStarted: (r) => s.emit('onFlowStarted(${r.flowStatus.name})'),
            onError: () => s.emit('onError'),
            builder: (ctx, isLoading) => Opacity(opacity: isLoading ? 0.5 : 1, child: _customButton(ctx, s)),
          )
        : SignUpButton(
            onFlowStarted: (r) => s.emit('onFlowStarted(${r.flowStatus.name})'),
            onError: () => s.emit('onError'),
          ),
    code: (s) => s.story == 'base'
        ? _customButtonCode('BaseSignUpButton', s, ['onFlowStarted'])
            .replaceFirst('onFlowStarted: () {}', 'onFlowStarted: (response) {}')
        : 'SignUpButton(\n  onFlowStarted: (response) {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'signIn',
    name: 'SignIn',
    category: 'Flows',
    controls: const [ControlDef.text('applicationId')],
    stories: const [StoryDef('embedded', 'App-native flow')],
    build: (context, s) => SignIn(
      key: ValueKey('signIn-${s.text('applicationId')}'),
      applicationId: s.text('applicationId'),
      onSuccess: (user) => s.emit('onSuccess(${user.sub ?? 'user'})'),
      onError: () => s.emit('onError'),
    ),
    code: (s) => 'SignIn(\n  applicationId: ${lit(s.text('applicationId'))},\n  onSuccess: (user) {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'signUp',
    name: 'SignUp',
    category: 'Flows',
    controls: const [ControlDef.text('applicationId')],
    stories: const [StoryDef('embedded', 'App-native flow')],
    build: (context, s) => SignUp(
      key: ValueKey('signUp-${s.text('applicationId')}'),
      applicationId: s.text('applicationId'),
      onSuccess: () => s.emit('onSuccess'),
      onError: () => s.emit('onError'),
    ),
    code: (s) => 'SignUp(\n  applicationId: ${lit(s.text('applicationId'))},\n  onSuccess: () {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'userAvatar',
    name: 'UserAvatar',
    category: 'Presentation',
    defaults: const {'size': '48', 'anonymousSeed': 'otter'},
    controls: const [ControlDef.choice('size', ['32', '48', '72'])],
    stories: const [
      StoryDef('current', 'Current user'),
      StoryDef(
        'anonymous',
        'Anonymous',
        controls: [ControlDef.choice('size', ['32', '48', '72']), ControlDef.text('anonymousSeed')],
      ),
    ],
    build: (context, s) => s.story == 'anonymous'
        ? BaseUserAvatar(user: null, size: s.number('size', 48), anonymousSeed: s.text('anonymousSeed'))
        : UserAvatar(size: s.number('size', 48)),
    code: (s) => s.story == 'anonymous'
        ? 'BaseUserAvatar(\n  user: null,\n  size: ${s.text('size')},\n  anonymousSeed: ${lit(s.text('anonymousSeed'))},\n)'
        : 'UserAvatar(size: ${s.text('size')})',
  ),
  ComponentDef(
    id: 'userObject',
    name: 'UserObject',
    category: 'Presentation',
    stories: const [StoryDef('default', 'Default'), StoryDef('base', 'Base (custom)')],
    build: (context, s) => s.story == 'base'
        ? BaseUserObject(
            builder: (ctx, user) => Text(
              user == null ? 'Signed out' : '${user.email ?? user.username ?? user.sub} · ${user.claims.length} claims',
            ),
          )
        : const UserObject(),
    code: (s) => s.story == 'base'
        ? "BaseUserObject(\n  builder: (context, user) => Text(\n    user == null ? 'Signed out' : user.email ?? '',\n  ),\n)"
        : 'const UserObject()',
  ),
  ComponentDef(
    id: 'userDropdown',
    name: 'UserDropdown',
    category: 'Presentation',
    stories: const [StoryDef('default', 'Default')],
    build: (context, s) => UserDropdown(
      onProfileTap: () => s.emit('onProfileTap'),
      onSignOutComplete: () => s.emit('onSignOutComplete'),
    ),
    code: (s) => 'UserDropdown(\n  onProfileTap: () {},\n  onSignOutComplete: () {},\n)',
  ),
  ComponentDef(
    id: 'userProfile',
    name: 'UserProfile',
    category: 'Presentation',
    stories: const [StoryDef('default', 'Default')],
    build: (context, s) => UserProfile(onSaved: () => s.emit('onSaved'), onError: () => s.emit('onError')),
    code: (s) => 'UserProfile(\n  onSaved: () {},\n  onError: () {},\n)',
  ),
  ComponentDef(
    id: 'verifyAttribute',
    name: 'VerifyAttribute',
    category: 'Presentation',
    defaults: const {
      'attribute': 'email',
      'flowHandle': AttributeVerification.defaultFlowHandle,
    },
    controls: const [
      ControlDef.text('attribute'),
      ControlDef.text('flowHandle'),
    ],
    stories: const [
      StoryDef('email', 'Email', preset: {'attribute': 'email'}),
      StoryDef(
        'mobile',
        'Mobile number',
        preset: {'attribute': 'mobile_number'},
      ),
    ],
    build: (context, s) => _VerifyAttributeStory(
      key: ValueKey('verify-${s.text('attribute')}|${s.text('flowHandle')}'),
      story: s,
    ),
    code: (s) =>
        'VerifyAttribute(\n  key: ValueKey(${lit(s.text('attribute'))}),\n'
        '  attribute: ${lit(s.text('attribute'))},\n'
        '${s.text('flowHandle') == AttributeVerification.defaultFlowHandle ? '' : '  flowHandle: ${lit(s.text('flowHandle'))},\n'}'
        '  onComplete: () {},\n  onDone: () {},\n  onCancel: () {},\n)',
  ),
  ComponentDef(
    id: 'changeCredential',
    name: 'ChangeCredential',
    category: 'Presentation',
    defaults: const {'attribute': 'password', 'showDivider': true},
    controls: const [ControlDef.text('attribute'), ControlDef.toggle('showDivider')],
    stories: const [StoryDef('password', 'Password')],
    build: (context, s) => ChangeCredential(
      attribute: s.text('attribute'),
      showDivider: s.flag('showDivider'),
      onSuccess: () => s.emit('onSuccess'),
    ),
    code: (s) => 'ChangeCredential(\n  attribute: ${lit(s.text('attribute'))},\n'
        '${s.flag('showDivider') ? '' : '  showDivider: false,\n'}  onSuccess: () {},\n)',
  ),
  ComponentDef(
    id: 'languageSwitcher',
    name: 'LanguageSwitcher',
    category: 'Presentation',
    defaults: const {'locales': 'en-US, fr-FR, es-ES'},
    controls: const [ControlDef.text('locales')],
    stories: const [StoryDef('bundles', 'Bundled locales')],
    build: (context, s) => LanguageSwitcher(locales: _locales(s)),
    code: (s) => 'LanguageSwitcher(\n  locales: [${_locales(s).map(lit).join(', ')}],\n)',
  ),
  ComponentDef(
    id: 'logo',
    name: 'ThunderIDLogo',
    category: 'Presentation',
    defaults: const {'size': '72', 'fallbackSeedText': 'Playground'},
    controls: const [
      ControlDef.text('spec'),
      ControlDef.choice('size', ['40', '72', '96']),
      ControlDef.text('fallbackSeedText'),
    ],
    stories: const [
      StoryDef('emoji', 'Emoji', preset: {'spec': 'emoji:⚡'}),
      StoryDef('avatar', 'Avatar', preset: {'spec': 'avatar:shape=rounded,variant=two_letter'}),
      StoryDef('animal', 'Anonymous', preset: {'spec': 'avatar:shape=circle,variant=anonymous_animal,content=otter'}),
    ],
    build: (context, s) => ThunderIDLogo(
      spec: s.text('spec'),
      size: s.number('size', 72),
      fallbackSeedText: s.text('fallbackSeedText'),
    ),
    code: (s) => 'ThunderIDLogo(\n  spec: ${lit(s.text('spec'))},\n  size: ${s.text('size')},\n'
        '  fallbackSeedText: ${lit(s.text('fallbackSeedText'))},\n)',
  ),
  ComponentDef(
    id: 'guards',
    name: 'SignedIn / SignedOut / Loading',
    category: 'Control',
    defaults: const {'child': 'Welcome back', 'fallback': 'Please sign in'},
    controls: const [ControlDef.text('child'), ControlDef.text('fallback')],
    stories: const [
      StoryDef('signedIn', 'SignedIn', preset: {'child': 'Welcome back', 'fallback': 'Please sign in'}),
      StoryDef('signedOut', 'SignedOut', preset: {'child': 'Please sign in', 'fallback': 'You are signed in'}),
      StoryDef('loading', 'Loading', preset: {'child': 'Ready'}, controls: [ControlDef.text('child')]),
    ],
    build: (context, s) => switch (s.story) {
      'signedOut' => SignedOut(fallback: Text(s.text('fallback')), child: Text(s.text('child'))),
      'loading' => Loading(indicator: const CircularProgressIndicator(), child: Text(s.text('child'))),
      _ => SignedIn(fallback: Text(s.text('fallback')), child: Text(s.text('child'))),
    },
    code: (s) => switch (s.story) {
      'loading' => 'Loading(\n  indicator: const CircularProgressIndicator(),\n  child: Text(${lit(s.text('child'))}),\n)',
      final story => '${story == 'signedOut' ? 'SignedOut' : 'SignedIn'}(\n'
          '  fallback: Text(${lit(s.text('fallback'))}),\n  child: Text(${lit(s.text('child'))}),\n)',
    },
  ),
  ...adminComponentDefs,
  ...customRenderComponentDefs,
];

/// Starting a verification sends a message, so the story waits for a tap.
class _VerifyAttributeStory extends StatefulWidget {
  final StoryContext story;

  const _VerifyAttributeStory({super.key, required this.story});

  @override
  State<_VerifyAttributeStory> createState() => _VerifyAttributeStoryState();
}

class _VerifyAttributeStoryState extends State<_VerifyAttributeStory> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.story;
    if (!_started) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          onPressed: () => setState(() => _started = true),
          child: Text('Send a code to ${s.text('attribute')}'),
        ),
      );
    }
    return VerifyAttribute(
      attribute: s.text('attribute'),
      flowHandle: s.text('flowHandle'),
      onComplete: () => s.emit('onComplete'),
      onDone: () => s.emit('onDone'),
      onError: (error) => s.emit('onError(${error.code.value})'),
      onCancel: () => setState(() => _started = false),
    );
  }
}

List<String> _locales(StoryContext s) => s
    .text('locales')
    .split(',')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();
