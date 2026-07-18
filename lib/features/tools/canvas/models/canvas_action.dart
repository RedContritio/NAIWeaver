import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'canvas_layer.dart';
import 'paint_stroke.dart';

/// Sealed class hierarchy for undoable canvas actions.
sealed class CanvasAction {
  const CanvasAction();

  Map<String, dynamic> toJson();

  /// Apply this action to the layer list.
  void apply(List<CanvasLayer> layers, {required String activeLayerId});

  /// Revert (undo) this action on the layer list.
  void revert(List<CanvasLayer> layers);

  static CanvasAction fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'addStroke' => AddStrokeAction._fromJson(json),
      'addLayer' => AddLayerAction._fromJson(json),
      'removeLayer' => RemoveLayerAction._fromJson(json),
      'duplicateLayer' => DuplicateLayerAction._fromJson(json),
      'reorderLayer' => ReorderLayerAction._fromJson(json),
      'setLayerVisibility' => SetLayerVisibilityAction._fromJson(json),
      'setLayerOpacity' => SetLayerOpacityAction._fromJson(json),
      'setLayerBlendMode' => SetLayerBlendModeAction._fromJson(json),
      'renameLayer' => RenameLayerAction._fromJson(json),
      'clearLayer' => ClearLayerAction._fromJson(json),
      'addImageLayer' => AddImageLayerAction._fromJson(json),
      'transformImageLayer' => TransformImageLayerAction._fromJson(json),
      'translateLayer' => TranslateLayerAction._fromJson(json),
      'replaceImageBytes' => ReplaceImageBytesAction._fromJson(json),
      'resizeCanvas' => ResizeCanvasAction._fromJson(json),
      _ => throw ArgumentError('Unknown action type: ${json['type']}'),
    };
  }
}

class AddStrokeAction extends CanvasAction {
  final String layerId;
  final PaintStroke stroke;
  const AddStrokeAction({required this.layerId, required this.stroke});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'addStroke',
        'layerId': layerId,
        'stroke': stroke.toJson(),
      };

  static AddStrokeAction _fromJson(Map<String, dynamic> json) =>
      AddStrokeAction(
        layerId: json['layerId'] as String,
        stroke: PaintStroke.fromJson(json['stroke'] as Map<String, dynamic>),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) {
      layers[idx] = layers[idx].copyWith(strokes: [...layers[idx].strokes, stroke]);
    }
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0 && layers[idx].strokes.isNotEmpty) {
      layers[idx] = layers[idx].copyWith(
        strokes: layers[idx].strokes.sublist(0, layers[idx].strokes.length - 1),
      );
    }
  }
}

class RemoveLayerAction extends CanvasAction {
  final CanvasLayer removedLayer;
  final int index;
  const RemoveLayerAction({required this.removedLayer, required this.index});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'removeLayer',
        'removedLayer': removedLayer.toJson(),
        'index': index,
      };

  static RemoveLayerAction _fromJson(Map<String, dynamic> json) =>
      RemoveLayerAction(
        removedLayer:
            CanvasLayer.fromJson(json['removedLayer'] as Map<String, dynamic>),
        index: json['index'] as int,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    if (index >= 0 && index < layers.length) {
      layers.removeAt(index);
    }
  }

  @override
  void revert(List<CanvasLayer> layers) {
    layers.insert(index.clamp(0, layers.length), removedLayer);
  }
}

class AddLayerAction extends CanvasAction {
  final CanvasLayer layer;
  const AddLayerAction({required this.layer});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'addLayer',
        'layer': layer.toJson(),
      };

  static AddLayerAction _fromJson(Map<String, dynamic> json) => AddLayerAction(
        layer: CanvasLayer.fromJson(json['layer'] as Map<String, dynamic>),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final activeIdx = layers.indexWhere((l) => l.id == activeLayerId);
    final insertIdx = activeIdx >= 0 ? activeIdx + 1 : layers.length;
    layers.insert(insertIdx, layer);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    layers.removeWhere((l) => l.id == layer.id);
  }
}

