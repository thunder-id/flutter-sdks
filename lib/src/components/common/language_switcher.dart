// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import '../../i18n/built_in_strings.dart';
import '../../models/preferences.dart';
import '../thunderid_provider.dart';

/// Locale picker that updates the active language for component labels (spec §8.4 Presentation).
class LanguageSwitcher extends StatelessWidget {
  /// Available locales to display. If empty, lists the locales the SDK ships strings for
  /// followed by any other [I18nPreferences.bundles] locale.
  final List<String> locales;

  const LanguageSwitcher({super.key, this.locales = const []});

  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    final available = locales.isNotEmpty
        ? locales
        : {...thunderSupportedLocales, ...?state.preferences?.i18n?.bundles.keys}.toList();
    return BaseLanguageSwitcher(
      locales: available,
      builder: (ctx, active, select) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final locale in available)
            GestureDetector(
              onTap: () => select(locale),
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                child: Semantics(
                  label: locale,
                  selected: locale == active,
                  button: true,
                  child: Text(
                    locale,
                    style: TextStyle(
                      fontWeight:
                          locale == active ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Unstyled base variant (spec §8.3).
class BaseLanguageSwitcher extends StatefulWidget {
  final List<String> locales;
  final Widget Function(
    BuildContext context,
    String activeLocale,
    void Function(String locale) selectLocale,
  ) builder;

  const BaseLanguageSwitcher({
    super.key,
    required this.locales,
    required this.builder,
  });

  @override
  State<BaseLanguageSwitcher> createState() =>
      _BaseLanguageSwitcherState();
}

class _BaseLanguageSwitcherState
    extends State<BaseLanguageSwitcher> {
  @override
  Widget build(BuildContext context) {
    final state = ThunderIDProvider.of(context);
    return widget.builder(
      context,
      state.i18n.activeLocale,
      (locale) => state.setLocale(locale),
    );
  }
}
