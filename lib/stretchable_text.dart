import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:myapp/custom_color_slider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stroke_text/stroke_text.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

class VideoWithTextOverlay extends StatefulWidget {
  const VideoWithTextOverlay({super.key});

  @override
  State<VideoWithTextOverlay> createState() => _VideoWithTextOverlayState();
}

class _VideoWithTextOverlayState extends State<VideoWithTextOverlay> {
  VideoPlayerController? _controller;
  final ImagePicker _picker = ImagePicker();

  // List of text overlays
  List<_TextOverlay> texts = [];
  int? _editingIndex;
  Color _selectedColor = Colors.white;

  Future<List<Map<String, dynamic>>> _prepareMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    String? storedUuid = prefs.getString('userid');

    if (_controller == null || !_controller!.value.isInitialized) return [];

    // Original video resolution
    final videoWidth = _controller!.value.size.width;
    final videoHeight = _controller!.value.size.height;

    // Displayed size in UI
    final renderBoxWidth = MediaQuery.of(context).size.width;
    final renderBoxHeight = MediaQuery.of(context).size.height;

    // BoxFit.cover scaling
    final scale = max(
      renderBoxWidth / videoWidth,
      renderBoxHeight / videoHeight,
    );

    // Cropped offset due to BoxFit.cover
    final offsetX = (renderBoxWidth - videoWidth * scale) / 2;
    final offsetY = (renderBoxHeight - videoHeight * scale) / 2;

