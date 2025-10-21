import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

class PickAndPlayVideo extends StatefulWidget {
  const PickAndPlayVideo({super.key});

  @override
  State<PickAndPlayVideo> createState() => _PickAndPlayVideoState();
}

class _PickAndPlayVideoState extends State<PickAndPlayVideo> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickVideo() async {
    // Pick video from gallery or camera
    final XFile? file = await _picker.pickVideo(
      source: ImageSource.gallery, // or ImageSource.camera
    );

    if (file != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              FullScreenVideoPlayer(videoFile: File(file.path)),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller != null && _controller!.value.isInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover, // <-- fills entire screen
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          : Center(
              child: ElevatedButton(
                onPressed: _pickVideo,
                child: const Text("Pick or Record Video"),
              ),
            ),
    );
  }
}

// Full-screen video player screen
class FullScreenVideoPlayer extends StatefulWidget {
  final File videoFile;
  const FullScreenVideoPlayer({required this.videoFile, super.key});

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        _controller.setLooping(true);
        _controller.play();
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _controller.value.isInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