class ReorderLayerAction extends CanvasAction {
  final int oldIndex;
  final int newIndex;
  const ReorderLayerAction({required this.oldIndex, required this.newIndex});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'reorderLayer',
        'oldIndex': oldIndex,
        'newIndex': newIndex,
      };

  static ReorderLayerAction _fromJson(Map<String, dynamic> json) =>
      ReorderLayerAction(
        oldIndex: json['oldIndex'] as int,
        newIndex: json['newIndex'] as int,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    if (oldIndex >= 0 && oldIndex < layers.length) {
      final layer = layers.removeAt(oldIndex);
      final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
      layers.insert(adjustedNew.clamp(0, layers.length), layer);
    }
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final adjustedNew = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (adjustedNew >= 0 && adjustedNew < layers.length) {
      final layer = layers.removeAt(adjustedNew);
      layers.insert(oldIndex.clamp(0, layers.length), layer);
    }
  }
}

class SetLayerVisibilityAction extends CanvasAction {
  final String layerId;
  final bool oldVisible;
  final bool newVisible;
  const SetLayerVisibilityAction({
    required this.layerId,
    required this.oldVisible,
    required this.newVisible,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'setLayerVisibility',
        'layerId': layerId,
        'oldVisible': oldVisible,
        'newVisible': newVisible,
      };

  static SetLayerVisibilityAction _fromJson(Map<String, dynamic> json) =>
      SetLayerVisibilityAction(
        layerId: json['layerId'] as String,
        oldVisible: json['oldVisible'] as bool,
        newVisible: json['newVisible'] as bool,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(visible: newVisible);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(visible: oldVisible);
  }
}

class SetLayerOpacityAction extends CanvasAction {
  final String layerId;
  final double oldOpacity;
  final double newOpacity;
  const SetLayerOpacityAction({
    required this.layerId,
    required this.oldOpacity,
    required this.newOpacity,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'setLayerOpacity',
        'layerId': layerId,
        'oldOpacity': oldOpacity,
        'newOpacity': newOpacity,
      };

  static SetLayerOpacityAction _fromJson(Map<String, dynamic> json) =>
      SetLayerOpacityAction(
        layerId: json['layerId'] as String,
        oldOpacity: (json['oldOpacity'] as num).toDouble(),
        newOpacity: (json['newOpacity'] as num).toDouble(),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(opacity: newOpacity);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(opacity: oldOpacity);
  }
}

class SetLayerBlendModeAction extends CanvasAction {
  final String layerId;
  final CanvasBlendMode oldMode;
  final CanvasBlendMode newMode;
  const SetLayerBlendModeAction({
    required this.layerId,
    required this.oldMode,
    required this.newMode,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'setLayerBlendMode',
        'layerId': layerId,
        'oldMode': oldMode.name,
        'newMode': newMode.name,
      };

  static SetLayerBlendModeAction _fromJson(Map<String, dynamic> json) =>
      SetLayerBlendModeAction(
        layerId: json['layerId'] as String,
        oldMode: CanvasBlendMode.values.firstWhere(
          (m) => m.name == json['oldMode'],
          orElse: () => CanvasBlendMode.normal,
        ),
        newMode: CanvasBlendMode.values.firstWhere(
          (m) => m.name == json['newMode'],
          orElse: () => CanvasBlendMode.normal,
        ),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(blendMode: newMode);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(blendMode: oldMode);
  }
}

class RenameLayerAction extends CanvasAction {
  final String layerId;
  final String oldName;
  final String newName;
  const RenameLayerAction({
    required this.layerId,
    required this.oldName,
    required this.newName,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'renameLayer',
        'layerId': layerId,
        'oldName': oldName,
        'newName': newName,
      };

  static RenameLayerAction _fromJson(Map<String, dynamic> json) =>
      RenameLayerAction(
        layerId: json['layerId'] as String,
        oldName: json['oldName'] as String,
        newName: json['newName'] as String,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(name: newName);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(name: oldName);
  }
}

class ClearLayerAction extends CanvasAction {
  final String layerId;
  final List<PaintStroke> removedStrokes;
  const ClearLayerAction({
    required this.layerId,
    required this.removedStrokes,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'clearLayer',
        'layerId': layerId,
        'removedStrokes': removedStrokes.map((s) => s.toJson()).toList(),
      };

  static ClearLayerAction _fromJson(Map<String, dynamic> json) =>
      ClearLayerAction(
        layerId: json['layerId'] as String,
        removedStrokes: (json['removedStrokes'] as List)
            .map((j) => PaintStroke.fromJson(j as Map<String, dynamic>))
            .toList(),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(strokes: []);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(strokes: removedStrokes);
  }
}

class DuplicateLayerAction extends CanvasAction {
  final CanvasLayer duplicatedLayer;
  final int insertIndex;
  const DuplicateLayerAction({
    required this.duplicatedLayer,
    required this.insertIndex,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'duplicateLayer',
        'duplicatedLayer': duplicatedLayer.toJson(),
        'insertIndex': insertIndex,
      };

  static DuplicateLayerAction _fromJson(Map<String, dynamic> json) =>
      DuplicateLayerAction(
        duplicatedLayer: CanvasLayer.fromJson(
            json['duplicatedLayer'] as Map<String, dynamic>),
        insertIndex: json['insertIndex'] as int,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    layers.insert(insertIndex.clamp(0, layers.length), duplicatedLayer);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    layers.removeWhere((l) => l.id == duplicatedLayer.id);
  }
}

class AddImageLayerAction extends CanvasAction {
  final CanvasLayer layer;
  const AddImageLayerAction({required this.layer});

