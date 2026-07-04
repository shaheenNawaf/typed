import 'package:flutter/material.dart';

class FontOption {
  final String id;
  final String name;
  final IconData icon;
  final String uiFontFamily;
  final String? displayFontFamily;
  final String monoFontFamily;

  const FontOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.uiFontFamily,
    this.displayFontFamily,
    required this.monoFontFamily,
  });

  bool get usesGoogleFonts => uiFontFamily != 'System';
}

const List<FontOption> kFontOptions = [
  FontOption(
    id: 'dm-sans',
    name: 'DM Sans',
    icon: Icons.text_fields,
    uiFontFamily: 'DM Sans',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'inter',
    name: 'Inter',
    icon: Icons.text_fields,
    uiFontFamily: 'Inter',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'lora',
    name: 'Lora',
    icon: Icons.text_fields,
    uiFontFamily: 'DM Sans',
    displayFontFamily: 'Lora',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'outfit',
    name: 'Outfit',
    icon: Icons.text_fields,
    uiFontFamily: 'Outfit',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'system',
    name: 'System',
    icon: Icons.text_fields,
    uiFontFamily: 'System',
    monoFontFamily: 'JetBrains Mono',
  ),
];

FontOption fontOptionById(String id) {
  return kFontOptions.firstWhere(
    (f) => f.id == id,
    orElse: () => kFontOptions.first,
  );
}
