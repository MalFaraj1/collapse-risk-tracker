import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme/app_colors.dart';
import 'app_button.dart';

/// Displays a single-marker Google Map for a building's location, with an
/// "Open in Google Maps" fallback link. Requires the Google Maps JavaScript
/// API to be loaded on the web page — see the setup note in
/// docs/ARCHITECTURE.md before using this on Flutter Web, or the map area
/// will render as a blank grey box with no error shown.
class GoogleMapCard extends StatelessWidget {
  const GoogleMapCard({
    super.key,
    required this.latitude,
    required this.longitude,
    this.height = 220,
    this.markerLabel,
  });

  final double latitude;
  final double longitude;
  final double height;
  final String? markerLabel;

  @override
  Widget build(BuildContext context) {
    final position = LatLng(latitude, longitude);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: height,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: position, zoom: 16),
              markers: {
                Marker(
                  markerId: const MarkerId('building-location'),
                  position: position,
                  infoWindow: InfoWindow(title: markerLabel ?? 'موقع المبنى'),
                ),
              },
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
              myLocationButtonEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontFamily: 'monospace'),
            ),
            const Spacer(),
            AppButton(
              label: 'فتح في خرائط Google',
              icon: Icons.open_in_new,
              variant: AppButtonVariant.ghost,
              dense: true,
              onPressed: () => _openInGoogleMaps(latitude, longitude),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Shown instead of [GoogleMapCard] when a parcel has no coordinates yet.
class NoLocationPlaceholder extends StatelessWidget {
  const NoLocationPlaceholder({super.key, required this.canSetLocation, required this.onSetLocation});

  final bool canSetLocation;
  final VoidCallback onSetLocation;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_off_outlined, size: 28, color: AppColors.textFaint),
          const SizedBox(height: 8),
          const Text('لم يتم تحديد موقع هذا المبنى بعد', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          if (canSetLocation) ...[
            const SizedBox(height: 10),
            AppButton(label: 'تحديد الموقع', icon: Icons.add_location_alt_outlined, dense: true, onPressed: onSetLocation),
          ],
        ],
      ),
    );
  }
}
