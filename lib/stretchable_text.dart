import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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

  // Pick video from gallery or camera
  Future<void> _pickVideo() async {
    final XFile? file = await _picker.pickVideo(
      source: ImageSource.gallery, // or ImageSource.camera
    );

    if (file != null) {
      _controller?.dispose();
      _controller = VideoPlayerController.file(File(file.path))
        ..initialize().then((_) {
          _controller!.setLooping(true);
          _controller!.play();
          setState(() {});
        });
    }
  }

  void _addText(Offset position) {
    setState(() {
      texts.add(_TextOverlay(
        text: '',
        position: position,
      ));
      _editingIndex = texts.length - 1;
    });
  }

  void _setEditingIndex(int? index) {
    setState(() {
      _editingIndex = index;
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
                onPressed: _pickVideo,
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
                  // Optional: Floating back button
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
                  // Instruction text
                  // if (texts.isEmpty)
                  //   const Positioned(
                  //     bottom: 100,
                  //     left: 0,
                  //     right: 0,
                  //     child: Center(
                  //       child: Text(
                  //         'Double tap to add text',
                  //         style: TextStyle(
                  //           color: Colors.white,
                  //           fontSize: 18,
                  //           shadows: [
                  //             Shadow(
                  //               blurRadius: 10.0,
                  //               color: Colors.black,
                  //               offset: Offset(0, 0),
                  //             ),
                  //           ],
                  //         ),
                  //       ),
                  //     ),
                  //   ),
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

  _TextOverlay({required this.text, required this.position});
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

  // Track positions
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
    return Positioned(
      left: widget.overlay.position.dx - 40,
      top: widget.overlay.position.dy - 40,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: (details) {
          if (!widget.isEditing) {
            _baseScale = widget.overlay.scale;
            _startPosition = widget.overlay.position;
            _dragStartLocal = details.localFocalPoint;
            _isDragging = true;
          }
        },
        onScaleUpdate: (details) {
          if (!widget.isEditing && _isDragging) {
            setState(() {
              if (details.pointerCount == 1) {
                // Single finger drag
                widget.overlay.position = _startPosition + (details.localFocalPoint - _dragStartLocal);
              }
              if (details.pointerCount > 1) {
                // Multi-finger pinch to scale
                widget.overlay.scale = (_baseScale * details.scale).clamp(0.5, 5.0);
              }
              widget.onUpdate();
            });
          }
        },
        onScaleEnd: (details) {
          _isDragging = false;
        },
        onLongPress: () {
          if (!widget.isEditing) {
            // Long press to delete
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
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
            widget.overlay.scale,
            widget.overlay.scale,
            1.0,
          ),
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
                      cursorColor: Colors.white,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
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
                      onChanged: (value) {
                        widget.overlay.text = value;
                      },
                      onSubmitted: (value) {
                        widget.overlay.text = value;
                        widget.onEndEdit();
                      },
                    ),
                  )
                : GestureDetector(
                    onTap: widget.onStartEdit,
                    child: Text(
                      widget.overlay.text.isEmpty ? 'Tap to edit' : widget.overlay.text,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: widget.overlay.text.isEmpty ? Colors.white54 : Colors.white,
                        shadows: const [
                          Shadow(
                            blurRadius: 4.0,
                            color: Colors.black,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}