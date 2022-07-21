import 'package:example/plugin/debuggable_rich_text.dart';
import 'package:flowy_editor/flowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';

class SelectedTextNodeBuilder extends NodeWidgetBuilder {
  SelectedTextNodeBuilder.create({
    required super.node,
    required super.editorState,
    required super.key,
  }) : super.create() {
    nodeValidator = ((node) {
      return node.type == 'text';
    });
  }

  @override
  Widget build(BuildContext buildContext) {
    print('key -> $key');
    return _SelectedTextNodeWidget(
      key: key,
      node: node,
      editorState: editorState,
    );
  }
}

class _SelectedTextNodeWidget extends StatefulWidget {
  final Node node;
  final EditorState editorState;

  const _SelectedTextNodeWidget({
    Key? key,
    required this.node,
    required this.editorState,
  }) : super(key: key);

  @override
  State<_SelectedTextNodeWidget> createState() =>
      _SelectedTextNodeWidgetState();
}

class _SelectedTextNodeWidgetState extends State<_SelectedTextNodeWidget>
    with Selectable, KeyboardEventsRespondable {
  TextNode get node => widget.node as TextNode;
  EditorState get editorState => widget.editorState;

  final _textKey = GlobalKey();
  TextSelection? _textSelection;

  RenderParagraph get _renderParagraph =>
      _textKey.currentContext?.findRenderObject() as RenderParagraph;

  @override
  List<Rect> getOverlayRectsInRange(Offset start, Offset end) {
    var textSelection =
        TextSelection(baseOffset: 0, extentOffset: node.toRawString().length);
    // Returns select all if the start or end exceeds the size of the box
    // TODO: don't need to compute everytime.
    var rects = _computeSelectionRects(textSelection);
    _textSelection = textSelection;

    if (end.dy > start.dy) {
      // downward
      if (end.dy >= rects.last.bottom) {
        return rects;
      }
    } else {
      // upward
      if (end.dy <= rects.first.top) {
        return rects;
      }
    }

    final selectionBaseOffset = _getTextPositionAtOffset(start).offset;
    final selectionExtentOffset = _getTextPositionAtOffset(end).offset;
    textSelection = TextSelection(
      baseOffset: selectionBaseOffset,
      extentOffset: selectionExtentOffset,
    );
    _textSelection = textSelection;
    return _computeSelectionRects(textSelection);
  }

  @override
  Rect getCursorRect(Offset start) {
    final selectionBaseOffset = _getTextPositionAtOffset(start).offset;
    final textSelection = TextSelection.collapsed(offset: selectionBaseOffset);
    _textSelection = textSelection;
    return _computeCursorRect(textSelection.baseOffset);
  }

  @override
  KeyEventResult onKeyDown(RawKeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final textSelection = _textSelection;
      // TODO: just handle upforward delete.
      if (textSelection != null) {
        if (textSelection.isCollapsed) {
          print(node.toRawString());
          print('is empty ${node.toRawString().isEmpty}');
          if (textSelection.baseOffset == 0 && node.toRawString().isEmpty) {
            TransactionBuilder(editorState)
              ..deleteNode(node)
              ..commit();
          } else {
            TransactionBuilder(editorState)
              ..deleteText(node, textSelection.start - 1, 1)
              ..commit();
            final rect = _computeCursorRect(textSelection.baseOffset - 1);
            editorState.tapOffset = rect.center;
            editorState.updateCursor();
          }
        } else {
          TransactionBuilder(editorState)
            ..deleteText(node, textSelection.start,
                textSelection.baseOffset - textSelection.extentOffset)
            ..commit();
        }
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    print('text rebuild $this');
    Widget richText;
    if (kDebugMode) {
      richText = DebuggableRichText(text: node.toTextSpan(), textKey: _textKey);
    } else {
      richText = RichText(key: _textKey, text: node.toTextSpan());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: MediaQuery.of(context).size.width,
          child: richText,
        ),
        if (node.children.isNotEmpty)
          ...node.children.map(
            (e) => editorState.renderPlugins.buildWidget(
              context: NodeWidgetContext(
                buildContext: context,
                node: e,
                editorState: editorState,
              ),
            ),
          ),
        const SizedBox(
          height: 5,
        ),
      ],
    );
  }

  TextPosition _getTextPositionAtOffset(Offset offset) {
    final textOffset = _renderParagraph.globalToLocal(offset);
    return _renderParagraph.getPositionForOffset(textOffset);
  }

  List<Rect> _computeSelectionRects(TextSelection selection) {
    final textBoxes = _renderParagraph.getBoxesForSelection(selection);
    return textBoxes
        .map((box) =>
            _renderParagraph.localToGlobal(box.toRect().topLeft) &
            box.toRect().size)
        .toList();
  }

  Rect _computeCursorRect(int offset) {
    final position = TextPosition(offset: offset);
    var cursorOffset = _renderParagraph.getOffsetForCaret(position, Rect.zero);
    cursorOffset = _renderParagraph.localToGlobal(cursorOffset);
    final cursorHeight = _renderParagraph.getFullHeightForCaret(position);
    if (cursorHeight != null) {
      const cursorWidth = 2;
      return Rect.fromLTWH(
        cursorOffset.dx - (cursorWidth / 2),
        cursorOffset.dy,
        cursorWidth.toDouble(),
        cursorHeight.toDouble(),
      );
    } else {
      return Rect.zero;
    }
  }
}

