import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Magic Coloring's line art (SPEC FR-TOY-02, Appendix B), drawn in code so
/// the app ships no image files and every outline stays crisp at any size.
/// A picture lives in a 1000 × 750 box. [regions] are the parts she colors,
/// bottom to top (a later part covers an earlier one); [lines] are outlines
/// only (whiskers, strings); [fixed] are painted parts that never change
/// (eyes).
class ColoringPicture {
  ColoringPicture(this.id, this.emoji, this.regions, {this.lines = const [], this.fixed = const []});
  final String id;

  /// For the celebration when it's done.
  final String emoji;
  final List<Path> regions;
  final List<Path> lines;
  final List<(Path, Color)> fixed;
}

const Size kPictureSize = Size(1000, 750);
const Color _ink = Color(0xFF2B2B38);

/// Every picture, by how many parts it has (4 big ones → 26 small ones).
final List<ColoringPicture Function()> kColoringPictures = [
  _sunny, _apple, _fish, _balloon, //
  _house, _butterfly, _iceCream, _snail,
  _car, _flowerPot, _rocket, _rainbow,
  _turtle, _train,
  _castle, _sea,
];

// ─────────────────────────────── Drawing kit ───────────────────────────────

Path _rect(double l, double t, double r, double b, [double radius = 0]) => Path()..addRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(radius)));
Path _circle(double x, double y, double r) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r));
Path _oval(double x, double y, double rx, double ry) => Path()..addOval(Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2));
Path _line(double x1, double y1, double x2, double y2) => Path()
  ..moveTo(x1, y1)
  ..lineTo(x2, y2);

Path _poly(List<double> xy) {
  final p = Path()..moveTo(xy[0], xy[1]);
  for (var i = 2; i < xy.length; i += 2) {
    p.lineTo(xy[i], xy[i + 1]);
  }
  return p..close();
}

/// A smooth closed shape through the points (a Catmull-Rom loop).
Path _blob(List<double> xy) {
  final pts = [for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1])];
  final n = pts.length;
  final p = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < n; i++) {
    final p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return p..close();
}

