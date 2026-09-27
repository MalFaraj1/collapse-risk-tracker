import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../app/theme/app_colors.dart';
import 'app_button.dart';

enum MediaKind { image, video }

const _videoExtensions = ['.mp4', '.mov', '.webm', '.avi', '.mkv', '.m4v'];

/// Detects whether a saved media URL is a photo or a video, by file
/// extension. Storage download URLs carry query parameters after the
/// extension (a signing token etc.), so this checks the path portion
/// before `?`, not a strict string suffix on the whole URL.
MediaKind mediaKindForUrl(String url) {
  final path = url.toLowerCase().split('?').first;
  return _videoExtensions.any((ext) => path.endsWith(ext)) ? MediaKind.video : MediaKind.image;
}

/// A single piece of saved media (photo or video) — shown as a thumbnail,
/// and fully openable on tap regardless of which type it is. This is the
/// one place the app should render complaint/evidence media, so photo and
/// video handling never has to be reimplemented per screen.
///
/// - Photo: thumbnail loads the image directly; tapping opens a
///   pinch-to-zoom full view.
/// - Video: thumbnail shows a play icon over a dark tile (a real preview
///   frame would need a separate thumbnail-generation step server-side,
///   which this project doesn't have yet — see the note on
///   [_VideoThumbnail]); tapping opens a real, playable video with
///   play/pause and a scrub bar.
///
/// A NOTE ON A COMMON FLUTTER-WEB FAILURE MODE: if photos upload fine but
/// never actually display — no thumbnail, tapping does nothing useful —
/// the file itself is almost never the problem. Firebase Storage's
/// default bucket configuration does not send CORS headers allowing this
/// web app's origin to fetch files via `Image.network` (a browser fetch
/// request), even though the identical URL opens perfectly well as a
/// direct browser navigation (typing it in, or a new tab), which CORS
/// doesn't apply to. The fix lives in Firebase/Google Cloud, not this
/// widget: set a CORS configuration on the Storage bucket allowing this
/// app's origin(s), e.g. via `gsutil cors set cors.json gs://<bucket>`
/// with a cors.json permitting GET from the deployed origin(s) and
/// localhost during development. Until that's set, this widget still
/// gives the person a working "open in new tab" escape hatch rather than
/// a dead end.
class MediaThumbnail extends StatelessWidget {
  const MediaThumbnail({super.key, required this.url, this.size = 84});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final kind = mediaKindForUrl(url);
    return GestureDetector(
      onTap: () => _openViewer(context, kind),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: size,
          height: size,
          child: kind == MediaKind.video ? const _VideoThumbnail() : _ImageThumbnail(url: url),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, MediaKind kind) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            kind == MediaKind.video
                ? _VideoPlayerView(url: url)
                : InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4,
                    child: Image.network(
                      url,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => _BrokenMediaNotice(url: url),
                    ),
                  ),
            // Always-available escape hatch: opening the raw URL as a direct
            // browser navigation works even when Image.network can't load
            // it inline — see the note on [_ImageThumbnail] for why those
            // two paths can behave differently on Flutter Web.
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.open_in_new, color: Colors.white70),
                tooltip: 'فتح في نافذة جديدة',
                onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when Image.network fails to load a saved photo inline. On
/// Flutter Web this is very often NOT a broken or missing file — it is
/// almost always the Firebase Storage bucket's CORS configuration not
/// allowing this app's origin to fetch it via a browser request, even
/// though the exact same URL opens perfectly fine as a direct browser
/// navigation (which is not subject to CORS). This notice says so
/// explicitly and gives that direct-open option right here, rather than
/// showing a bare, unexplained broken-image icon.
class _BrokenMediaNotice extends StatelessWidget {
  const _BrokenMediaNotice({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Colors.white70, size: 32),
          const SizedBox(height: 10),
          const Text(
            'تعذّر عرض الصورة داخل التطبيق — على الأرجح بسبب إعدادات CORS الخاصة بمساحة التخزين (Firebase Storage). يمكن فتحها مباشرة في المتصفح:',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.6),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'فتح الصورة في نافذة جديدة',
            icon: Icons.open_in_new,
            dense: true,
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      // See the CORS note on [MediaThumbnail] — this is almost always a
      // Storage bucket configuration issue, not a missing/corrupt file.
      // Tapping still works and opens the same escape hatch.
      errorBuilder: (context, error, stack) => Container(
        color: AppColors.navy2,
        alignment: Alignment.center,
        child: const Icon(Icons.cloud_off_outlined, color: Colors.white70, size: 20),
      ),
    );
  }
}

/// A generic "this is a video" tile. Not a real preview frame — generating
/// one would need either a server-side thumbnail step (e.g. a Cloud
/// Function on upload) or a client-side video-frame-extraction package,
/// neither of which exists in this project yet. Flagging this honestly
/// rather than pretending it shows a real preview.
class _VideoThumbnail extends StatelessWidget {
  const _VideoThumbnail();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navy2,
      child: const Center(
        child: Icon(Icons.play_circle_fill, color: Colors.white, size: 30),
      ),
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.url});
  final String url;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'تعذّر تشغيل الفيديو.');
    });
    _controller.addListener(() {
      if (mounted) setState(() {}); // refresh play/pause icon and scrub bar
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SizedBox(
        width: 320,
        height: 200,
        child: Center(child: Text(_error!, style: const TextStyle(color: Colors.white))),
      );
    }
    if (!_ready) {
      return const SizedBox(
        width: 320,
        height: 200,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller),
          GestureDetector(
            onTap: () => setState(() {
              _controller.value.isPlaying ? _controller.pause() : _controller.play();
            }),
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 56),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: VideoProgressIndicator(_controller, allowScrubbing: true, padding: const EdgeInsets.all(8)),
          ),
        ],
      ),
    );
  }
}