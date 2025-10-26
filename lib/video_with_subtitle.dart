import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

// Model for subtitle segments
class SubtitleSegment {
  final int id;
  final String transcript;
  final double startTime;
  final double endTime;

  SubtitleSegment({
    required this.id,
    required this.transcript,
    required this.startTime,
    required this.endTime,
  });

  factory SubtitleSegment.fromJson(Map<String, dynamic> json) {
    return SubtitleSegment(
      id: json['id'] as int,
      transcript: json['transcript'] as String,
      startTime: double.parse(json['start_time'].toString()),
      endTime: double.parse(json['end_time'].toString()),
    );
  }

  bool isActiveAt(double currentTime) {
    return currentTime >= startTime && currentTime <= endTime;
  }
}

// Subtitle parser
class SubtitleParser {
  static List<SubtitleSegment> parseFromJson(String jsonString) {
    try {
      final data = jsonDecode(jsonString);
      final segments = data['audio_segments'] as List;
      return segments.map((seg) => SubtitleSegment.fromJson(seg)).toList();
    } catch (e) {
      print('Error parsing subtitles: $e');
      return [];
    }
  }

  // Parse SRT format
  static List<SubtitleSegment> parseFromSRT(String srtContent) {
    final subtitles = <SubtitleSegment>[];
    final blocks = srtContent.trim().split('\n\n');

    for (var i = 0; i < blocks.length; i++) {
      final lines = blocks[i].split('\n');
      if (lines.length < 3) continue;

      try {
        // Parse timestamp line (e.g., "00:00:03,650 --> 00:00:10,300")
        final timeLine = lines[1];
        final times = timeLine.split(' --> ');
        final startTime = _parseTimeToSeconds(times[0]);
        final endTime = _parseTimeToSeconds(times[1]);

        // Get subtitle text (all lines after timestamp)
        final text = lines.sublist(2).join(' ');

        subtitles.add(
          SubtitleSegment(
            id: i,
            transcript: text,
            startTime: startTime,
            endTime: endTime,
          ),
        );
      } catch (e) {
        print('Error parsing block: $e');
      }
    }

    return subtitles;
  }

  // Parse VTT format
  static List<SubtitleSegment> parseFromVTT(String vttContent) {
    final subtitles = <SubtitleSegment>[];
    final lines = vttContent.split('\n');

    int id = 0;
    String? currentTime;
    List<String> currentText = [];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // Skip WEBVTT header and empty lines
      if (line.isEmpty || line.startsWith('WEBVTT')) continue;

      // Check if this is a timestamp line
      if (line.contains('-->')) {
        // Save previous subtitle if exists
        if (currentTime != null && currentText.isNotEmpty) {
          final times = currentTime.split(' --> ');
          subtitles.add(
            SubtitleSegment(
              id: id++,
              transcript: currentText.join(' '),
              startTime: _parseTimeToSeconds(times[0]),
              endTime: _parseTimeToSeconds(times[1]),
            ),
          );
          currentText = [];
        }
        currentTime = line;
      } else if (currentTime != null && !line.startsWith('NOTE')) {
        // This is subtitle text
        currentText.add(line);
      }
    }

    // Add last subtitle
    if (currentTime != null && currentText.isNotEmpty) {
      final times = currentTime.split(' --> ');
      subtitles.add(
        SubtitleSegment(
          id: id,
          transcript: currentText.join(' '),
          startTime: _parseTimeToSeconds(times[0]),
          endTime: _parseTimeToSeconds(times[1]),
        ),
      );
    }

    return subtitles;
  }

  static double _parseTimeToSeconds(String timeString) {
    // Remove any extra spaces and handle both comma and dot as decimal separator
    timeString = timeString.trim().replaceAll(',', '.');

    // Format: HH:MM:SS.mmm or MM:SS.mmm
    final parts = timeString.split(':');

    if (parts.length == 3) {
      // HH:MM:SS.mmm
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final seconds = double.parse(parts[2]);
      return hours * 3600 + minutes * 60 + seconds;
    } else if (parts.length == 2) {
      // MM:SS.mmm
      final minutes = int.parse(parts[0]);
      final seconds = double.parse(parts[1]);
      return minutes * 60 + seconds;
    }

    return 0.0;
  }
}

