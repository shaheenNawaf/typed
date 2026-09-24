import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

class WorkspaceHeader extends StatelessWidget {
  final String sectionLabel;
  final String? tagLabel;
  final String? noteTitle;
  final VoidCallback? onHome;
  final VoidCallback? onSection;
  final VoidCallback? onOpenCommandPalette;
  final VoidCallback? onMenu;
  final bool isMobile;
  final bool headerSearch;
  final VoidCallback? onSearchTap;

  const WorkspaceHeader({
    super.key,
    required this.sectionLabel,
    this.tagLabel,
    this.noteTitle,
    this.onHome,
    this.onSection,
    this.onOpenCommandPalette,
    this.onMenu,
    this.isMobile = false,
    this.headerSearch = false,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = noteTitle?.trim();
    final hasNote = title != null && title.isNotEmpty;

    if (isMobile && headerSearch && onSearchTap != null) {
      return Container(
        height: 50,
        padding: const EdgeInsets.only(left: 8, right: 10),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            if (onMenu != null)
              IconButton(
                onPressed: onMenu,
                tooltip: 'Open navigation',
                icon: Icon(Icons.menu, size: 20, color: c.muted),
                visualDensity: VisualDensity.compact,
              ),
            const Spacer(),
            InkWell(
              onTap: onSearchTap,
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.border),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 16, color: c.muted),
                    const SizedBox(width: 6),
                    Text('Search', style: TextStyle(fontSize: AppType.t12, color: c.muted)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: isMobile ? 50 : 54,
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 18),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (isMobile && onMenu != null)
            IconButton(
              onPressed: onMenu,
              tooltip: 'Open navigation',
              icon: Icon(Icons.menu, size: 20, color: c.muted),
              visualDensity: VisualDensity.compact,
            ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (isMobile && !hasNote)
                    Text(
                      sectionLabel,
                      style: TextStyle(
                        color: c.fg,
                        fontSize: AppType.t15,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else ...[
                    _Crumb(
                      label: isMobile ? sectionLabel : 'Workspace',
                      onTap: onHome,
                      muted: !isMobile,
                    ),
                    if (!isMobile || hasNote) ...[
                      _separator(c),
                      _Crumb(
                        label: tagLabel ?? sectionLabel,
                        onTap: onSection,
                        muted: hasNote,
                      ),
                    ],
                    if (hasNote) ...[
                      _separator(c),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.fg,
                          fontSize: isMobile ? AppType.t15 : AppType.t13_5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (onOpenCommandPalette != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _CommandButton(
                isMobile: isMobile,
                onPressed: onOpenCommandPalette!,
              ),
            ),
        ],
      ),
    );
  }

  Widget _separator(AppColors c) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Icon(Icons.chevron_right, size: 14, color: c.muted),
  );
}

class _Crumb extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool muted;

  const _Crumb({required this.label, this.onTap, this.muted = false});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Text(
      label,
      style: TextStyle(
        color: muted ? c.muted : c.fg,
        fontSize: AppType.t13_5,
        fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
      ),
    );
    if (onTap == null) return text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: text,
      ),
    );
  }
}

class _CommandButton extends StatelessWidget {
  final bool isMobile;
  final VoidCallback onPressed;

  const _CommandButton({required this.isMobile, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 8 : 10,
          vertical: 7,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 16, color: c.muted),
            if (!isMobile) ...[
              const SizedBox(width: 6),
              Text(
                'Search or jump',
                style: TextStyle(fontSize: AppType.t12, color: c.muted),
              ),
              const SizedBox(width: 8),
              Text(
                'Ctrl K',
                style: TextStyle(
                  fontSize: AppType.t10,
                  color: c.muted,
                  fontFamily: c.monoFontFamily,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
