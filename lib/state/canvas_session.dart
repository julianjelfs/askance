import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';

import '../engine/crop.dart';
import '../engine/engine.dart';
import '../engine/families.dart';
import '../engine/landmarks.dart';
import '../engine/blur_pass.dart';
import '../engine/lines.dart';
import '../engine/sketch.dart';
import '../engine/value_scale.dart';
import '../model/study.dart';

enum CanvasTool {
  /// How many values, and the stages that set values and detail together.
  steps,

  /// The picture's qualities, which every view shows and the values are cut
  /// from: detail, brightness and contrast.
  picture,

  /// How the shapes form: smooth, rough or straight-edged.
  shapes,

  /// The root of the scale: grey or a tint.
  scale,

  /// The board: crop and grid.
  grid,

  /// Whether PHOTO shows the photograph in colour or black and white.
  tone,

  /// How many values EDGES blocks in under its lines.
  fill,

  /// A photograph of the drawing, laid over the picture to check it.
  sketch,

  /// Light and shadow: where the line between the families falls, and the
  /// dropper that says which side of it a point is on.
  families;

  /// The tools on the tool bar while [mode] is showing. The view selector
  /// picks how to look and the bar holds what adjusts that view, so it never
  /// offers a control that would change nothing on screen: values, shapes
  /// and scale are all lost on the photograph, colour is lost on everything
  /// else, and fill only means something under the edges. The picture and
  /// the drawing laid over it are in every view.
  static List<CanvasTool> barFor(ViewMode mode) => switch (mode) {
    ViewMode.photo => const [picture, tone, families, grid, sketch],
    ViewMode.skeleton => [
      steps,
      picture,
      shapes,
      if (kShowTint) scale,
      fill,
      families,
      grid,
      sketch,
    ],
    // RANDOM paints its own hues, never the families' tint, and its bar
    // already carries another deal: on a phone there is no room for both.
    ViewMode.random => [
      steps,
      picture,
      shapes,
      if (kShowTint) scale,
      grid,
      sketch,
    ],
    _ => [steps, picture, shapes, if (kShowTint) scale, families, grid, sketch],
  };
}

/// Whether the tint (the root of the scale) is offered anywhere. Hidden for
/// now because it went unused; the scale is still stored, rendered and
/// exported, so turning this back on restores it as it was.
const bool kShowTint = false;

/// The open study, plus the view state that is deliberately *not* part of a
/// study: zoom, pan, peek, chrome visibility and which tool is open.
class CanvasSession extends ChangeNotifier {
  ui.Image? image;

  /// Owned here rather than by the canvas widget so that every view of this
  /// study — the canvas, and the copy that flies during the open transition —
  /// shares one finished pass instead of each starting from nothing.
  final BlurPass blur = BlurPass();

  /// The photograph blurred by the study's detail, for PHOTO's squint, a
  /// peek. Only asked for while PHOTO squints.
  final BlurPass photoBlur = BlurPass();

  /// The original bytes, kept so exports can re-run the engine from the source
  /// rather than upscaling the screen raster.
  Uint8List? imageBytes;

  /// Set once the study has been kept on the shelf.
  String? studyId;
  String? imageKey;

  String name = 'Untitled study';
  StudySettings settings = const StudySettings();
  ViewTransform view = const ViewTransform();

  bool peeking = false;

  /// The one band, darkest first, the picture is showing on its own after a
  /// tap on the palette swatch; null shows them all. View state like
  /// [peeking]: a study never records it.
  int? isolatedBand;

  /// The picture turned upside down, as a painter turns the paper, so its
  /// proportions can be judged as shapes rather than as the things they
  /// depict. View state like
  /// [peeking]: a study never records it, and exports are never flipped.
  bool flipped = false;
  bool chromeVisible = true;
  CanvasTool? openTool;

  /// Whether a click on the picture rules lines rather than doing what it
  /// usually does. View state like [peeking], and with it [lineStart], the
  /// first end of a line still being ruled, and [selectedLine], the one a
  /// delete would remove.
  bool drawingLines = false;
  Offset? lineStart;
  int? selectedLine;

  /// The photograph of the drawing, decoded for the screen. Where it lies is
  /// [StudySettings.sketch]; this is only its pixels, read back from storage
  /// when the study opens.
  ui.Image? sketchImage;

  /// Whether gestures on the picture move the drawing rather than the view.
  /// View state like [drawingLines], and like it, a mode of its own: the two
  /// never run at once.
  bool aligningSketch = false;

  /// Whether taps on the picture mark points to check the drawing's
  /// proportions by. A mode of its own, like [drawingLines]: the two never
  /// run at once.
  bool markingPoints = false;

  /// Whether a tap on the picture reads the value under it rather than
  /// doing what it usually does. View state like [drawingLines], and a mode
  /// of its own like it: the three never run at once.
  bool probing = false;