// Subtitle display widget
class SubtitleOverlay extends StatefulWidget {
  final VideoPlayerController controller;
  final List<SubtitleSegment> subtitles;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final EdgeInsets? padding;
  final double? bottomOffset;

  const SubtitleOverlay({
    Key? key,
    required this.controller,
    required this.subtitles,
    this.textStyle,
    this.backgroundColor,
    this.padding,
    this.bottomOffset,
  }) : super(key: key);

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  String _currentSubtitle = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateSubtitle);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateSubtitle);
    super.dispose();
  }

  void _updateSubtitle() {
    if (!widget.controller.value.isInitialized) return;

    final currentTime =
        widget.controller.value.position.inMilliseconds / 1000.0;

    // Find the active subtitle
    final activeSubtitle = widget.subtitles.firstWhere(
      (sub) => sub.isActiveAt(currentTime),
      orElse: () =>
          SubtitleSegment(id: -1, transcript: '', startTime: 0, endTime: 0),
    );

    if (_currentSubtitle != activeSubtitle.transcript) {
      setState(() {
        _currentSubtitle = activeSubtitle.transcript;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSubtitle.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottomOffset ?? 80,
      child: Center(
        child: Container(
          padding:
              widget.padding ??
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _currentSubtitle,
            textAlign: TextAlign.center,
            style:
                widget.textStyle ??
                const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
          ),
        ),
      ),
    );
  }
}

// Enum for video source type
enum VideoSourceType {
  asset,    // Video from assets folder
  file,     // Video from device file system
  network,  // Video from URL
}

// Example usage widget
class VideoWithSubtitles extends StatefulWidget {
  final String videoPath;
  final String subtitleData;
  final SubtitleFormat format;
  final VideoSourceType sourceType;

  const VideoWithSubtitles({
    Key? key,
    required this.videoPath,
    required this.subtitleData,
    this.format = SubtitleFormat.json,
    this.sourceType = VideoSourceType.network,
  }) : super(key: key);

  @override
  State<VideoWithSubtitles> createState() => _VideoWithSubtitlesState();
}

enum SubtitleFormat { json, srt, vtt }

class _VideoWithSubtitlesState extends State<VideoWithSubtitles> {
  VideoPlayerController? _controller;
  List<SubtitleSegment> _subtitles = [];
  bool _initialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeVideoAndSubtitles();
  }

  Future<void> _initializeVideoAndSubtitles() async {
    try {
      // Initialize video controller based on source type
      switch (widget.sourceType) {
        case VideoSourceType.asset:
          _controller = VideoPlayerController.asset(widget.videoPath);
          break;
        case VideoSourceType.file:
          _controller = VideoPlayerController.file(File(widget.videoPath));
          break;
        case VideoSourceType.network:
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.videoPath),
          );
          break;
      }

      // Initialize the controller
      await _controller!.initialize();

      // Parse subtitles based on format
      switch (widget.format) {
        case SubtitleFormat.json:
          _subtitles = SubtitleParser.parseFromJson(widget.subtitleData);
          break;
        case SubtitleFormat.srt:
          _subtitles = SubtitleParser.parseFromSRT(widget.subtitleData);
          break;
        case SubtitleFormat.vtt:
          _subtitles = SubtitleParser.parseFromVTT(widget.subtitleData);
          break;
      }

      setState(() {
        _initialized = true;
      });

      // Auto-play the video
      _controller!.play();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading video: $e';
        _initialized = false;
      });
      print('Video initialization error: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show error if initialization failed
    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  _initializeVideoAndSubtitles();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Show loading indicator
    if (!_initialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video player
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),

          // Subtitle overlay
          if (_subtitles.isNotEmpty)
            SubtitleOverlay(
              controller: _controller!,
              subtitles: _subtitles,
              textStyle: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(
                    color: Colors.black,
                    offset: Offset(1, 1),
                    blurRadius: 3,
                  ),
                ],
              ),
            ),

          // Play/Pause button
          Center(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(20),
                child: Icon(
                  _controller!.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                  size: 64,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 40,
            left: 20,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Video progress indicator
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.red,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.white24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}