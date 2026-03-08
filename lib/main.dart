import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as v;
import 'dart:async';

void main() {
  runApp(const RubixCubePro());
}

class RubixCubePro extends StatelessWidget {
  const RubixCubePro({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rubix Cube Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF050510),
      ),
      home: const CubeGameScreen(),
    );
  }
}

// --- MODELS ---

enum CubeFace { front, back, left, right, top, bottom }

class Cubie {
  v.Vector3 position;
  Map<CubeFace, Color> faceColors;
  v.Matrix4 rotationMatrix;

  Cubie({
    required this.position,
    required this.faceColors,
  }) : rotationMatrix = v.Matrix4.identity();

  void rotate(v.Vector3 axis, double angle) {
    v.Matrix4 rotation = v.Matrix4.identity()..rotate(axis, angle);
    rotationMatrix = rotation * rotationMatrix;
    v.Vector4 pos4 = v.Vector4(position.x, position.y, position.z, 1.0);
    v.Vector4 newPos4 = rotation * pos4;
    position = v.Vector3(
      newPos4.x.roundToDouble(),
      newPos4.y.roundToDouble(),
      newPos4.z.roundToDouble(),
    );
  }
}

// --- GAME LOGIC & STATE ---

class MoveRecord {
  final v.Vector3 axis;
  final double angle;
  final double pos;
  MoveRecord(this.axis, this.angle, this.pos);
}

class AnimatedSlice {
  final v.Vector3 axis;
  final double targetAngle;
  final bool Function(Cubie) filter;
  final double pos;
  double currentAngle = 0;

  AnimatedSlice(this.axis, this.targetAngle, this.filter, this.pos);
}

class CubeController extends ChangeNotifier {
  List<Cubie> cubies = [];
  v.Matrix4 globalRotation = v.Matrix4.identity()
    ..rotateX(-0.6)
    ..rotateY(0.6);

  bool isRotating = false;
  AnimatedSlice? animatedSlice;
  List<MoveRecord> moveHistory = [];

  bool isAutoPlayback = false;
  bool isSequencePlaying = false;
  DateTime? startTime;
  DateTime? endTime;
  
  VoidCallback? onSolved;
  bool _wasSolved = true; // Tracks previous state so we only trigger once per win

  CubeController() {
    _initCube();
  }

  void _initCube() {
    for (int x = -1; x <= 1; x++) {
      for (int y = -1; y <= 1; y++) {
        for (int z = -1; z <= 1; z++) {
          if (x == 0 && y == 0 && z == 0) continue;

          cubies.add(Cubie(
            position: v.Vector3(x.toDouble(), y.toDouble(), z.toDouble()),
            faceColors: {
              CubeFace.front: z == 1 ? const Color(0xFF1E88E5) : Colors.black,
              CubeFace.back: z == -1 ? const Color(0xFF43A047) : Colors.black,
              CubeFace.top: y == -1 ? Colors.white : Colors.black,
              CubeFace.bottom: y == 1 ? const Color(0xFFFDD835) : Colors.black,
              CubeFace.left: x == -1 ? const Color(0xFFE53935) : Colors.black,
              CubeFace.right: x == 1 ? const Color(0xFFFB8C00) : Colors.black,
            },
          ));
        }
      }
    }
  }

  void updateGlobalRotation(double dx, double dy) {
    v.Matrix4 rotY = v.Matrix4.identity()..rotateY(dx * 2.5);
    v.Matrix4 rotX = v.Matrix4.identity()..rotateX(dy * 2.5);
    globalRotation = rotY * rotX * globalRotation;
    notifyListeners();
  }

  void beginAnimatedSlice(v.Vector3 axis, double angle, bool Function(Cubie) filter, double pos) {
    if (isRotating) return;
    isRotating = true;
    animatedSlice = AnimatedSlice(axis, angle, filter, pos);
  }

  void updateAnimatedSlice(double progress) {
    if (animatedSlice != null) {
      animatedSlice!.currentAngle = animatedSlice!.targetAngle * progress;
      notifyListeners();
    }
  }

  void commitAnimatedSlice() {
    if (animatedSlice != null) {
      // Record user moves or shuffle moves, but NEVER Auto Solve moves!
      if (!isAutoPlayback) {
        moveHistory.add(MoveRecord(animatedSlice!.axis, animatedSlice!.targetAngle, animatedSlice!.pos));
      }
      for (var cubie in cubies) {
        if (animatedSlice!.filter(cubie)) {
          cubie.rotate(animatedSlice!.axis, animatedSlice!.targetAngle);
        }
      }
      animatedSlice = null;
    }
    isRotating = false;

    bool currentlySolved = isCubeSolved();
    if (currentlySolved && !_wasSolved) {
      endTime = DateTime.now(); // Stop timer
      onSolved?.call();     // Trigger Congratulations
    }
    _wasSolved = currentlySolved;

    notifyListeners();
  }