    return texts.map((t) {
      // Account for the 60px UI offset
      final uiX = t.position.dx + 60;
      final uiY = t.position.dy;
      
      // Convert Flutter UI coordinates to original video coordinates
      final videoX = ((uiX - offsetX) / scale).clamp(0.0, videoWidth);
      final videoY = ((uiY - offsetY) / scale).clamp(0.0, videoHeight);

      // Send NORMALIZED coordinates (0-1 range)
      return {
        "userid": storedUuid,
        "text": t.text,
        "x": (videoX / videoWidth).clamp(0.0, 1.0),  // Normalized X
        "y": (videoY / videoHeight).clamp(0.0, 1.0), // Normalized Y
        "scale": t.scale,
        "color": "#${t.color.value.toRadixString(16).substring(2).padLeft(6, '0')}", // Remove alpha channel
      };
    }).toList();
  }

  Future<void> _uploadVideoWithMetadata() async {
    if (_controller == null) return;

    final videoPath = _controller!.dataSource.replaceFirst('file://', '');
    final videoFile = File(videoPath);
    final metadata = await _prepareMetadata();

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 120),
      ),
    );
    final url = "http://3.110.56.232:3000/render-video";

    FormData formData = FormData.fromMap({
      "video": await MultipartFile.fromFile(
        videoFile.path,
        filename: "video.mp4",
      ),
      "metadata": jsonEncode(metadata),
    });

    try {
      final response = await dio.post(
        url,
        data: formData,
        options: Options(headers: {"Content-Type": "multipart/form-data"}),
      );

      if (response.statusCode == 200) {
        print("Upload successful: ${response.data}");
      } else {
        print("Upload failed: ${response.statusCode}");
      }
    } catch (e, st) {
      print("Upload error: $e");
      print(st);
    }
  }

  // Show dialog to choose between gallery and camera
  Future<void> _showVideoSourceDialog() async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Video Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record Video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo(ImageSource.camera);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Pick video from gallery or record from camera
  Future<void> _pickVideo(ImageSource source) async {
    try {
      print("Opening ${source == ImageSource.camera ? 'camera' : 'gallery'}...");
      
      final XFile? file = await _picker.pickVideo(
        source: source,
        maxDuration: source == ImageSource.camera 
            ? const Duration(minutes: 5) 
            : null,
      );

      print("Picker returned: ${file?.path ?? 'null'}");

      if (file != null) {
        print("Loading video from: ${file.path}");
        _controller?.dispose();
        _controller = VideoPlayerController.file(File(file.path))
          ..initialize().then((_) {
            print("Video initialized successfully");
            _controller!.setLooping(true);
            _controller!.play();
            if (mounted) {
              setState(() {});
            }
          }).catchError((error) {
            print("Error initializing video: $error");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error loading video: $error'),
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
      } else {
        print("No video selected/recorded (user may have cancelled)");
        if (mounted && source == ImageSource.camera) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording cancelled or permission denied. Please enable camera and microphone permissions in Settings.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      print("Error picking video: $e");
      print("Stack trace: $stackTrace");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}. Please check app permissions in Settings.'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _addText(Offset position) {
    setState(() {
      texts.add(
        _TextOverlay(text: '', position: position, color: _selectedColor),
      );
      _editingIndex = texts.length - 1;
    });
  }

  void _setEditingIndex(int? index) {
    setState(() {
      _editingIndex = index;
      if (index != null) {
        _selectedColor = texts[index].color;
      }
    });
  }

  void _updateTextColor(Color color) {
    setState(() {
      _selectedColor = color;
      if (_editingIndex != null) {
        texts[_editingIndex!].color = color;
      }
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: _controller == null || !_controller!.value.isInitialized
          ? Center(
              child: ElevatedButton(
                onPressed: _showVideoSourceDialog,
                child: const Text("Pick or Record Video"),
              ),
            )
          : GestureDetector(
              onDoubleTapDown: (details) {
                if (_editingIndex == null) {
                  _addText(details.localPosition);
                }
              },
              child: Stack(
                children: [
                  // Full-screen video
                  SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    ),
                  ),
                  // Render all text overlays
                  for (int i = 0; i < texts.length; i++)
                    _StretchableTextWidget(
                      key: ValueKey(i),
                      overlay: texts[i],
                      isEditing: _editingIndex == i,
                      onUpdate: () {
                        setState(() {}); // refresh UI
                      },
                      onDelete: () {
                        setState(() {
                          texts.removeAt(i);
                          if (_editingIndex == i) {
                            _editingIndex = null;
                          }
                        });
                      },
                      onStartEdit: () {
                        _setEditingIndex(i);
                      },
                      onEndEdit: () {
                        if (_editingIndex == i) {
                          _setEditingIndex(null);
                        }
                      },
                    ),
                  // Color Picker - shown only when editing
                  if (_editingIndex != null)
                    Positioned(
                      left: 20,
                      top: 0,
                      bottom: 0,
                      child: CustomColorSlider(
                        onColorChanged: _updateTextColor,
                        initialColor: _selectedColor,
                      ),
                    ),
                  // Done button at top-right
                  Positioned(
                    top: 40,
                    right: 20,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.black54,
                        onPressed: () async {
                          await _uploadVideoWithMetadata();
                        },
                        child: const Icon(Icons.done),
                      ),
                    ),
                  ),
                  // Floating back button
                  Positioned(
                    top: 40,
                    left: 20,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: Colors.black54,
                        onPressed: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// Text overlay data
class _TextOverlay {
  String text;
  Offset position;
  double scale = 1.0;
  Color color;

  _TextOverlay({
    required this.text,
    required this.position,
    this.color = Colors.white,
  });
}

// Widget for individual stretchable text
class _StretchableTextWidget extends StatefulWidget {
  final _TextOverlay overlay;
  final bool isEditing;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onStartEdit;
  final VoidCallback onEndEdit;

  const _StretchableTextWidget({
    required this.overlay,
    required this.isEditing,
    required this.onUpdate,
    required this.onDelete,
    required this.onStartEdit,
    required this.onEndEdit,
    Key? key,
  }) : super(key: key);

  @override
  State<_StretchableTextWidget> createState() => _StretchableTextWidgetState();
}

class _StretchableTextWidgetState extends State<_StretchableTextWidget> {
  late double _baseScale;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  late Offset _startPosition;
  late Offset _dragStartLocal;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.overlay.text);
    _focusNode = FocusNode();
    _baseScale = widget.overlay.scale;
    _startPosition = widget.overlay.position;

    if (widget.isEditing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(_StretchableTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing && !oldWidget.isEditing) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    } else if (!widget.isEditing && oldWidget.isEditing) {
      _focusNode.unfocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure valid scale
    final safeScale =
        (widget.overlay.scale.isNaN ||
            widget.overlay.scale.isInfinite ||
            widget.overlay.scale <= 0)
        ? 1.0
        : widget.overlay.scale;

    return Positioned(
      left: widget.overlay.position.dx + 60,
      top: widget.overlay.position.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) {
          if (!widget.isEditing) {
            _baseScale =
                (widget.overlay.scale.isNaN ||
                    widget.overlay.scale.isInfinite ||
                    widget.overlay.scale <= 0)
                ? 1.0
                : widget.overlay.scale;
            _startPosition = widget.overlay.position;
            _dragStartLocal = details.localFocalPoint;
            _isDragging = true;
          }
        },
        onScaleUpdate: (details) {
          if (!widget.isEditing && _isDragging) {
            setState(() {
              if (details.pointerCount == 1) {
                widget.overlay.position =
                    _startPosition +
                    (details.localFocalPoint - _dragStartLocal);
              }
              if (details.pointerCount > 1) {
                final newScale = (_baseScale * details.scale).clamp(0.4, 6.0);
                if (!newScale.isNaN && !newScale.isInfinite) {
                  widget.overlay.scale = newScale;
                }
              }
              widget.onUpdate();
            });
          }
        },
        onScaleEnd: (details) => _isDragging = false,
        onLongPress: () {
          if (!widget.isEditing) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Text'),
                content: const Text('Do you want to delete this text?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
          }
        },
        onTap: () {
          if (!widget.isEditing) {
            widget.onStartEdit();
          }
        },
        child: SizedBox(
          width: 200,
          height: 80,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(safeScale, safeScale, 1.0),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: widget.isEditing ? Colors.black38 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: widget.isEditing
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: widget.isEditing
                  ? IntrinsicWidth(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        cursorColor: widget.overlay.color,
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: widget.overlay.color,
                          shadows: const [
                            Shadow(
                              blurRadius: 4.0,
                              color: Colors.black,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 4),
                          border: InputBorder.none,
                          hintText: 'Enter text',
                          hintStyle: TextStyle(color: Colors.white54),
                        ),
                        onChanged: (value) => widget.overlay.text = value,
                        onSubmitted: (value) {
                          widget.overlay.text = value;
                          widget.onEndEdit();
                        },
                      ),
                    )
                  : GestureDetector(
                      onTap: widget.onStartEdit,
                      child: StrokeText(
                        text: widget.overlay.text.isEmpty
                            ? 'Tap to edit'
                            : widget.overlay.text,
                        textStyle: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: widget.overlay.text.isEmpty
                              ? Colors.white54
                              : widget.overlay.color,
                        ),
                        strokeColor: Colors.black,
                        strokeWidth: 2.5,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}