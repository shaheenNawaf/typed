import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ImagePickerSheet extends StatelessWidget {
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  const ImagePickerSheet({
    super.key,
    required this.onGallery,
    required this.onCamera,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onGallery,
    required VoidCallback onCamera,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ImagePickerSheet(
        onGallery: onGallery,
        onCamera: onCamera,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _Option(
              icon: Icons.photo_library_outlined,
              label: 'Choose from gallery',
              onTap: () {
                Navigator.pop(context);
                onGallery();
              },
            ),
            _Option(
              icon: Icons.camera_alt_outlined,
              label: 'Take a photo',
              onTap: () {
                Navigator.pop(context);
                onCamera();
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text('Cancel',
                    style: TextStyle(fontSize: 14, color: context.colors.muted)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: context.colors.listBg,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: context.colors.fg),
            ),
            const SizedBox(width: 14),
            Text(label, style:  TextStyle(
              fontSize: 15, color: context.colors.fg,
            )),
          ],
        ),
      ),
    );
  }
}
