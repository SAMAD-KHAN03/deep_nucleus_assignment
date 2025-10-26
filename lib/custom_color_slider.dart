import 'package:flutter/material.dart';

// Vertical Color Picker Widget
class CustomColorSlider extends StatefulWidget {
  final Function(Color) onColorChanged;
  final Color initialColor;

  const CustomColorSlider({
    required this.onColorChanged,
    required this.initialColor,
  });

  @override
  State<CustomColorSlider> createState() => CustomColorSliderState();
}

class CustomColorSliderState extends State<CustomColorSlider> {
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
    // Find initial position based on color
    _findPositionForColor(widget.initialColor);
  }

  void _findPositionForColor(Color color) {
    // Find closest color in palette
    int closestIndex = 0;
    double minDistance = double.infinity;

    for (int i = 0; i < _colors.length; i++) {
      double distance = _colorDistance(color, _colors[i]);
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    // Set position based on index
    if (_pickerHeight > 0) {
      _colorSliderPosition = (closestIndex / (_colors.length - 1)) * _pickerHeight;
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

    return Color.lerp(_colors[index], _colors[nextIndex], localRatio) ?? _colors[index];
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