/// A smooth open line through the points.
Path _curve(List<double> xy) {
  final pts = [for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1])];
  final p = Path()..moveTo(pts[0].dx, pts[0].dy);
  for (var i = 0; i < pts.length - 1; i++) {
    final p0 = pts[math.max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[math.min(pts.length - 1, i + 2)];
    final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
    p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  return p;
}

Path _union(List<Path> parts) => parts.reduce((a, b) => Path.combine(PathOperation.union, a, b));

/// A fluffy cloud: three puffs on a flat bottom, [w] wide.
Path _cloud(double x, double y, double w) {
  final r = w / 6;
  return _union([_circle(x - w * 0.27, y, r * 1.05), _circle(x, y - r * 0.55, r * 1.45), _circle(x + w * 0.27, y, r * 1.05), _rect(x - w / 2, y - r * 0.2, x + w / 2, y + r * 1.05, r)]);
}

/// A star with [n] points.
Path _star(double x, double y, double r, {int n = 5, double inner = 0.45}) => _poly([
      for (var i = 0; i < n * 2; i++) ...[
        x + (i.isEven ? r : r * inner) * math.cos(-math.pi / 2 + i * math.pi / n),
        y + (i.isEven ? r : r * inner) * math.sin(-math.pi / 2 + i * math.pi / n),
      ],
    ]);

/// The top half of a disc: a rainbow band before the smaller ones cover it.
Path _halfDisc(double x, double y, double r) => Path()
  ..moveTo(x - r, y)
  ..arcTo(Rect.fromCircle(center: Offset(x, y), radius: r), math.pi, math.pi, false)
  ..close();

/// An oval petal [dist] from ([x], [y]), turned to [angle].
Path _petal(double x, double y, double dist, double rx, double ry, double angle) {
  final m = Matrix4.identity()
    ..translateByDouble(x, y, 0, 1)
    ..rotateZ(angle)
    ..translateByDouble(-x, -y, 0, 1);
  return _oval(x + dist, y, rx, ry).transform(m.storage);
}

/// A rectangle with rounded top corners (doors, arched windows).
Path _arch(double l, double t, double r, double b) {
  final radius = Radius.circular((r - l) / 2);
  return Path()..addRRect(RRect.fromLTRBAndCorners(l, t, r, b, topLeft: radius, topRight: radius));
}

/// An eye: white, a pupil and a glint.
List<(Path, Color)> _eye(double x, double y, double r) => [
      (_circle(x, y, r), Colors.white),
      (_circle(x + r * 0.15, y + r * 0.05, r * 0.5), _ink),
      (_circle(x, y - r * 0.15, r * 0.17), Colors.white),
    ];

// ───────────────────────── Level 1: 4–5 big parts ──────────────────────────

ColoringPicture _sunny() => ColoringPicture('sunny', '☀️', [
      _rect(0, 0, 1000, 750),
      Path()
        ..moveTo(0, 540)
        ..cubicTo(250, 420, 520, 430, 700, 500)
        ..cubicTo(820, 545, 920, 540, 1000, 505)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _circle(770, 200, 115),
      _cloud(330, 250, 300),
    ], lines: [
      for (var i = 0; i < 8; i++)
        _line(770 + 150 * math.cos(i * math.pi / 4), 200 + 150 * math.sin(i * math.pi / 4), 770 + 200 * math.cos(i * math.pi / 4), 200 + 200 * math.sin(i * math.pi / 4)),
    ]);

ColoringPicture _apple() => ColoringPicture('apple', '🍎', [
      _rect(0, 0, 1000, 750),
      _rect(488, 150, 516, 290, 12),
      _blob([500, 270, 570, 240, 660, 250, 735, 310, 770, 410, 755, 520, 700, 610, 620, 665, 545, 660, 500, 645, 455, 660, 380, 665, 300, 610, 245, 520, 230, 410, 265, 310, 340, 250, 430, 240]),
      _blob([515, 215, 560, 150, 640, 120, 700, 130, 660, 195, 580, 228]),
    ], lines: [
      _curve([330, 350, 305, 430, 325, 510]),
    ]);

ColoringPicture _fish() => ColoringPicture('fish', '🐟', [
      _rect(0, 0, 1000, 750),
      Path()
        ..moveTo(0, 640)
        ..cubicTo(250, 600, 450, 680, 700, 630)
        ..cubicTo(820, 605, 920, 620, 1000, 640)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _poly([690, 375, 890, 245, 850, 375, 890, 505]),
      _blob([370, 260, 440, 165, 560, 160, 610, 250]),
      _oval(470, 375, 270, 165),
    ], lines: [
      _curve([235, 400, 262, 418, 290, 405]),
      _curve([440, 290, 470, 375, 440, 460]),
    ], fixed: _eye(360, 335, 38));

ColoringPicture _balloon() => ColoringPicture('balloon', '🎈', [
      _rect(0, 0, 1000, 750),
      _cloud(230, 190, 260),
      _cloud(790, 570, 240),
      _blob([520, 110, 610, 130, 680, 200, 700, 300, 670, 400, 600, 470, 545, 510, 520, 518, 495, 510, 440, 470, 370, 400, 340, 300, 360, 200, 430, 130]),
    ], lines: [
      _curve([520, 518, 545, 580, 500, 645, 530, 735]),
      _curve([420, 230, 410, 290, 430, 350]),
    ]);

// ───────────────────────── Level 2: 6–9 parts ──────────────────────────────

ColoringPicture _house() => ColoringPicture('house', '🏠', [
      _rect(0, 0, 1000, 750),
      _circle(870, 120, 75),
      Path()
        ..moveTo(0, 600)
        ..cubicTo(300, 570, 700, 630, 1000, 590)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _rect(610, 150, 680, 330, 6),
      _rect(270, 320, 730, 630),
      _poly([215, 335, 500, 125, 785, 335]),
      _arch(450, 450, 550, 630),
      _rect(310, 400, 410, 490, 6),
      _rect(590, 400, 690, 490, 6),
    ], lines: [
      _line(360, 400, 360, 490),
      _line(310, 445, 410, 445),
      _line(640, 400, 640, 490),
      _line(590, 445, 690, 445),
    ], fixed: [
      (_circle(530, 545, 9), _ink),
    ]);

ColoringPicture _butterfly() => ColoringPicture('butterfly', '🦋', [
      _rect(0, 0, 1000, 750),
      _blob([480, 330, 400, 170, 280, 115, 185, 170, 195, 285, 300, 355]),
      _blob([520, 330, 600, 170, 720, 115, 815, 170, 805, 285, 700, 355]),
      _blob([480, 385, 330, 390, 235, 470, 255, 575, 350, 600, 450, 505]),
      _blob([520, 385, 670, 390, 765, 470, 745, 575, 650, 600, 550, 505]),
      _circle(300, 240, 45),
      _circle(700, 240, 45),
      _oval(500, 385, 34, 195),
    ], lines: [
      _curve([488, 205, 462, 135, 420, 100]),
      _curve([512, 205, 538, 135, 580, 100]),
    ], fixed: [
      (_circle(420, 100, 13), _ink),
      (_circle(580, 100, 13), _ink),
    ]);

ColoringPicture _iceCream() => ColoringPicture('icecream', '🍦', [
      _rect(0, 0, 1000, 750),
      _poly([385, 400, 615, 400, 500, 705]),
      _blob([370, 400, 380, 330, 430, 290, 500, 280, 570, 290, 620, 330, 630, 400, 600, 422, 570, 402, 540, 428, 500, 406, 460, 428, 430, 402, 400, 422]),
      _blob([390, 290, 400, 220, 450, 180, 500, 172, 550, 180, 600, 220, 610, 290, 560, 302, 500, 296, 440, 302]),
      _blob([435, 182, 445, 130, 475, 104, 500, 98, 525, 104, 555, 130, 565, 182, 500, 192]),
      _circle(500, 84, 30),
    ], lines: [
      _curve([500, 56, 512, 30, 538, 14]),
      // The waffle, inside the cone and under the scoops.
      _line(425, 480, 575, 480),
      _line(445, 540, 555, 540),
      _line(448, 432, 520, 600),
      _line(552, 432, 480, 600),
    ]);

ColoringPicture _snail() => ColoringPicture('snail', '🐌', [
      _rect(0, 0, 1000, 750),
      _circle(130, 130, 70),
      Path()
        ..moveTo(0, 560)
        ..cubicTo(300, 530, 700, 590, 1000, 550)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _blob([240, 600, 300, 545, 600, 545, 700, 505, 765, 420, 810, 380, 860, 405, 870, 475, 825, 565, 760, 605, 600, 620, 300, 622]),
      _circle(500, 420, 150),
      _circle(515, 415, 72),
    ], lines: [
      _curve([515, 415, 540, 402, 546, 432, 516, 452, 480, 428, 490, 386, 542, 372, 578, 412]),
      _line(800, 395, 785, 300),
      _line(845, 400, 875, 312),
      _curve([830, 455, 848, 470, 866, 455]),
    ], fixed: [
      (_circle(785, 296, 14), _ink),
      (_circle(876, 307, 14), _ink),
    ]);

// ───────────────────────── Level 3: 10–15 parts ────────────────────────────

ColoringPicture _car() => ColoringPicture('car', '🚗', [
      _rect(0, 0, 1000, 750),
      _circle(860, 115, 68),
      _cloud(250, 150, 210),
      _rect(0, 500, 1000, 585),
      _rect(0, 585, 1000, 750),
      _poly([300, 386, 375, 250, 620, 250, 705, 386]),
      _poly([348, 380, 398, 280, 490, 280, 490, 380]),
      _poly([510, 380, 510, 280, 600, 280, 652, 380]),
      _rect(180, 380, 820, 560, 40),
      _circle(330, 560, 80),
      _circle(670, 560, 80),
      _circle(330, 560, 32),
      _circle(670, 560, 32),
      _rect(765, 420, 812, 458, 12),
    ], fixed: [
      for (var x = 40.0; x < 1000; x += 200) (_rect(x, 660, x + 110, 676, 8), Colors.white),
    ]);

ColoringPicture _flowerPot() => ColoringPicture('flowerpot', '🌼', [
      _rect(0, 0, 1000, 750),
      _rect(0, 620, 1000, 750),
      _rect(486, 235, 514, 470, 14),
      _blob([495, 385, 430, 330, 360, 330, 395, 385, 450, 400]),
      _blob([505, 335, 570, 280, 640, 280, 605, 335, 550, 350]),
      _poly([380, 480, 620, 480, 590, 685, 410, 685]),
      _rect(360, 450, 640, 505, 12),
      for (var i = 0; i < 6; i++) _petal(500, 200, 82, 54, 36, i * math.pi / 3),
      _circle(500, 200, 50),
    ]);

ColoringPicture _rocket() => ColoringPicture('rocket', '🚀', [
      _rect(0, 0, 1000, 750),
      _circle(170, 160, 80),
      _star(820, 130, 40),
      _star(880, 520, 34),
      _star(130, 560, 36),
      _blob([440, 560, 560, 560, 545, 650, 500, 725, 455, 650]),
      _blob([468, 560, 532, 560, 525, 620, 500, 672, 475, 620]),
      _poly([425, 420, 330, 560, 330, 610, 425, 545]),
      _poly([575, 420, 670, 560, 670, 610, 575, 545]),
      _rect(420, 200, 580, 572, 30),
      Path()
        ..moveTo(420, 215)
        ..quadraticBezierTo(428, 110, 500, 58)
        ..quadraticBezierTo(572, 110, 580, 215)
        ..close(),
      _circle(500, 330, 62),
      _circle(500, 330, 42),
    ], lines: [
      _circle(145, 140, 16),
      _circle(195, 185, 12),
      _circle(150, 195, 9),
    ]);

ColoringPicture _rainbow() => ColoringPicture('rainbow', '🌈', [
      _rect(0, 0, 1000, 750),
      _circle(870, 110, 60),
      for (final r in const <double>[420, 380, 340, 300, 260, 220, 180]) _halfDisc(500, 610, r),
      _cloud(110, 590, 230),
      _cloud(890, 590, 230),
      Path()
        ..moveTo(0, 640)
        ..cubicTo(300, 580, 600, 660, 1000, 610)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      Path()
        ..moveTo(0, 700)
        ..cubicTo(350, 660, 700, 720, 1000, 690)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
    ]);

// ───────────────────────── Level 4: 16–23 parts ────────────────────────────

ColoringPicture _turtle() => ColoringPicture('turtle', '🐢', [
      _rect(0, 0, 1000, 750),
      _circle(880, 110, 65),
      _cloud(200, 120, 220),
      _cloud(560, 95, 180),
      Path()
        ..moveTo(0, 350)
        ..cubicTo(250, 320, 500, 380, 1000, 340)
        ..lineTo(1000, 520)
        ..cubicTo(700, 540, 300, 500, 0, 530)
        ..close(),
      Path()
        ..moveTo(0, 530)
        ..cubicTo(300, 500, 700, 540, 1000, 520)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _blob([330, 585, 240, 610, 330, 640]),
      // Legs out at the corners, under the shell.
      _oval(345, 482, 56, 42),
      _oval(655, 482, 56, 42),
      _oval(345, 688, 56, 42),
      _oval(655, 688, 56, 42),
      _circle(750, 560, 62),
      _oval(500, 585, 195, 122),
      _oval(500, 505, 75, 30),
      _oval(500, 668, 75, 28),
      _oval(385, 588, 50, 58),
      _oval(615, 588, 50, 58),
      _poly([500, 530, 548, 557, 548, 613, 500, 640, 452, 613, 452, 557]),
    ], lines: [
      _curve([760, 590, 780, 600, 798, 588]),
    ], fixed: [
      (_circle(772, 545, 11), _ink),
    ]);

ColoringPicture _train() => ColoringPicture('train', '🚂', [
      _rect(0, 0, 1000, 750),
      _circle(120, 110, 60),
      _cloud(720, 115, 220),
      Path()
        ..moveTo(0, 470)
        ..cubicTo(250, 330, 500, 360, 650, 440)
        ..cubicTo(780, 400, 900, 380, 1000, 420)
        ..lineTo(1000, 600)
        ..lineTo(0, 600)
        ..close(),
      _rect(0, 600, 1000, 750),
      _circle(300, 150, 40),
      _circle(352, 98, 50),
      _circle(425, 58, 56),
      _poly([275, 302, 325, 302, 342, 198, 258, 198]),
      _rect(230, 300, 520, 522, 30),
      _rect(500, 220, 700, 522, 20),
      _rect(545, 262, 655, 352, 14),
      _poly([234, 478, 178, 586, 252, 586, 252, 478]),
      _circle(300, 560, 55),
      _circle(430, 560, 55),
      _circle(620, 550, 72),
      _rect(730, 330, 960, 522, 16),
      _rect(770, 250, 920, 336, 12),
      _circle(785, 562, 48),
      _circle(905, 562, 48),
    ], lines: [
      _line(0, 668, 1000, 668),
      for (var x = 30.0; x < 1000; x += 90) _line(x, 668, x - 18, 700),
      _line(700, 498, 730, 498),
    ]);

// ───────────────────────── Level 5: 24–34 parts ────────────────────────────

ColoringPicture _castle() => ColoringPicture('castle', '🏰', [
      _rect(0, 0, 1000, 750),
      _circle(930, 62, 46),
      _cloud(95, 72, 150),
      _cloud(650, 112, 150),
      Path()
        ..moveTo(0, 560)
        ..cubicTo(300, 500, 700, 520, 1000, 560)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _poly([448, 750, 552, 750, 532, 620, 468, 620]),
      _rect(120, 250, 270, 620),
      _rect(730, 250, 880, 620),
      _rect(420, 185, 580, 620),
      _poly([100, 258, 195, 152, 290, 258]),
      _poly([710, 258, 805, 152, 900, 258]),
      _poly([400, 192, 500, 82, 600, 192]),
      _poly([195, 86, 258, 106, 195, 126]),
      _poly([805, 86, 868, 106, 805, 126]),
      _poly([500, 22, 563, 42, 500, 62]),
      _rect(260, 380, 740, 620),
      _rect(280, 342, 330, 382),
      _rect(360, 342, 410, 382),
      _rect(590, 342, 640, 382),
      _rect(670, 342, 720, 382),
      _arch(440, 480, 560, 620),
      _arch(170, 320, 220, 392),
      _arch(780, 320, 830, 392),
      _arch(470, 250, 530, 322),
      _arch(305, 430, 360, 485),
      _arch(640, 430, 695, 485),
    ], lines: [
      _line(195, 86, 195, 154),
      _line(805, 86, 805, 154),
      _line(500, 22, 500, 84),
      _line(500, 480, 500, 620),
    ]);

ColoringPicture _sea() => ColoringPicture('sea', '🐠', [
      _rect(0, 0, 1000, 750),
      Path()
        ..moveTo(0, 620)
        ..cubicTo(250, 580, 600, 660, 1000, 600)
        ..lineTo(1000, 750)
        ..lineTo(0, 750)
        ..close(),
      _blob([60, 645, 90, 560, 170, 540, 232, 582, 240, 650]),
      _blob([820, 625, 850, 562, 930, 548, 985, 592, 990, 652, 830, 662]),
      _blob([150, 620, 128, 520, 160, 430, 140, 340, 176, 328, 192, 430, 166, 520, 186, 620]),
      _blob([880, 610, 860, 500, 890, 420, 870, 330, 906, 322, 922, 420, 896, 500, 916, 610]),
      _blob([620, 645, 604, 560, 630, 480, 656, 480, 642, 560, 652, 645]),
      _blob([268, 196, 300, 158, 342, 168, 346, 200]),
      _poly([215, 250, 148, 195, 164, 250, 148, 305]),
      _oval(300, 250, 95, 60),
      _poly([775, 180, 842, 132, 826, 180, 842, 228]),
      _oval(700, 180, 80, 50),
      _poly([455, 112, 412, 84, 420, 112, 412, 140]),
      _oval(500, 112, 50, 32),
      _star(480, 650, 60, inner: 0.42),
      _star(905, 700, 34, inner: 0.42),
      _blob([250, 692, 262, 640, 300, 615, 340, 640, 352, 692]),
      _circle(612, 560, 32),
      _circle(788, 560, 32),
      _oval(700, 622, 72, 46),
      _circle(520, 330, 20),
      _circle(546, 278, 26),
      _circle(514, 222, 17),
      _circle(560, 178, 22),
      Path()
        ..moveTo(372, 430)
        ..cubicTo(372, 330, 528, 330, 528, 430)
        ..close(),
    ], lines: [
      for (final x in const <double>[390, 430, 470, 510]) _curve([x, 432, x - 12, 470, x + 6, 505, x - 6, 540]),
      _line(640, 600, 610, 590),
      _line(760, 600, 790, 590),
      _line(670, 662, 655, 690),
      _line(730, 662, 745, 690),
    ], fixed: [
      ..._eye(355, 238, 14),
      ..._eye(660, 170, 12),
      ..._eye(526, 106, 8),
      ..._eye(682, 606, 10),
      ..._eye(718, 606, 10),
    ]);