  bool isCubeSolved() {
    List<v.Vector3> dirs = [
      v.Vector3(1, 0, 0), v.Vector3(-1, 0, 0),
      v.Vector3(0, 1, 0), v.Vector3(0, -1, 0),
      v.Vector3(0, 0, 1), v.Vector3(0, 0, -1),
    ];

    for (var dir in dirs) {
      Color? faceColor;
      for (var cubie in cubies) {
        v.Vector3 worldPos = cubie.rotationMatrix.transform3(cubie.position.clone());
        worldPos = v.Vector3(worldPos.x.roundToDouble(), worldPos.y.roundToDouble(), worldPos.z.roundToDouble());
        
        if (worldPos.dot(dir) > 0.5) {
          for (var f in CubeFace.values) {
            v.Vector3 originalNormal = _getNormalForFace(f);
            v.Vector3 worldNormal = cubie.rotationMatrix.transform3(originalNormal);
            worldNormal = v.Vector3(worldNormal.x.roundToDouble(), worldNormal.y.roundToDouble(), worldNormal.z.roundToDouble());
            
            if (worldNormal.dot(dir) > 0.5) {
              Color c = cubie.faceColors[f]!;
              if (c != Colors.black) {
                if (faceColor == null) {
                  faceColor = c;
                } else if (faceColor != c) {
                  return false;
                }
              }
            }
          }
        }
      }
    }
    return true;
  }

  v.Vector3 _getNormalForFace(CubeFace f) {
    switch (f) {
      case CubeFace.front: return v.Vector3(0, 0, 1);
      case CubeFace.back: return v.Vector3(0, 0, -1);
      case CubeFace.left: return v.Vector3(-1, 0, 0);
      case CubeFace.right: return v.Vector3(1, 0, 0);
      case CubeFace.top: return v.Vector3(0, -1, 0);
      case CubeFace.bottom: return v.Vector3(0, 1, 0);
    }
  }

  void resetCube() {
    if (isRotating || isSequencePlaying) return;
    cubies.clear();
    _initCube();
    globalRotation = v.Matrix4.identity()..rotateX(-0.6)..rotateY(0.6);
    moveHistory.clear();
    startTime = null;
    endTime = null;
    _wasSolved = true;
    notifyListeners();
  }
}

// --- REFINED 3D ENGINE ---

class CubeGameScreen extends StatefulWidget {
  const CubeGameScreen({super.key});

  @override
  State<CubeGameScreen> createState() => _CubeGameScreenState();
}

class _CubeGameScreenState extends State<CubeGameScreen> with SingleTickerProviderStateMixin {
  final CubeController controller = CubeController();
  late AnimationController animCtrl;
  late Animation<double> anim;

  List<_FaceData> _currentFaces = [];
  Offset? _swipeStart;
  _FaceData? _hitFace;
  Timer? _uiTimer;

