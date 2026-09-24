class FontOption {
  final String id;
  final String name;
  final String uiFontFamily;
  final String? displayFontFamily;
  final String monoFontFamily;

  const FontOption({
    required this.id,
    required this.name,
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
    uiFontFamily: 'DM Sans',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'inter',
    name: 'Inter',
    uiFontFamily: 'Inter',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'lora',
    name: 'Lora',
    uiFontFamily: 'DM Sans',
    displayFontFamily: 'Lora',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'outfit',
    name: 'Outfit',
    uiFontFamily: 'Outfit',
    monoFontFamily: 'JetBrains Mono',
  ),
  FontOption(
    id: 'system',
    name: 'System',
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