  /// The point last read, on the photograph as [BoardLine] measures it, and
  /// the colour of the pass under it. The colour, not its band, so changing
  /// the values, the brightness or the line between the families reads it
  /// afresh without going back to the GPU. Null until a point is tapped.
  Offset? probePoint;
  (int, int, int)? probeColour;

  Size viewportSize = Size.zero;
  double devicePixelRatio = 1;

  /// Called when a study that is already on the shelf has settled on new
  /// settings, so they can be written back without the user saving again.
  ///
  /// The study id and settings are passed by value rather than read back off
  /// the session, so a write scheduled for one study can never land on
  /// whichever study happens to be open by the time it fires.
  void Function(String studyId, StudySettings settings, String name)? onPersist;

  Timer? _persistDebounce;

  bool get hasImage => image != null;

  /// [resetView] belongs to a freshly picked image. A reopened study has its
  /// view restored by [openStudy] just before its image arrives here, and
  /// resetting then wiped the restored zoom — and the next autosave wrote the
  /// wiped view back over the study, so the passage was lost for good.
  void loadImage(
    ui.Image decoded,
    Uint8List bytes, {
    String? key,
    bool resetView = true,
  }) {
    image?.dispose();
    image = decoded;
    imageBytes = bytes;
    // Taken verbatim, null included: a fresh image has no stored copy yet.
    // Falling back to the previous study's key here meant a new study could
    // be kept under the *old* study's photograph.
    imageKey = key;
    if (resetView) view = const ViewTransform();
    notifyListeners();
  }

  void openStudy(Study study) {
    flushPersist();
    studyId = study.id;
    name = study.name;
    imageKey = study.imageKey;
    settings = study.settings;
    // Come back to the passage you were working on, at the zoom you left it.
    view = study.settings.view;
    isolatedBand = null;
    _stopProbing();
    flipped = false;
    _stopDrawingLines();
    _dropSketchImage();
    openTool = null;
    chromeVisible = true;
    notifyListeners();
  }