  @override
  void initState() {
    super.initState();
    animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    anim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: animCtrl, curve: Curves.easeInOut));
    anim.addListener(() {
      controller.updateAnimatedSlice(anim.value);
    });
    anim.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.commitAnimatedSlice();
        animCtrl.reset();
      }
    });

    controller.onSolved = () {
      if (mounted) _showWinModal();
    };

    _uiTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && controller.startTime != null && controller.endTime == null) {
        setState(() {}); // Repaint the bottom timer smoothly
      }
    });
  }

  void _showWinModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B3A),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.5), width: 2),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ),
                const Icon(Icons.emoji_events, color: Colors.amber, size: 60),
                const SizedBox(height: 16),
                const Text(
                  "CONGRATULATIONS!",
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "You solved the Rubix Cube\nTime: ${_formatElapsed()}",
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _runShuffle();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  ),
                  child: const Text("PLAY AGAIN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  @override
  void dispose() {
    animCtrl.dispose();
    _uiTimer?.cancel();
    super.dispose();
  }

  Future<void> _playSequence(List<MoveRecord> moves, bool isReverse) async {
    controller.isAutoPlayback = isReverse; // Don't record backward moves!
    controller.isSequencePlaying = true;
    animCtrl.duration = const Duration(milliseconds: 160); // Faster for auto solve/shuffle
    
    for (var m in moves) {
      if (!mounted) break;
      double angle = isReverse ? -m.angle : m.angle;
      bool Function(Cubie) filter;
      if (m.axis.x != 0) filter = (c) => c.position.x == m.pos;
      else if (m.axis.y != 0) filter = (c) => c.position.y == m.pos;
      else filter = (c) => c.position.z == m.pos;

      controller.beginAnimatedSlice(m.axis, angle, filter, m.pos);
      await animCtrl.forward(from: 0.0);
      
      // Safety pause just to ensure the StatusListener has cleared `isRotating` flag before next move
      while (controller.isRotating && mounted) {
        await Future.delayed(const Duration(milliseconds: 5));
      }
    }
    
    animCtrl.duration = const Duration(milliseconds: 300); // restore normal swiping speed
    controller.isAutoPlayback = false;
    controller.isSequencePlaying = false;
  }

  Future<void> _runShuffle() async {
    if (controller.isRotating || controller.isSequencePlaying) return;
    
    var random = math.Random();
    List<v.Vector3> axes = [v.Vector3(1, 0, 0), v.Vector3(0, 1, 0), v.Vector3(0, 0, 1)];
    List<double> angles = [math.pi / 2, -math.pi / 2];
    List<double> positions = [-1.0, 0.0, 1.0];

    List<MoveRecord> moves = [];
    for (int i = 0; i < 20; i++) {
      moves.add(MoveRecord(
        axes[random.nextInt(axes.length)],
        angles[random.nextInt(angles.length)],
        positions[random.nextInt(positions.length)]
      ));
    }
    
    controller.startTime = null;
    controller.endTime = null;
    setState((){});
    
    await _playSequence(moves, false); // Animate the shuffle dynamically!
    
    controller.startTime = DateTime.now(); // Start the timer!
    setState((){});
  }

  Future<void> _runAutoSolve() async {
    if (controller.isRotating || controller.moveHistory.isEmpty || controller.isSequencePlaying) return;
    
    // Animate backward moves to solve it magically!
    List<MoveRecord> reversed = controller.moveHistory.reversed.toList();
    
    await _playSequence(reversed, true);
    
    controller.moveHistory.clear();
    controller.endTime = DateTime.now(); // Stop the timer and log end time
    if (mounted) setState((){});
  }

  // Exact 2D Screen to 3D Projected Math Bounding Box calculation
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    bool isInside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      if ((polygon[i].dy > point.dy) != (polygon[j].dy > point.dy) &&
          point.dx < (polygon[j].dx - polygon[i].dx) * (point.dy - polygon[i].dy) / (polygon[j].dy - polygon[i].dy) + polygon[i].dx) {
        isInside = !isInside;
      }
    }
    return isInside;
  }

  void _onPanStart(DragStartDetails details, BoxConstraints constraints) {
    if (controller.isRotating || controller.isSequencePlaying) return;

    double cx = constraints.maxWidth / 2;
    double cy = constraints.maxHeight / 2;
    // Scale down from UI size to the 3D Math matrix size
    double vx = (details.localPosition.dx - cx) / 1.1;
    double vy = (details.localPosition.dy - cy) / 1.1;
    Offset touchPoint = Offset(vx, vy);

    _hitFace = null;
    double size = 56.0;

    // Iterate backwards. Painter's algorithm puts the closest face at the END of the list.
    for (int i = _currentFaces.length - 1; i >= 0; i--) {
      var fd = _currentFaces[i];
      // Generate the unrotated bounding corners locally
      v.Vector3 p1 = fd.transform.perspectiveTransform(v.Vector3(-size/2, -size/2, 0));
      v.Vector3 p2 = fd.transform.perspectiveTransform(v.Vector3(size/2, -size/2, 0));
      v.Vector3 p3 = fd.transform.perspectiveTransform(v.Vector3(size/2, size/2, 0));
      v.Vector3 p4 = fd.transform.perspectiveTransform(v.Vector3(-size/2, size/2, 0));
      
      List<Offset> poly = [
        Offset(p1.x, p1.y),
        Offset(p2.x, p2.y),
        Offset(p3.x, p3.y),
        Offset(p4.x, p4.y),
      ];

      // PERFECT pixel-to-pixel intersection using absolute math
      if (_isPointInPolygon(touchPoint, poly)) {
        _hitFace = fd;
        break;
      }
    }
    _swipeStart = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_swipeStart == null || controller.isRotating || controller.isSequencePlaying) return;

    if (_hitFace == null) {
      // User tapped in empty space! Rotate Global Camera only!
      controller.updateGlobalRotation(
        details.delta.dx * 0.01,
        -details.delta.dy * 0.01,
      );
    } else {
      // User tapped strictly on a visible CUBE FACE! Check for slice swipe
      Offset swipeDelta = details.localPosition - _swipeStart!;
      if (swipeDelta.distance > 20) {
        _handleFaceSwipe(_hitFace!, swipeDelta);
        // Reset immediately to block further commands during animation
        _swipeStart = null;
        _hitFace = null;
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _swipeStart = null;
    _hitFace = null;
  }

  void _handleFaceSwipe(_FaceData hitFace, Offset swipe) {
    Cubie cubie = hitFace.cubie;
    
    // THE 100% ACCURACY FIX: 
    // We must calculate the CURRENT physical world normal of the touched face.
    // The hitFace.normal was its original logical direction, which changes when the piece rotates!
    v.Vector3 worldNormal = cubie.rotationMatrix.transform3(hitFace.normal.clone());
    worldNormal = v.Vector3(
      worldNormal.x.roundToDouble(),
      worldNormal.y.roundToDouble(),
      worldNormal.z.roundToDouble(),
    );

    v.Vector3 u, vAxis;
    if (worldNormal.x.abs() > 0.5) {
      u = v.Vector3(0, 1, 0); 
      vAxis = v.Vector3(0, 0, 1); 
    } else if (worldNormal.y.abs() > 0.5) { 
      u = v.Vector3(0, 0, 1); 
      vAxis = v.Vector3(1, 0, 0); 
    } else {             
      u = v.Vector3(1, 0, 0); 
      vAxis = v.Vector3(0, 1, 0); 
    }

    Offset projU = _toScreen(u);
    Offset projV = _toScreen(vAxis);

    double dotU = swipe.dx * projU.dx + swipe.dy * projU.dy;
    double dotV = swipe.dx * projV.dx + swipe.dy * projV.dy;

    v.Vector3 rotateAxis;
    bool Function(Cubie) filter;
    double angle;
    double targetPos = 0;

    double faceSign = (worldNormal.x + worldNormal.y + worldNormal.z).sign;

    if (dotU.abs() > dotV.abs()) {
      rotateAxis = vAxis;
      if (vAxis.x != 0) { filter = (c) => c.position.x == cubie.position.x; targetPos = cubie.position.x; }
      else if (vAxis.y != 0) { filter = (c) => c.position.y == cubie.position.y; targetPos = cubie.position.y; }
      else { filter = (c) => c.position.z == cubie.position.z; targetPos = cubie.position.z; }
      angle = (math.pi / 2) * dotU.sign * faceSign;
    } else {
      rotateAxis = u;
      if (u.x != 0) { filter = (c) => c.position.x == cubie.position.x; targetPos = cubie.position.x; }
      else if (u.y != 0) { filter = (c) => c.position.y == cubie.position.y; targetPos = cubie.position.y; }
      else { filter = (c) => c.position.z == cubie.position.z; targetPos = cubie.position.z; }
      angle = -(math.pi / 2) * dotV.sign * faceSign;
    }

    controller.beginAnimatedSlice(rotateAxis, angle, filter, targetPos);
    animCtrl.forward(from: 0.0);
  }

  Offset _toScreen(v.Vector3 vec) {
    v.Vector3 proj = controller.globalRotation.transform3(vec.clone());
    return Offset(proj.x, proj.y);
  }

  String _formatElapsed() {
    if (controller.startTime == null) return "00:00.0";
    final end = controller.endTime ?? DateTime.now();
    final diff = end.difference(controller.startTime!);
    final m = diff.inMinutes.toString().padLeft(2, '0');
    final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (diff.inMilliseconds % 1000 ~/ 100).toString(); // Tenths of a second
    return "$m:$s.$ms";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF1B1B3A), Color(0xFF050510)],
            center: Alignment.center,
            radius: 1.2,
          ),
        ),
        // LayoutBuilder provides raw screen size constraints for accurate Math calculations
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ONLY ONE GESTURE DETECTOR CONTROLLING EVERYTHING IN THE APP
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) => _onPanStart(details, constraints),
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: Stack(
                children: [
                  Positioned(
                    top: 50,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        Text("RUBIX CUBE",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white.withOpacity(0.9),
                              letterSpacing: 6,
                            )),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _actionBtn("Shuffle", _runShuffle),
                            const SizedBox(width: 8),
                            _actionBtn("Auto Solve", _runAutoSolve),
                            const SizedBox(width: 8),
                            _actionBtn("Reset", () { controller.resetCube(); setState((){}); }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatElapsed(),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: IgnorePointer( // The entire 3D cube ignores standard widget touches!
                      child: AnimatedBuilder(
                        animation: controller,
                        builder: (context, child) {
                          // Generates the geometry for the Master Raycast Touch System
                          final allFaces = _getSortedFaces();
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()..scale(1.1),
                            child: Stack(
                              alignment: Alignment.center,
                              clipBehavior: Clip.none,
                              children: allFaces,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        ),
      ),
    );
  }

  List<Widget> _getSortedFaces() {
    List<_FaceData> faceDataList = [];
    double size = 56.0;
    double spacing = 1.0; 

    for (var cubie in controller.cubies) {
      final faces = [
        _FaceInfo(CubeFace.front, v.Vector3(0, 0, 1)),
        _FaceInfo(CubeFace.back, v.Vector3(0, 0, -1)),
        _FaceInfo(CubeFace.left, v.Vector3(-1, 0, 0)),
        _FaceInfo(CubeFace.right, v.Vector3(1, 0, 0)),
        _FaceInfo(CubeFace.top, v.Vector3(0, -1, 0)),
        _FaceInfo(CubeFace.bottom, v.Vector3(0, 1, 0)),
      ];

      for (var f in faces) {
        Color color = cubie.faceColors[f.type]!;
        if (color == Colors.black) continue;

        v.Matrix4 modelMatrix = v.Matrix4.identity();
        v.Matrix4 renderMatrix = v.Matrix4.identity();

        if (controller.animatedSlice != null && controller.animatedSlice!.filter(cubie)) {
           v.Matrix4 animRot = v.Matrix4.identity()..rotate(controller.animatedSlice!.axis, controller.animatedSlice!.currentAngle);
           renderMatrix.multiply(animRot);
           modelMatrix.multiply(animRot);
        }

        modelMatrix.multiply(cubie.rotationMatrix);
        v.Matrix4 viewMatrix = controller.globalRotation * modelMatrix;

        v.Vector3 normalViewSpace = viewMatrix.rotate3(f.normal.clone());
        if (normalViewSpace.z < -0.0001) continue; 

        v.Vector3 worldPos = cubie.position * (size * spacing);
        renderMatrix.translate(worldPos.x, worldPos.y, worldPos.z);
        renderMatrix.multiply(cubie.rotationMatrix);
        renderMatrix.translate(f.normal.x * size / 2, f.normal.y * size / 2, f.normal.z * size / 2);
        
        if (f.normal.x != 0) renderMatrix.rotateY(math.pi / 2 * f.normal.x);
        if (f.normal.y != 0) renderMatrix.rotateX(-math.pi / 2 * f.normal.y);

        v.Matrix4 finalMatrix = controller.globalRotation * renderMatrix;
        double zDepth = finalMatrix.getTranslation().z;

        faceDataList.add(_FaceData(
          zDepth: zDepth,
          transform: finalMatrix,
          color: color,
          cubie: cubie,
          normal: f.normal,
        ));
      }
    }

    faceDataList.sort((a, b) => a.zDepth.compareTo(b.zDepth));
    _currentFaces = faceDataList; // Cache the 3D data for the Raycaster!

    return faceDataList.map((fd) => _RenderFace(fd: fd, size: size)).toList();
  }

  Widget _actionBtn(String label, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white10,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 0,
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _FaceInfo {
  final CubeFace type;
  final v.Vector3 normal;
  _FaceInfo(this.type, this.normal);
}

class _FaceData {
  final double zDepth;
  final v.Matrix4 transform;
  final Color color;
  final Cubie cubie;
  final v.Vector3 normal;
  _FaceData({required this.zDepth, required this.transform, required this.color, required this.cubie, required this.normal});
}

class _RenderFace extends StatelessWidget {
  final _FaceData fd;
  final double size;

  const _RenderFace({required this.fd, required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: fd.transform,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.black, 
        ),
        child: Container(
          margin: const EdgeInsets.all(3.5), 
          decoration: BoxDecoration(
            color: fd.color, 
            borderRadius: BorderRadius.circular(4), 
          ),
        ),
      ),
    );
  }
}