  @override
  Map<String, dynamic> toJson() => {
        'type': 'addImageLayer',
        'layer': layer.toJson(),
      };

  static AddImageLayerAction _fromJson(Map<String, dynamic> json) =>
      AddImageLayerAction(
        layer: CanvasLayer.fromJson(json['layer'] as Map<String, dynamic>),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final activeIdx = layers.indexWhere((l) => l.id == activeLayerId);
    final insertIdx = activeIdx >= 0 ? activeIdx + 1 : layers.length;
    layers.insert(insertIdx, layer);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    layers.removeWhere((l) => l.id == layer.id);
  }
}

class TransformImageLayerAction extends CanvasAction {
  final String layerId;
  final double oldX, oldY, oldScale, oldRotation;
  final double newX, newY, newScale, newRotation;

  const TransformImageLayerAction({
    required this.layerId,
    required this.oldX,
    required this.oldY,
    required this.oldScale,
    required this.oldRotation,
    required this.newX,
    required this.newY,
    required this.newScale,
    required this.newRotation,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'transformImageLayer',
        'layerId': layerId,
        'oldX': oldX,
        'oldY': oldY,
        'oldScale': oldScale,
        'oldRotation': oldRotation,
        'newX': newX,
        'newY': newY,
        'newScale': newScale,
        'newRotation': newRotation,
      };

  static TransformImageLayerAction _fromJson(Map<String, dynamic> json) =>
      TransformImageLayerAction(
        layerId: json['layerId'] as String,
        oldX: (json['oldX'] as num).toDouble(),
        oldY: (json['oldY'] as num).toDouble(),
        oldScale: (json['oldScale'] as num).toDouble(),
        oldRotation: (json['oldRotation'] as num).toDouble(),
        newX: (json['newX'] as num).toDouble(),
        newY: (json['newY'] as num).toDouble(),
        newScale: (json['newScale'] as num).toDouble(),
        newRotation: (json['newRotation'] as num).toDouble(),
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) {
      layers[idx] = layers[idx].copyWith(
        imageX: newX, imageY: newY, imageScale: newScale, imageRotation: newRotation);
    }
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) {
      layers[idx] = layers[idx].copyWith(
        imageX: oldX, imageY: oldY, imageScale: oldScale, imageRotation: oldRotation);
    }
  }
}

/// Move a whole layer by a normalized offset (the Move tool): shifts every
/// stroke point and, for image layers, the image position as well.
class TranslateLayerAction extends CanvasAction {
  final String layerId;
  final double dx;
  final double dy;
  final bool moveImage;

  const TranslateLayerAction({
    required this.layerId,
    required this.dx,
    required this.dy,
    this.moveImage = false,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'translateLayer',
        'layerId': layerId,
        'dx': dx,
        'dy': dy,
        'moveImage': moveImage,
      };

  static TranslateLayerAction _fromJson(Map<String, dynamic> json) =>
      TranslateLayerAction(
        layerId: json['layerId'] as String,
        dx: (json['dx'] as num).toDouble(),
        dy: (json['dy'] as num).toDouble(),
        moveImage: json['moveImage'] as bool? ?? false,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    _translate(layers, dx, dy);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    _translate(layers, -dx, -dy);
  }

  void _translate(List<CanvasLayer> layers, double dx, double dy) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx < 0) return;
    final layer = layers[idx];
    final delta = Offset(dx, dy);
    layers[idx] = layer.copyWith(
      strokes: layer.strokes.map((s) => s.translated(delta)).toList(),
      imageX: moveImage ? layer.imageX + dx : layer.imageX,
      imageY: moveImage ? layer.imageY + dy : layer.imageY,
    );
  }
}

class ReplaceImageBytesAction extends CanvasAction {
  final String layerId;
  final Uint8List? oldBytes;
  final Uint8List? newBytes;

