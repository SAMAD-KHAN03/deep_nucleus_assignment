import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
                  // Color Picker - shown only when editing
                  if (_editingIndex != null)
                    Positioned(
                      left: 20,
                      top: 0,
                      bottom: 0,
                      child: _VerticalColorPicker(
                        onColorChanged: _updateTextColor,
                        initialColor: _selectedColor,
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

// Vertical Color Picker Widget
class _VerticalColorPicker extends StatefulWidget {
  final Function(Color) onColorChanged;
  final Color initialColor;

  const _VerticalColorPicker({
    required this.onColorChanged,
    required this.initialColor,
  });

  @override
  State<_VerticalColorPicker> createState() => _VerticalColorPickerState();
}

class _VerticalColorPickerState extends State<_VerticalColorPicker> {
  double _colorSliderPosition = 0;
  double _pickerHeight = 0;

  final List<Color> _colors = [
    Color.fromARGB(255, 255, 0, 0),
    Color.fromARGB(255, 255, 128, 0),
    Color.fromARGB(255, 255, 255, 0),
    Color.fromARGB(255, 128, 255, 0),
    Color.fromARGB(255, 0, 255, 0),
    Color.fromARGB(255, 0, 255, 128),
    Color.fromARGB(255, 0, 255, 255),
    Color.fromARGB(255, 0, 128, 255),
    Color.fromARGB(255, 0, 0, 255),
    Color.fromARGB(255, 127, 0, 255),
    Color.fromARGB(255, 255, 0, 255),
    Color.fromARGB(255, 255, 0, 127),
    Color.fromARGB(255, 255, 255, 255),
    Color.fromARGB(255, 0, 0, 0),
  ];

  @override
  void initState() {
    super.initState();
    _findPositionForColor(widget.initialColor);
  }

  void _findPositionForColor(Color color) {
    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < _colors.length; i++) {
      double distance = _colorDistance(color, _colors[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    if (_pickerHeight > 0) {
      _colorSliderPosition =
          (closestIndex / (_colors.length - 1)) * _pickerHeight;
    }
  }

  double _colorDistance(Color c1, Color c2) {
    return ((c1.red - c2.red) * (c1.red - c2.red) +
            (c1.green - c2.green) * (c1.green - c2.green) +
            (c1.blue - c2.blue) * (c1.blue - c2.blue))
        .toDouble();
  }

  Color _getColorAtPosition(double position) {
    double ratio = (position / _pickerHeight).clamp(0.0, 1.0);
    int index = (ratio * (_colors.length - 1)).floor();
    int nextIndex = (index + 1).clamp(0, _colors.length - 1);

    double localRatio = (ratio * (_colors.length - 1)) - index;

    return Color.lerp(_colors[index], _colors[nextIndex], localRatio) ??
        _colors[index];
  }

  void _colorChangeHandler(double position) {
    if (position > _pickerHeight) position = _pickerHeight;
    if (position < 0) position = 0;
    setState(() {
      _colorSliderPosition = position;
    });
    widget.onColorChanged(_getColorAtPosition(position));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _pickerHeight = constraints.maxHeight * 0.6;
          if (_colorSliderPosition == 0) {
            _colorSliderPosition = _pickerHeight / 2;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            onVerticalDragUpdate: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            onTapDown: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            child: Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                width: 30,
                height: _pickerHeight,
                decoration: BoxDecoration(
                  border: Border.all(width: 2, color: Colors.white70),
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _colors,
                  ),
                ),
                child: CustomPaint(
                  painter: _VerticalSliderIndicatorPainter(
                    _colorSliderPosition,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VerticalSliderIndicatorPainter extends CustomPainter {
  final double position;
  _VerticalSliderIndicatorPainter(this.position);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, position);
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_VerticalSliderIndicatorPainter old) =>
      old.position != position;
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
      left: widget.overlay.position.dx+60 ,
      top: widget.overlay.position.dy ,
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
        // Use SizedBox instead of Container with infinite constraints
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
