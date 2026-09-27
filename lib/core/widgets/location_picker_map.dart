import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../app/theme/app_colors.dart';

/// An interactive Google Map for capturing a single point location by
/// tapping to drop a pin — or, in [readOnly] mode, just displaying an
/// already-saved one. Generic — not tied to Intake specifically, reuse
/// this anywhere else a lat/lng needs to be captured or shown this way.
///
/// Pass [readOnly] = true to show a fixed marker without allowing the
/// user to move it. Intake uses this for an EXISTING parcel's saved
/// location, which it doesn't own the right to edit — the same reasoning
/// already applied to that parcel's address field.
class LocationPickerMap extends StatefulWidget {
  const LocationPickerMap({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.onLocationSelected,
    this.readOnly = false,
    this.height = 220,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  /// Called with the tapped point every time the user drops/moves the pin.
  /// Ignored when [readOnly] is true.
  final ValueChanged<LatLng>? onLocationSelected;
  final bool readOnly;
  final double height;

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  // Default center when no location is set yet: Tripoli, Lebanon — this is
  // a Tripoli municipality system, so an empty map should already be
  // looking at the right city rather than at Null Island (0, 0).
  static const _defaultCenter = LatLng(34.4346, 35.8362);

  LatLng? _marker;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _marker = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  void _handleTap(LatLng point) {
    if (widget.readOnly) return;
    setState(() => _marker = point);
    widget.onLocationSelected?.call(point);
  }

  @override
  Widget build(BuildContext context) {
    final center = _marker ?? _defaultCenter;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: center, zoom: _marker != null ? 16 : 12),
              markers: _marker == null
                  ? const {}
                  : {Marker(markerId: const MarkerId('selected'), position: _marker!)},
              onTap: _handleTap,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: true,
            ),
            if (!widget.readOnly)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.navy.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'اضغط على الخريطة لتحديد الموقع',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}