  const ReplaceImageBytesAction({
    required this.layerId,
    this.oldBytes,
    this.newBytes,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'replaceImageBytes',
        'layerId': layerId,
      };

  static ReplaceImageBytesAction _fromJson(Map<String, dynamic> json) =>
      ReplaceImageBytesAction(
        layerId: json['layerId'] as String,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(imageBytes: newBytes);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    final idx = layers.indexWhere((l) => l.id == layerId);
    if (idx >= 0) layers[idx] = layers[idx].copyWith(imageBytes: oldBytes);
  }
}

/// Resize the canvas, remapping all normalized stroke/image-layer coordinates.
class ResizeCanvasAction extends CanvasAction {
  final int oldWidth;
  final int oldHeight;
  final int newWidth;
  final int newHeight;
  final int anchorOffsetX;
  final int anchorOffsetY;

  const ResizeCanvasAction({
    required this.oldWidth,
    required this.oldHeight,
    required this.newWidth,
    required this.newHeight,
    required this.anchorOffsetX,
    required this.anchorOffsetY,
  });

  @override
  Map<String, dynamic> toJson() => {
        'type': 'resizeCanvas',
        'oldWidth': oldWidth,
        'oldHeight': oldHeight,
        'newWidth': newWidth,
        'newHeight': newHeight,
        'anchorOffsetX': anchorOffsetX,
        'anchorOffsetY': anchorOffsetY,
      };

  static ResizeCanvasAction _fromJson(Map<String, dynamic> json) =>
      ResizeCanvasAction(
        oldWidth: json['oldWidth'] as int,
        oldHeight: json['oldHeight'] as int,
        newWidth: json['newWidth'] as int,
        newHeight: json['newHeight'] as int,
        anchorOffsetX: json['anchorOffsetX'] as int,
        anchorOffsetY: json['anchorOffsetY'] as int,
      );

  @override
  void apply(List<CanvasLayer> layers, {required String activeLayerId}) {
    _remapLayers(layers, oldWidth, oldHeight, newWidth, newHeight, anchorOffsetX, anchorOffsetY);
  }

  @override
  void revert(List<CanvasLayer> layers) {
    // Inverse: remap back from new→old
    _remapLayers(layers, newWidth, newHeight, oldWidth, oldHeight, -anchorOffsetX, -anchorOffsetY);
  }

  static void _remapLayers(List<CanvasLayer> layers,
      int fromW, int fromH, int toW, int toH, int offX, int offY) {
    for (int i = 0; i < layers.length; i++) {
      final layer = layers[i];

      // Remap strokes
      final remappedStrokes = layer.strokes.map((stroke) {
        final remappedPoints = stroke.points.map((p) {
          final newX = (p.dx * fromW + offX) / toW;
          final newY = (p.dy * fromH + offY) / toH;
          return Offset(newX, newY);
        }).toList();

        // Remap radius (normalized to width)
        final newRadius = stroke.radius * fromW / toW;

        // Remap font size (normalized to height)
        final newFontSize = stroke.fontSize != null
            ? stroke.fontSize! * fromH / toH
            : null;

        // Remap letter spacing (normalized to height)
        final newLetterSpacing = stroke.letterSpacing != null
            ? stroke.letterSpacing! * fromH / toH
            : null;

        return PaintStroke(
          points: remappedPoints,
          radius: newRadius,
          colorValue: stroke.colorValue,
          opacity: stroke.opacity,
          isErase: stroke.isErase,
          strokeType: stroke.strokeType,
          smooth: stroke.smooth,
          text: stroke.text,
          fontSize: newFontSize,
          fontFamily: stroke.fontFamily,
          letterSpacing: newLetterSpacing,
          blurSigma: stroke.blurSigma,
          cloneSourceOffset: stroke.cloneSourceOffset,
        );
      }).toList();

      // Remap image layer position
      double newImgX = layer.imageX;
      double newImgY = layer.imageY;
      double newImgScale = layer.imageScale;
      if (layer.isImageLayer) {
        newImgX = (layer.imageX * fromW + offX) / toW;
        newImgY = (layer.imageY * fromH + offY) / toH;
        newImgScale = layer.imageScale * fromW / toW;
      }

      layers[i] = layer.copyWith(
        strokes: remappedStrokes,
        imageX: newImgX,
        imageY: newImgY,
        imageScale: newImgScale,
      );
    }
  }
}