  /// Empties the session entirely — deleting the open study from the shelf
  /// must not leave a ghost of it here, still shareable. Nothing is
  /// persisted: the study is going, not settling.
  void clear() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    studyId = null;
    imageKey = null;
    name = 'Untitled study';
    settings = const StudySettings();
    view = const ViewTransform();
    isolatedBand = null;
    _stopProbing();
    flipped = false;
    _stopDrawingLines();
    _dropSketchImage();
    imageBytes = null;
    final old = image;
    image = null;
    if (old != null) _disposeAfterFrame(old);
    notifyListeners();
  }

  /// The stage may still be rasterising the frame that shows [old].
  static void _disposeAfterFrame(ui.Image old) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
      SchedulerBinding.instance.scheduleFrame();
    });
  }

  void startFreshStudy() {
    flushPersist();
    studyId = null;
    imageKey = null;
    name = 'Untitled study';
    settings = const StudySettings();
    view = const ViewTransform();
    isolatedBand = null;
    _stopProbing();
    flipped = false;
    _stopDrawingLines();
    _dropSketchImage();
    openTool = null;
    chromeVisible = true;
    notifyListeners();
  }

  Study toStudy({String? id, DateTime? date}) => Study(
    id: id ?? studyId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    name: name.trim().isEmpty ? 'Untitled study' : name.trim(),
    date: date ?? DateTime.now(),
    imageKey: imageKey ?? '',
    settings: settled,
  );

  /// The study settings as they stand, folding in the view, which is kept
  /// live for the duration of a gesture.
  StudySettings get settled => settings.copyWith(view: view);

  /// Adopts settings that arrived over the QR transfer, wholesale — including
  /// the view, so the phone lands on the passage the sender was looking at.
  ///
  /// Less the drawing laid over it: that photograph stayed behind on the
  /// sending device, so here its key names nothing.
  void applyTransferredSettings(StudySettings incoming) {
    settings = incoming.copyWith(removeSketch: true);
    view = incoming.view;
    isolatedBand = null;
    _stopProbing();
    lineStart = null;
    selectedLine = null;
    notifyListeners();
  }

  // --- study settings -----------------------------------------------------

  void setSteps(int steps) {
    if (steps == settings.steps) return;
    settings = settings.copyWith(
      steps: steps.clamp(StudySettings.minSteps, StudySettings.maxSteps),
    );
    // Band n of five is not band n of three; start from the whole picture.
    isolatedBand = null;
    _persistSoon();
    notifyListeners();
  }

  /// Moves the values and the detail together to one of
  /// [StudySettings.stages].
  void setStage(int index) {
    final stage = StudySettings.stages[index];
    if (stage.steps == settings.steps && stage.detail == settings.detail) {
      return;
    }
    if (stage.steps != settings.steps) isolatedBand = null;
    settings = settings.copyWith(steps: stage.steps, detail: stage.detail);
    _persistSoon();
    notifyListeners();
  }

  void setDetail(double detail) {
    final next = detail.clamp(0.0, 1.0);
    if (next == settings.detail) return;
    settings = settings.copyWith(detail: next);
    _persistSoon();
    notifyListeners();
  }

  void setSmoothing(Smoothing smoothing) {
    if (smoothing == settings.smoothing) return;
    settings = settings.copyWith(smoothing: smoothing);
    _persistSoon();
    notifyListeners();
  }

  void setLockDetail(bool value) {
    if (value == settings.lockDetail) return;
    settings = settings.copyWith(lockDetail: value);
    _persistSoon();
    notifyListeners();
  }

  void setBias(double bias) {
    final next = bias.clamp(-StudySettings.maxBias, StudySettings.maxBias);
    if (next == settings.bias) return;
    settings = settings.copyWith(bias: next);
    _persistSoon();
    notifyListeners();
  }

  void setContrast(double contrast) {
    final next = contrast.clamp(-1.0, 1.0);
    if (next == settings.contrast) return;
    settings = settings.copyWith(contrast: next);
    _persistSoon();
    notifyListeners();
  }

  /// Splits the picture into light and shadow families, or stops. Splitting
  /// moves no value: the line goes on the band boundary nearest where the
  /// photograph's darks and lights part, so only the tint changes. The
  /// slider or "Find the line" frees it from the boundaries.
  Future<void> setFamilies(bool value) async {
    if (value == (settings.shadowSteps != null)) return;
    if (!value) {
      settings = settings.copyWith(removeFamilies: true);
      _persistSoon();
      notifyListeners();
      return;
    }
    final line = await _otsuLine();
    // Split already, by another tap while the histogram was taken.
    if (settings.shadowSteps != null) return;
    final steps = settings.steps;
    final shadow = line == null ? steps ~/ 2 : (line * steps).round();
    settings = settings.copyWith(shadowSteps: shadow.clamp(1, steps - 1));
    _persistSoon();
    notifyListeners();
  }

  /// Puts the family line at Otsu's threshold for the whole photograph.
  Future<void> findFamilyLine() async {
    final line = await _otsuLine();
    if (line == null || settings.shadowSteps == null) return;
    setFamilyLine(line);
  }

  /// Otsu's threshold for the whole photograph, in toned lightness; null
  /// with no photograph, or a different one by the time it is taken.
  Future<double?> _otsuLine() async {
    final source = image;
    if (source == null) return null;
    final asked = settings;
    final line = await otsuLine(
      source,
      asked.crop,
      bias: asked.bias,
      contrast: asked.contrast,
    );
    return image == source ? line : null;
  }

  /// Where the line between the families falls, in toned lightness.
  void setFamilyLine(double at) {
    final next = at.clamp(StudySettings.minLine, StudySettings.maxLine);
    if (next == settings.familyLine || settings.shadowSteps == null) return;
    settings = settings.copyWith(familyLine: next);
    _persistSoon();
    notifyListeners();
  }

  /// How many steps the shadow family has. With the line free, the light
  /// family keeps its own and the steps grow or shrink; on a band boundary,
  /// the line moves within the steps there are.
  void setShadowSteps(int count) {
    final light = settings.steps - (settings.shadowBands ?? 0);
    if (settings.familyLine != null) {
      final next = count.clamp(1, StudySettings.maxSteps - light);
      if (next == settings.shadowBands) return;
      settings = settings.copyWith(shadowSteps: next, steps: next + light);
      isolatedBand = null;
    } else {
      final next = count.clamp(1, settings.steps - 1);
      if (next == settings.shadowBands) return;
      settings = settings.copyWith(shadowSteps: next);
    }
    _persistSoon();
    notifyListeners();
  }

  /// How many steps the light family has; the shadow keeps its own.
  void setLightSteps(int count) {
    final shadow = settings.shadowBands;
    if (shadow == null) return;
    setSteps(shadow + count.clamp(1, StudySettings.maxSteps - shadow));
  }

  /// Whether the palette leaves a value out between the families.
  void setFamilyGap(bool value) {
    if (value == settings.familyGap) return;
    settings = settings.copyWith(familyGap: value);
    _persistSoon();
    notifyListeners();
  }

  void setScale(ValueScale scale) {
    if (scale == settings.scale) return;
    settings = settings.copyWith(scale: scale);
    _persistSoon();
    notifyListeners();
  }

  void setMode(ViewMode mode) {
    if (mode == settings.mode) {
      // Tapping RANDOM while it is showing is the gesture of the mode:
      // another deal of colours over the same values. Every other mode
      // treats a repeat tap as nothing new.
      if (mode != ViewMode.random) return;
      dealColours();
      return;
    } else {
      settings = settings.copyWith(
        mode: mode,
        // First entry into RANDOM gets a fresh deal too — seed 0 is the
        // never-dealt default, and without this every study's first palette
        // was seed 0's. A study saved in random mode reopens through
        // openStudy, not here, so a kept palette is never redrawn.
        randomSeed: mode == ViewMode.random && settings.randomSeed == 0
            ? math.Random().nextInt(1 << 31)
            : null,
        // The skeleton is laid over whatever was showing, so its fill
        // blocks in the colours it was entered from. From anywhere else
        // the base stays as it last was.
        skeletonBase: mode == ViewMode.skeleton
            ? (settings.mode == ViewMode.random
                  ? ViewMode.random
                  : settings.mode == ViewMode.value
                  ? ViewMode.value
                  : settings.skeletonBase)
            : null,
      );
    }
    // A tool the new view's bar does not offer would be adjusting nothing.
    if (openTool case final tool?
        when !CanvasTool.barFor(settings.mode).contains(tool)) {
      openTool = null;
    }
    // VALUE and RANDOM share bands, so an isolated band survives moving
    // between them, and a new deal; anywhere else has no swatch to undo it.
    if (!settings.mode.paintsOnlyPalette) isolatedBand = null;
    _persistSoon();
    notifyListeners();
  }

  /// Another deal of RANDOM's colours over the same values.
  void dealColours() {
    // A fresh draw, not seed + 1: every study starts at seed 0, so an
    // incrementing seed dealt every study the same palette sequence. The
    // draw is still stored, so the palette survives repaint and reopening.
    settings = settings.copyWith(randomSeed: math.Random().nextInt(1 << 31));
    _persistSoon();
    notifyListeners();
  }

  void setTone(PhotoTone tone) {
    if (tone == settings.tone) return;
    settings = settings.copyWith(tone: tone);
    _persistSoon();
    notifyListeners();
  }

  void setGrid(GridMode grid) {
    if (grid == settings.grid) return;
    settings = settings.copyWith(grid: grid);
    _persistSoon();
    notifyListeners();
  }

  void setGridLevel(int level) {
    final next = level.clamp(
      StudySettings.minGridLevel,
      StudySettings.maxGridLevel,
    );
    if (next == settings.gridLevel) return;
    settings = settings.copyWith(gridLevel: next);
    _persistSoon();
    notifyListeners();
  }

  /// Jump straight to a fill count — the desktop's segmented control.
  void setSkeletonFill(int fill) {
    final next = fill.clamp(0, settings.steps);
    if (next == settings.skeletonFill) return;
    settings = settings.copyWith(skeletonFill: next);
    _persistSoon();
    notifyListeners();
  }

  /// Each tap blocks in one more value, darkest first; past the last it
  /// returns to edges alone. The count survives a steps change by clamping
  /// at paint time rather than resetting here.
  void cycleSkeletonFill() {
    settings = settings.copyWith(
      skeletonFill: (settings.skeletonFill + 1) % (settings.steps + 1),
    );
    _persistSoon();
    notifyListeners();
  }

  /// The part of the picture on screen now, as [StudySettings.gridFrame]
  /// measures it. The zoom stays inside the picture's own frame, so which
  /// part shows does not depend on the room it is shown in, and the picture's
  /// own size will do for one.
  Rect get shownFrame =>
      _sourceSize.isEmpty ? kWholeImage : view.shown(_sourceSize, _sourceSize);

  /// Whether the grid already divides exactly what is on screen.
  bool get gridFitsView => settings.gridFrame == shownFrame;

  /// Lays the grid over what is on screen: the view framed by zooming becomes
  /// the board the grid divides, and zooming from here magnifies it.
  void resetGrid() {
    final frame = shownFrame;
    if (frame == settings.gridFrame) return;
    settings = settings.copyWith(gridFrame: frame);
    _persistSoon();
    notifyListeners();
  }

  /// Crops the study to [crop], a fraction of each side of the photograph,
  /// and shows the new picture whole: a zoom and pan chosen inside the old
  /// crop describe a different passage inside the new one, and so does a
  /// grid reset to one.
  void setCrop(Rect crop) {
    if (crop == settings.crop) return;
    settings = settings.copyWith(crop: crop, gridFrame: kWholeImage);
    view = const ViewTransform();
    probePoint = null;
    probeColour = null;
    _persistSoon();
    notifyListeners();
  }

  // --- lines ----------------------------------------------------------------

  void setDrawingLines(bool value) {
    if (value == drawingLines) return;
    if (value) {
      drawingLines = true;
      aligningSketch = false;
      markingPoints = false;
      _stopProbing();
    } else {
      _stopDrawingLines();
    }
    notifyListeners();
  }

  void _stopDrawingLines() {
    drawingLines = false;
    lineStart = null;
    selectedLine = null;
  }

  /// A click while ruling lines, at [point] on the photograph as [BoardLine]
  /// measures it. The first click of a line places its start; the second
  /// rules it. A second click on the first does nothing but forget it.
  void placeLineEnd(Offset point) {
    final start = lineStart;
    selectedLine = null;
    if (start == null) {
      lineStart = point;
    } else {
      lineStart = null;
      if (point != start) {
        settings = settings.copyWith(
          lines: [...settings.lines, BoardLine(start, point)],
        );
        _persistSoon();
      }
    }
    notifyListeners();
  }

  /// Moves one end, 0 or 1, of line [index] to [point] on the photograph.
  void moveLineEnd(int index, int end, Offset point) {
    final lines = [...settings.lines];
    final next = lines[index].withEnd(end, point);
    if (next == lines[index]) return;
    lines[index] = next;
    settings = settings.copyWith(lines: lines);
    _persistSoon();
    notifyListeners();
  }

  void selectLine(int? index) {
    if (index == selectedLine) return;
    selectedLine = index;
    notifyListeners();
  }

  /// Escape: forgets a half-ruled line or a selection, in that order.
  /// Returns whether there was either.
  bool cancelLine() {
    if (lineStart == null && selectedLine == null) return false;
    lineStart = null;
    selectedLine = null;
    notifyListeners();
    return true;
  }

  /// Removes the selected line. Returns whether there was one.
  bool deleteSelectedLine() {
    final index = selectedLine;
    if (index == null) return false;
    settings = settings.copyWith(lines: [...settings.lines]..removeAt(index));
    selectedLine = null;
    _persistSoon();
    notifyListeners();
    return true;
  }

  void clearLines() {
    if (settings.lines.isEmpty && lineStart == null) return;
    settings = settings.copyWith(lines: const []);
    lineStart = null;
    selectedLine = null;
    _persistSoon();
    notifyListeners();
  }

  // --- the drawing laid over the picture ----------------------------------

  Size? get photoSize => image == null
      ? null
      : Size(image!.width.toDouble(), image!.height.toDouble());

  /// Lays a newly added photograph of the drawing over the picture, fitted
  /// to the crop, and starts lining it up. [decoded] is already squared up
  /// to [page], when a page was found in it. Returns the key of the one it
  /// replaces, which nothing names any more.
  String? addSketch(ui.Image decoded, String key, {List<Offset>? page}) {
    final photo = photoSize;
    if (photo == null) {
      decoded.dispose();
      return null;
    }
    final previous = settings.sketch;
    final placed = fittedSketch(
      imageKey: key,
      photo: photo,
      sketch: Size(decoded.width.toDouble(), decoded.height.toDouble()),
      crop: settings.crop,
      page: page,
    );
    settings = settings.copyWith(
      // A replacement keeps the fade it was being looked through at.
      sketch: placed.copyWith(opacity: previous?.opacity),
    );
    _dropSketchImage();
    sketchImage = decoded;
    setAligningSketch(true);
    _persistSoon();
    notifyListeners();
    return previous?.imageKey;
  }

  /// The pixels for the study's drawing, read back after it opened. Taken
  /// only if they are still the drawing it has: the study may have been
  /// swapped or the drawing replaced while they loaded.
  void loadSketchImage(String key, ui.Image decoded) {
    if (settings.sketch?.imageKey != key) {
      decoded.dispose();
      return;
    }
    _dropSketchImage();
    sketchImage = decoded;
    notifyListeners();
  }

  /// The drawing's pixels again, squared up to its page or as the whole
  /// photograph as [straighten] says, with [page] in place of the one it
  /// had if given. Its shape changes with them, so it is fitted to the crop
  /// afresh and lined up again.
  void restraightenSketch(
    String key,
    ui.Image decoded,
    bool straighten, {
    List<Offset>? page,
  }) {
    final sketch = settings.sketch;
    final photo = photoSize;
    if (sketch == null || sketch.imageKey != key || photo == null) {
      decoded.dispose();
      return;
    }
    final placed = fittedSketch(
      imageKey: key,
      photo: photo,
      sketch: Size(decoded.width.toDouble(), decoded.height.toDouble()),
      crop: settings.crop,
      page: page ?? sketch.page,
      straighten: straighten,
    );
    settings = settings.copyWith(
      sketch: placed.copyWith(opacity: sketch.opacity),
    );
    _dropSketchImage();
    sketchImage = decoded;
    setAligningSketch(true);
    _persistSoon();
    notifyListeners();
  }

  void moveSketch(SketchOverlay next) {
    if (next == settings.sketch) return;
    settings = settings.copyWith(sketch: next);
    _persistSoon();
    notifyListeners();
  }

  void setSketchOpacity(double value) {
    final sketch = settings.sketch;
    if (sketch == null) return;
    moveSketch(sketch.copyWith(opacity: value.clamp(0.0, 1.0)));
  }

  /// Takes the drawing away. Returns the key of its photograph, which
  /// nothing names any more.
  String? removeSketch() {
    final sketch = settings.sketch;
    if (sketch == null) return null;
    settings = settings.copyWith(removeSketch: true);
    _dropSketchImage();
    _persistSoon();
    notifyListeners();
    return sketch.imageKey;
  }

  /// Lining up takes the gestures, so it shuts whatever else wanted them:
  /// ruling lines, and on the phone the sheet over the picture.
  void setAligningSketch(bool value) {
    if (value && settings.sketch == null) return;
    if (value == aligningSketch) return;
    aligningSketch = value;
    if (value) {
      _stopDrawingLines();
      _stopProbing();
      markingPoints = false;
      openTool = null;
      chromeVisible = true;
    }
    notifyListeners();
  }

  // --- points to check the drawing's proportions by -----------------------

  /// Starts or ends marking points. Ending it lays the drawing over the
  /// picture as the points fit it, when there are enough to fit, so the
  /// overlay shows what is left over.
  void setMarkingPoints(bool value) {
    if (value && settings.sketch == null) return;
    if (value == markingPoints) return;
    if (!value) _lineUpOnPoints();
    markingPoints = value;
    selectedPoint = null;
    if (value) {
      _stopDrawingLines();
      _stopProbing();
      aligningSketch = false;
      // Taps on the picture place points, so on the phone the sheet over
      // it goes, as it does for lining up.
      openTool = null;
      chromeVisible = true;
    }
    notifyListeners();
  }

  /// The size of the drawing's photograph as shown, which its marks are
  /// fractions of. Null while it is not loaded.
  Size? get _drawingSize => sketchImage == null
      ? null
      : Size(sketchImage!.width.toDouble(), sketchImage!.height.toDouble());

  List<Offset?> get _marks => settings.sketch?.marks ?? const [];

  /// The landmark whose half on the drawing the next tap places: the first
  /// not yet marked there. Null when the next tap picks a new point on the
  /// picture, or there is no drawing to mark.
  int? get nextMark {
    if (settings.sketch == null || sketchImage == null) return null;
    final marks = _marks;
    for (var i = 0; i < settings.landmarks.length; i++) {
      if (i >= marks.length || marks[i] == null) return i;
    }
    return null;
  }

  /// The point the name chips act on: the one last placed on the picture,
  /// or the one last tapped in either pane. Null when none is.
  int? selectedPoint;

  void selectPoint(int? index) {
    if (index == selectedPoint) return;
    selectedPoint = index;
    notifyListeners();
  }

  /// Calls landmark [index] [name], or nothing for an empty one.
  void nameLandmark(int index, String? name) {
    if (index >= settings.landmarks.length) return;
    final landmarks = [...settings.landmarks];
    final named = landmarks[index].named(name);
    if (named == landmarks[index]) return;
    landmarks[index] = named;
    settings = settings.copyWith(landmarks: landmarks);
    _persistSoon();
    notifyListeners();
  }

  /// Whether mark [i] has been placed on the drawing.
  bool isMarked(int i) => i < _marks.length && _marks[i] != null;

  /// A tap on the picture while marking: a new point there, at [point] on
  /// the photograph as a fraction of each side.
  void addLandmark(Offset point) {
    if (settings.landmarks.length >= kMaxLandmarks) return;
    selectedPoint = settings.landmarks.length;
    _placed.add(settings.landmarks.length);
    settings = settings.copyWith(
      landmarks: [...settings.landmarks, Landmark(point)],
    );
    _persistSoon();
    notifyListeners();
  }

  /// A tap on the drawing while marking, at [mark] as a fraction of each
  /// side of its photograph: the drawing's half of the first point not yet
  /// marked on it. Nothing while every point is.
  void placeMark(Offset mark) {
    final next = nextMark;
    if (next == null) return;
    _setMark(next, mark);
    _placed.add(-1 - next);
    _persistSoon();
    notifyListeners();
  }

  /// Puts landmark [index], on the picture, at [point] on the photograph.
  void moveLandmark(int index, Offset point) {
    final landmarks = [...settings.landmarks];
    if (landmarks[index].at == point) return;
    landmarks[index] = landmarks[index].movedTo(point);
    settings = settings.copyWith(landmarks: landmarks);
    _persistSoon();
    notifyListeners();
  }

  /// Puts the drawing's half of landmark [index] at [mark] on its
  /// photograph.
  void moveMark(int index, Offset mark) {
    if (!isMarked(index) || _marks[index] == mark) return;
    _setMark(index, mark);
    _persistSoon();
    notifyListeners();
  }

  void _setMark(int index, Offset mark) {
    final sketch = settings.sketch;
    if (sketch == null) return;
    final marks = [..._marks];
    while (marks.length <= index) {
      marks.add(null);
    }
    marks[index] = Offset(mark.dx.clamp(0.0, 1.0), mark.dy.clamp(0.0, 1.0));
    settings = settings.copyWith(sketch: sketch.copyWith(marks: marks));
  }

  /// What each tap while marking placed, latest last: the index of a
  /// landmark, or of a mark as `-1 - index`. Only for [undoPoint], so not
  /// kept with the study.
  final List<int> _placed = [];

  /// Takes back the last point placed. With nothing placed since the study
  /// opened, the last mark on the drawing, or failing that the last point
  /// on the picture.
  void undoPoint() {
    final landmarks = settings.landmarks;
    if (landmarks.isEmpty) return;
    final marks = _marks;
    final lastMark = marks.lastIndexWhere((m) => m != null);
    final last = _placed.isNotEmpty
        ? _placed.removeLast()
        : lastMark >= 0
        ? -1 - lastMark
        : landmarks.length - 1;
    if (last < 0) {
      if (-1 - last < marks.length) _dropMark(-1 - last);
    } else if (last == landmarks.length - 1) {
      settings = settings.copyWith(
        landmarks: landmarks.sublist(0, last),
        sketch: settings.sketch?.copyWith(
          marks: marks.length > last ? marks.sublist(0, last) : marks,
        ),
      );
    }
    if (selectedPoint case final p? when p >= settings.landmarks.length) {
      selectedPoint = null;
    }
    _persistSoon();
    notifyListeners();
  }

  void _dropMark(int index) {
    final sketch = settings.sketch!;
    final marks = [...sketch.marks];
    marks[index] = null;
    while (marks.isNotEmpty && marks.last == null) {
      marks.removeLast();
    }
    settings = settings.copyWith(sketch: sketch.copyWith(marks: marks));
  }

  /// Takes away every point, on the picture and on the drawing.
  void clearPoints() {
    if (settings.landmarks.isEmpty && _marks.isEmpty) return;
    _placed.clear();
    selectedPoint = null;
    settings = settings.copyWith(
      landmarks: const [],
      sketch: settings.sketch?.copyWith(marks: const []),
    );
    _persistSoon();
    notifyListeners();
  }

  /// The drawing's points against the picture's, for every landmark marked
  /// on both. Null under three such pairs. The picture's in pixels of the
  /// photograph, the drawing's in pixels of its own: the fit finds the
  /// scale and turn between them, so how the overlay lies does not matter.
  LandmarkFit? get landmarkFit {
    final photo = photoSize;
    final drawing = _drawingSize;
    if (photo == null || drawing == null) return null;
    final picture = <Offset>[];
    final drawn = <Offset>[];
    final numbers = <int>[];
    final names = <String?>[];
    for (var i = 0; i < settings.landmarks.length; i++) {
      if (!isMarked(i)) continue;
      final p = settings.landmarks[i].at;
      final m = _marks[i]!;
      picture.add(Offset(p.dx * photo.width, p.dy * photo.height));
      drawn.add(Offset(m.dx * drawing.width, m.dy * drawing.height));
      numbers.add(i + 1);
      names.add(settings.landmarks[i].name);
    }
    return fitLandmarks(picture, drawn, numbers: numbers, names: names);
  }

  /// Lays the drawing over the picture as the fit puts it, so its points
  /// lie as near the picture's as they can. What is left over is the
  /// drawing's own.
  void _lineUpOnPoints() {
    final fit = landmarkFit;
    final sketch = settings.sketch;
    final photo = photoSize;
    final drawing = _drawingSize;
    if (fit == null || sketch == null || photo == null || drawing == null) {
      return;
    }
    moveSketch(fit.overlay(sketch, photo, drawing));
  }

  void _dropSketchImage() {
    aligningSketch = false;
    markingPoints = false;
    // A new photograph of the drawing starts its marks afresh.
    _placed.removeWhere((p) => p < 0);
    final old = sketchImage;
    sketchImage = null;
    if (old != null) _disposeAfterFrame(old);
  }

  // --- the dropper ------------------------------------------------------------

  void setProbing(bool value) {
    if (value == probing) return;
    if (value) {
      probing = true;
      _stopDrawingLines();
      aligningSketch = false;
      markingPoints = false;
    } else {
      _stopProbing();
    }
    notifyListeners();
  }

  /// Where the point last read falls: its band, and its family when the
  /// picture has families. Null until its colour has been read.
  BandPlace? get probePlace {
    final colour = probeColour;
    if (colour == null) return null;
    final (r, g, b) = colour;
    return BandPlace(
      band: bandOfColour(
        r,
        g,
        b,
        settings.steps,
        bias: settings.bias,
        contrast: settings.contrast,
        split: settings.split,
      ),
      steps: settings.steps,
      shadowBands: settings.shadowBands,
    );
  }

  void _stopProbing() {
    probing = false;
    probePoint = null;
    probeColour = null;
  }

  /// A tap while probing, at [point] on the photograph. The colour under it
  /// follows from the pass, which the surface reads and hands back.
  void placeProbe(Offset point) {
    probePoint = point;
    probeColour = null;
    notifyListeners();
  }

  /// The colour of the pass under [point], if it is still the point being
  /// read: a read that lands after another tap is stale.
  void setProbeColour(Offset point, (int, int, int)? colour) {
    if (point != probePoint || colour == probeColour) return;
    probeColour = colour;
    notifyListeners();
  }

  void rename(String value) {
    name = value;
    _persistSoon();
    notifyListeners();
  }

  // --- view state ---------------------------------------------------------

  void setView(ViewTransform next) {
    if (next == view) return;
    view = next;
    // Debounced, so a pinch writes once when it settles rather than per frame.
    _persistSoon();
    notifyListeners();
  }

  /// Tapping a band shows it alone; tapping it again shows them all.
  void toggleIsolatedBand(int band) {
    isolatedBand = isolatedBand == band ? null : band;
    notifyListeners();
  }

  void setFlipped(bool value) {
    if (value == flipped) return;
    flipped = value;
    notifyListeners();
  }

  void setPeeking(bool value) {
    if (value == peeking) return;
    peeking = value;
    notifyListeners();
  }

  void toggleChrome() {
    chromeVisible = !chromeVisible;
    if (!chromeVisible) openTool = null;
    notifyListeners();
  }

  /// A single tap on the picture. With a tool's sheet open over it, the tap
  /// closes the sheet; otherwise it hides or shows the controls.
  void tapPicture() {
    if (chromeVisible && openTool != null) {
      closeTool();
      return;
    }
    toggleChrome();
  }

  void setChromeVisible(bool value) {
    if (value == chromeVisible) return;
    chromeVisible = value;
    notifyListeners();
  }

  /// Tapping the open tool closes it.
  void toggleTool(CanvasTool tool) {
    openTool = openTool == tool ? null : tool;
    notifyListeners();
  }

  void closeTool() {
    if (openTool == null) return;
    openTool = null;
    notifyListeners();
  }

  void setViewport(Size size, double dpr) {
    if (size == viewportSize && dpr == devicePixelRatio) return;
    viewportSize = size;
    devicePixelRatio = dpr;
  }

  /// Double tap cycles 1x -> 2.4x -> 4x -> 1x, centred on the tap point.
  void cycleZoom(Offset focus) {
    const stops = [1.0, 2.4, 4.0];
    final index = stops.indexWhere((z) => (z - view.zoom).abs() < 0.01);
    final next = stops[(index + 1) % stops.length];
    setView(view.zoomedAt(focus, next, _sourceSize, viewportSize));
  }

  Size get _sourceSize => image == null
      ? Size.zero
      : croppedSize(
          Size(image!.width.toDouble(), image!.height.toDouble()),
          settings.crop,
        );

  // --- keeping a saved study up to date -----------------------------------

  /// Nothing to write until a study has been kept on the shelf; an unsaved
  /// study is still just a view of a photograph.
  void _persistSoon() {
    if (studyId == null) return;
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  /// Writes any pending change immediately. Called before the open study is
  /// swapped out and when the canvas is left, so a change made in the last few
  /// hundred milliseconds is not lost.
  void flushPersist() {
    _persistDebounce?.cancel();
    _persistDebounce = null;
    _persistNow();
  }

  void _persistNow() {
    final id = studyId;
    if (id == null) return;
    onPersist?.call(id, settled, name);
  }

  /// Renders the pass this study needs at [outputPx] and waits for it, so the
  /// canvas is never put on screen showing the untouched photograph first.
  Future<void> warmBlur(Size outputPx) async {
    final source = image;
    if (source == null || outputPx.isEmpty) return;
    blur.request(
      source: source,
      outputPx: outputPx,
      detail: settings.detail,
      view: view,
      smoothing: settings.smoothing,
      lockDetail: settings.lockDetail,
      crop: settings.crop,
      steps: settings.steps,
      bias: settings.bias,
      contrast: settings.contrast,
      split: settings.split,
    );
    if (settings.photoNeedsOwnPass) {
      photoBlur.request(
        source: source,
        outputPx: outputPx,
        detail: settings.detail,
        view: view,
        lockDetail: settings.lockDetail,
        crop: settings.crop,
      );
    }
    await Future.wait([blur.settled, photoBlur.settled]);
  }

  @override
  void dispose() {
    blur.dispose();
    photoBlur.dispose();
    _persistDebounce?.cancel();
    image?.dispose();
    sketchImage?.dispose();
    super.dispose();
  }
}
