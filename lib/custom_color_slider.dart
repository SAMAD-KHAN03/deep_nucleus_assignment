import 'package:flutter/material.dart';

class VerticalColorPicker extends StatefulWidget {
  const VerticalColorPicker({Key? key}) : super(key: key);

  @override
  _VerticalColorPickerState createState() => _VerticalColorPickerState();
}

class _VerticalColorPickerState extends State<VerticalColorPicker> {
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
    Color.fromARGB(255, 128, 128, 128),
  ];

  void _colorChangeHandler(double position) {
    if (position > _pickerHeight) position = _pickerHeight;
    if (position < 0) position = 0;
    setState(() {
      _colorSliderPosition = position;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white, // white background for demo
      alignment: Alignment.center,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _pickerHeight = constraints.maxHeight / 2;
          if (_colorSliderPosition == 0) {
            _colorSliderPosition = _pickerHeight;
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            onVerticalDragUpdate: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            onTapDown: (details) =>
                _colorChangeHandler(details.localPosition.dy - 15),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Container(
                width: 30, // thin vertical bar
                height: _pickerHeight,
                decoration: BoxDecoration(
                  border: Border.all(width: 2, color: Colors.grey[800]!),
                  borderRadius: BorderRadius.circular(10),
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
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      8,
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