extension on TextNode {
  TextSpan toTextSpan() => TextSpan(
      children: delta.operations
          .whereType<TextInsert>()
          .map((op) => op.toTextSpan())
          .toList());
}

extension on TextInsert {
  TextSpan toTextSpan() {
    FontWeight? fontWeight;
    FontStyle? fontStyle;
    TextDecoration? decoration;
    GestureRecognizer? gestureRecognizer;
    Color color = Colors.black;
    Color highLightColor = Colors.transparent;
    double fontSize = 16.0;
    final attributes = this.attributes;
    if (attributes?['bold'] == true) {
      fontWeight = FontWeight.bold;
    }
    if (attributes?['italic'] == true) {
      fontStyle = FontStyle.italic;
    }
    if (attributes?['underline'] == true) {
      decoration = TextDecoration.underline;
    }
    if (attributes?['strikethrough'] == true) {
      decoration = TextDecoration.lineThrough;
    }
    if (attributes?['highlight'] is String) {
      highLightColor = Color(int.parse(attributes!['highlight']));
    }
    if (attributes?['href'] is String) {
      color = const Color.fromARGB(255, 55, 120, 245);
      decoration = TextDecoration.underline;
      gestureRecognizer = TapGestureRecognizer()
        ..onTap = () {
          launchUrlString(attributes?['href']);
        };
    }
    final heading = attributes?['heading'] as String?;
    if (heading != null) {
      // TODO: make it better
      if (heading == 'h1') {
        fontSize = 30.0;
      } else if (heading == 'h2') {
        fontSize = 20.0;
      }
      fontWeight = FontWeight.bold;
    }
    return TextSpan(
      text: content,
      style: TextStyle(
        fontWeight: fontWeight,
        fontStyle: fontStyle,
        decoration: decoration,
        color: color,
        fontSize: fontSize,
        backgroundColor: highLightColor,
      ),
      recognizer: gestureRecognizer,
    );
  }
}

class FlowyPainter extends CustomPainter {
  final List<Rect> _rects;
  final Paint _paint;

  FlowyPainter({
    Key? key,
    required Color color,
    required List<Rect> rects,
    bool fill = false,
  })  : _rects = rects,
        _paint = Paint()..color = color {
    _paint.style = fill ? PaintingStyle.fill : PaintingStyle.stroke;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final rect in _rects) {
      canvas.drawRect(
        rect,
        _paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
