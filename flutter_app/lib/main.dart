// SHEGUARD: app-style front end (v4).
//
// Backend contract:
//   POST  {apiBaseUrl}/chat   (conversation lives in app memory only)
//   body:     {category, immediate_danger, messages:[{role, content}]}
//   response: {reply, urgency, demo_notice}
//   (POST /assess is still available on the backend)
//
// Run on the Android emulator:
//   flutter run --dart-define=SHEGUARD_API_URL=http://10.0.2.2:8000
// Build the APK (use your public https backend URL):
//   flutter build apk --release --dart-define=SHEGUARD_API_URL=https://YOUR-BACKEND-URL
//
// Android release builds need the INTERNET permission in
// android/app/src/main/AndroidManifest.xml (above <application>):
//   <uses-permission android:name="android.permission.INTERNET"/>
//
// Only dependency beyond Flutter: the `http` package (already in your pubspec).

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = String.fromEnvironment(
  'SHEGUARD_API_URL',
  defaultValue: 'https://sheguard-ice5.onrender.com',
);

// ---------------------------------------------------------------------------
// Palette: Deep Navy, Brick Red, Orange, Golden Yellow, Warm Cream.
// A few tints are derived from them for surfaces and borders.
// Rule of thumb: navy = trust/structure, gold = action/highlight,
// orange = warmth, brick = urgency only.
// ---------------------------------------------------------------------------
class P {
  // Core palette
  static const navy = Color(0xFF123047);
  static const brick = Color(0xFFC63832);
  static const orange = Color(0xFFF0802E);
  static const gold = Color(0xFFF6BE58);
  static const cream = Color(0xFFE9E1BD);

  // Derived
  static const bg = Color(0xFFF6F2E0);
  static const card = Color(0xFFFFFCF2);
  static const navyMid = Color(0xFF1E4663);
  static const soft = Color(0xFF51656F);
  static const line = Color(0xFFDDD5AE);
  static const goldPale = Color(0xFFFBE9BE);
  static const brickPale = Color(0xFFF8DFD9);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: P.navy,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const SheGuardApp());
}

class SheGuardApp extends StatelessWidget {
  const SheGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: c, width: w),
        );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SHEGUARD',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: P.navy,
          primary: P.navy,
          secondary: P.orange,
          surface: P.bg,
        ),
        scaffoldBackgroundColor: P.bg,
        splashFactory: InkRipple.splashFactory,
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: P.navy,
            foregroundColor: P.cream,
            disabledBackgroundColor: P.line,
            minimumSize: const Size.fromHeight(56),
            shape: shape,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: P.navy,
            minimumSize: const Size.fromHeight(56),
            side: const BorderSide(color: P.navy, width: 1.6),
            shape: shape,
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: P.card,
          hintStyle: const TextStyle(color: P.soft, height: 1.4),
          contentPadding: const EdgeInsets.all(18),
          border: border(P.line, 1.5),
          enabledBorder: border(P.line, 1.5),
          focusedBorder: border(P.navy, 2),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: P.navy,
          contentTextStyle: const TextStyle(color: P.cream, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const OnboardingScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers and small widgets
// ---------------------------------------------------------------------------
Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    );

/// Full screens rise from the bottom like a native sheet.
Route<T> slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );

Future<void> copyText(BuildContext context, String text, String toast) async {
  HapticFeedback.mediumImpact();
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(toast)));
}

/// Press-scale feedback + haptics for every tappable surface.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const Tap({super.key, required this.child, this.onTap});

  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => down = true) : null,
        onTapUp: enabled ? (_) => setState(() => down = false) : null,
        onTapCancel: enabled ? () => setState(() => down = false) : null,
        onTap: enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              }
            : null,
        child: AnimatedScale(
          scale: down ? 0.96 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class Heading extends StatelessWidget {
  final String text;
  final double size;
  final Color color;
  const Heading(this.text, {super.key, this.size = 26, this.color = P.navy});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.15,
          letterSpacing: -0.4,
          color: color,
        ),
      );
}

class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const SectionLabel(this.text,
      {super.key, this.padding = const EdgeInsets.fromLTRB(20, 26, 20, 12)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: P.navy),
        ),
      );
}

/// Title row used at the top of each tab.
class TabHeader extends StatelessWidget {
  final String kicker;
  final String title;
  const TabHeader({super.key, required this.kicker, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    color: P.brick,
                  ),
                ),
                const SizedBox(height: 4),
                Heading(title, size: 28),
              ],
            ),
          ),
        
        ],
      ),
    );
  }
}
         
/// The one memorable element: a softly breathing golden orb.
class CalmOrb extends StatefulWidget {
  final double size;
  final IconData icon;
  const CalmOrb({super.key, this.size = 100, this.icon = Icons.shield_moon_rounded});

  @override
  State<CalmOrb> createState() => _CalmOrbState();
}

class _CalmOrbState extends State<CalmOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final s = widget.size;

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = still ? 0.5 : Curves.easeInOut.transform(_c.value);

          Widget ring(double scale, Color color, double alpha) => Container(
                width: s * scale,
                height: s * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: alpha),
                ),
              );

          return SizedBox(
            width: s * 1.5,
            height: s * 1.5,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ring(1.1 + 0.35 * t, P.orange, 0.16),
                ring(0.9 + 0.18 * t, P.gold, 0.30),
                Container(
                  width: s * 0.62,
                  height: s * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [P.gold, P.orange],
                    ),
                    boxShadow: [
                      BoxShadow(color: P.orange.withValues(alpha: 0.5), blurRadius: 26),
                    ],
                  ),
                  child: Icon(widget.icon, size: s * 0.3, color: P.navy),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Reveals content with a short fade + rise.
class FadeSlide extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const FadeSlide({super.key, required this.child, this.delayMs = 0});

  @override
  State<FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<FadeSlide> {
  bool shown = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) setState(() => shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: shown ? Offset.zero : const Offset(0, 0.06),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Native-style modal bottom sheet used by the toolkit and helplines.
Future<void> showToolSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Widget child,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: P.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Heading(title, size: 24),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(color: P.soft, height: 1.4, fontSize: 15)),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    ),
  );
}

/// Renders the AI reply: bold section labels and tidy "- " bullets.
class ReplyText extends StatelessWidget {
  final String text;
  final Color color;
  const ReplyText({super.key, required this.text, required this.color});

  static final _label = RegExp(r"^[A-Za-z' ]{3,40}:$");

  @override
  Widget build(BuildContext context) {
    final body = TextStyle(fontSize: 16, height: 1.45, color: color);
    final children = <Widget>[];

    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        children.add(const SizedBox(height: 6));
      } else if (_label.hasMatch(line)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            line.substring(0, line.length - 1),
            style: body.copyWith(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ));
      } else if (line.startsWith('- ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body),
              Expanded(child: Text(line.substring(2), style: body)),
            ],
          ),
        ));
      } else {
        children.add(Text(line, style: body));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

// ---------------------------------------------------------------------------
// Quick exit + decoy screen
// ---------------------------------------------------------------------------
class QuickExitButton extends StatelessWidget {
  const QuickExitButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: () {
        HapticFeedback.heavyImpact();
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          fadeRoute(const DecoyScreen()),
          (_) => false,
        );
      },
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: P.brick, borderRadius: BorderRadius.circular(20)),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.close_rounded, size: 18, color: Colors.white),
            SizedBox(width: 4),
            Text(
              'Quick exit',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// A harmless-looking screen. Long-press the title to come back.
class DecoyScreen extends StatefulWidget {
  const DecoyScreen({super.key});

  @override
  State<DecoyScreen> createState() => _DecoyScreenState();
}

class _DecoyScreenState extends State<DecoyScreen> {
  final done = <int>{};
  final tasks = const [
    'Maths: revise Chapter 5',
    'Science: finish lab file',
    'English: essay first draft',
    'Hindi: learn new vocabulary',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: GestureDetector(
          onLongPress: () => Navigator.of(context).pushAndRemoveUntil(
            fadeRoute(const AppShell()),
            (_) => false,
          ),
          child: const Text('Study planner'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text("Today's tasks", style: TextStyle(fontSize: 14, color: Colors.black54)),
          ),
          for (var i = 0; i < tasks.length; i++)
            CheckboxListTile(
              value: done.contains(i),
              onChanged: (v) => setState(() {
                if (v == true) {
                  done.add(i);
                } else {
                  done.remove(i);
                }
              }),
              title: Text(tasks[i]),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.blueGrey,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helplines (please verify these numbers before the event)
// ---------------------------------------------------------------------------
class Helpline {
  final String name;
  final String number;
  final String note;
  const Helpline(this.name, this.number, this.note);
}

const helplines = [
  Helpline('Childline', '1098', 'Free help for children, any time'),
  Helpline('Emergency / Police', '112', 'If you or someone is in danger now'),
  Helpline('Women Helpline', '181', 'Support for violence or harassment'),
  Helpline('Tele-MANAS', '14416', 'Free mental health support'),
  Helpline('Cyber Crime', '1930', 'Report online fraud or harassment'),
];

class HelplineList extends StatelessWidget {
  final bool emphasize;
  final List<Helpline> lines;
  const HelplineList({super.key, this.emphasize = false, this.lines = helplines});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: P.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: emphasize ? P.brick : P.line,
          width: emphasize ? 2 : 1.5,
        ),
      ),
      child: Column(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: P.line),
            _HelplineRow(line: lines[i], emphasize: emphasize),
          ],
        ],
      ),
    );
  }
}

class _HelplineRow extends StatelessWidget {
  final Helpline line;
  final bool emphasize;
  const _HelplineRow({required this.line, required this.emphasize});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: () => copyText(context, line.number, '${line.name} number copied'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              child: Text(
                line.number,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: emphasize ? P.brick : P.navy,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, color: P.navy)),
                  const SizedBox(height: 2),
                  Text(line.note,
                      style: const TextStyle(fontSize: 12.5, color: P.soft, height: 1.3)),
                ],
              ),
            ),
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: P.goldPale, shape: BoxShape.circle),
              child: const Icon(Icons.copy_rounded, size: 18, color: P.navy),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustedRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _TrustedRow({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: P.cream.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: P.navy, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, color: P.navy)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(fontSize: 14, color: P.soft, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Onboarding (3 swipeable pages, then the app)
// ---------------------------------------------------------------------------
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pager = PageController();
  int page = 0;

  static const pages = [
    (
      Icons.lock_outline_rounded,
      'Private by design',
      'This demo does not save your message. You choose what you share.'
    ),
    (
      Icons.favorite_border_rounded,
      'Support, not judgement',
      'Calm, kind guidance that helps you find your next safe step.'
    ),
    (
      Icons.people_outline_rounded,
      'Always a human next step',
      'We point you to trusted adults and free helplines.'
    ),
  ];

  void enter() => Navigator.of(context).pushReplacement(fadeRoute(const AppShell()));

  @override
  void dispose() {
    pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = page == pages.length - 1;
    return Scaffold(
      backgroundColor: P.navy,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
              child: Row(
                children: [
                  const Text(
                    'SHEGUARD',
                    style: TextStyle(
                      color: P.gold,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  if (!last)
                    TextButton(
                      onPressed: enter,
                      style: TextButton.styleFrom(foregroundColor: P.cream),
                      child: const Text('Skip', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const CalmOrb(size: 120),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                'You deserve to feel safe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: P.cream,
                  fontSize: 32,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pager,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (_, i) {
                  final p = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: P.cream.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Icon(p.$1, color: P.gold, size: 30),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          p.$2,
                          style: const TextStyle(
                            color: P.cream,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          p.$3,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: P.cream.withValues(alpha: 0.85),
                            fontSize: 15.5,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: i == page ? 26 : 8,
                    decoration: BoxDecoration(
                      color: i == page ? P.gold : P.cream.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: P.gold,
                  foregroundColor: P.navy,
                ),
                onPressed: () {
                  if (last) {
                    enter();
                  } else {
                    pager.nextPage(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                    );
                  }
                },
                child: Text(last ? 'Get started' : 'Next'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'AI support, not a replacement for a counsellor.',
                style: TextStyle(fontSize: 12, color: P.cream),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Concerns + draft state shared between Home and Talk
// ---------------------------------------------------------------------------
class Concern {
  final String label; // this exact text is sent to the backend as "category"
  final IconData icon;
  final Color tint;
  const Concern(this.label, this.icon, this.tint);
}

const concerns = [
  Concern('Feeling low or stressed', Icons.sentiment_dissatisfied_outlined, P.cream),
  Concern('Bullying or ragging', Icons.groups_2_outlined, P.goldPale),
  Concern('Online harassment', Icons.phone_iphone_rounded, P.cream),
  Concern('Unwanted behaviour or stalking', Icons.front_hand_outlined, P.brickPale),
  Concern('Discrimination', Icons.balance_rounded, P.goldPale),
  Concern('Family or relationship problem', Icons.favorite_border_rounded, P.cream),
  Concern('Something else', Icons.chat_bubble_outline_rounded, P.goldPale),
];

/// One chat message. Lives in memory only.
class ChatMsg {
  final bool fromUser;
  final String text;
  final bool urgent;
  const ChatMsg(this.fromUser, this.text, {this.urgent = false});
}

/// Shared between Home and Talk. Holds the whole conversation in memory
/// (nothing is saved to disk), so it survives switching tabs.
class Draft extends ChangeNotifier {
  static const maxHistory = 20;

  final controller = TextEditingController();
  final messages = <ChatMsg>[];

  String category = 'Feeling low or stressed';
  bool urgent = false;

  bool loading = false;
  bool slow = false;
  String? error;
  String? errorDetail;
  String? notice;

  int _generation = 0; // bumps on reset so stale replies are ignored
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void setCategory(String v) {
    category = v;
    notifyListeners();
  }

  void setUrgent(bool v) {
    urgent = v;
    notifyListeners();
  }

  void fillDemo() {
    category = 'Bullying or ragging';
    urgent = false;
    controller.text = 'I keep getting mocked by a group in my class and '
        'I feel anxious about going to college.';
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    notifyListeners();
  }

  void addStarter(String s) {
    final t = controller.text;
    controller.text = t.isEmpty ? s : '$t $s';
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
  }

  /// Start a fresh conversation.
  void reset() {
    _generation++;
    messages.clear();
    controller.clear();
    urgent = false;
    loading = false;
    slow = false;
    error = null;
    errorDetail = null;
    notice = null;
    notifyListeners();
  }

  /// Send what is typed in the composer.
  Future<void> send() async {
    if (loading) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    messages.add(ChatMsg(true, text));
    controller.clear();
    await _request();
  }

  /// Re-send the conversation after a failure (does not add a new message).
  Future<void> retry() async {
    if (loading || messages.isEmpty || !messages.last.fromUser) return;
    await _request();
  }

  Future<void> _request() async {
    final gen = ++_generation;
    loading = true;
    slow = false;
    error = null;
    errorDetail = null;
    notifyListeners();

    // If the backend is waking up, reassure instead of leaving a silent wait.
    final slowTimer = Timer(const Duration(seconds: 8), () {
      if (gen == _generation && loading) {
        slow = true;
        notifyListeners();
      }
    });

    // Last N messages, always starting with a student message.
    var history = messages.length > maxHistory
        ? messages.sublist(messages.length - maxHistory)
        : List<ChatMsg>.of(messages);
    while (history.isNotEmpty && !history.first.fromUser) {
      history = history.sublist(1);
    }

    ChatMsg? reply;
    String? newNotice;
    String? errMsg;
    String? errDetail;

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'category': category,
              'immediate_danger': urgent,
              'messages': [
                for (final m in history)
                  {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        var detail = 'HTTP ${response.statusCode}';
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['detail'] != null) {
            detail = body['detail'].toString();
          }
        } catch (_) {
          // Keep the status code if the error body isn't JSON.
        }
        throw Exception(detail);
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected response from backend.');
      }
      final text = '${decoded['reply'] ?? ''}'.trim();
      if (text.isEmpty) {
        throw const FormatException('The reply was empty.');
      }
      final isUrgent = '${decoded['urgency'] ?? ''}'.toLowerCase() == 'urgent';
      reply = ChatMsg(false, text, urgent: isUrgent || urgent);
      final n = decoded['demo_notice'];
      if (n is String && n.trim().isNotEmpty) newNotice = n;
    } on TimeoutException {
      errMsg = 'The server took too long to answer. If it was asleep, '
          'wait a few seconds and try again.';
    } catch (e) {
      errMsg = "We couldn't reach the guidance service. "
          'Check your internet connection and try again.';
      errDetail = e.toString();
    } finally {
      slowTimer.cancel();
    }

    // The chat was reset while waiting: drop this answer.
    if (gen != _generation) return;

    loading = false;
    slow = false;
    if (reply != null) {
      messages.add(reply);
      if (newNotice != null) notice = newNotice;
      HapticFeedback.lightImpact();
    } else {
      error = errMsg;
      errorDetail = errDetail;
    }
    notifyListeners();
  }

  /// Asks the backend to write one short message about this chat that the
  /// student can send to a [audience] ('parent' or 'teacher').
  Future<String> buildSummary(String audience) async {
    var history = messages.length > 40
        ? messages.sublist(messages.length - 40)
        : List<ChatMsg>.of(messages);
    while (history.isNotEmpty && !history.first.fromUser) {
      history = history.sublist(1);
    }
    if (history.isEmpty) {
      throw Exception('Nothing to summarise yet.');
    }

    final response = await http
        .post(
          Uri.parse('$apiBaseUrl/summary'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'category': category,
            'audience': audience,
            'immediate_danger': urgent,
            'messages': [
              for (final m in history)
                {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != 200) {
      var detail = 'HTTP ${response.statusCode}';
      try {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is Map && body['detail'] != null) {
          detail = body['detail'].toString();
        }
      } catch (_) {
        // Keep the status code if the error body isn't JSON.
      }
      throw Exception(detail);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final text = decoded is Map ? '${decoded['summary'] ?? ''}'.trim() : '';
    if (text.isEmpty) {
      throw const FormatException('The summary was empty.');
    }
    return text;
  }

  @override
  void dispose() {
    _disposed = true;
    controller.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// App shell: tabs + bottom navigation
// ---------------------------------------------------------------------------
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  final draft = Draft();

  void go(int i) {
    if (i == index) return;
    setState(() => index = i);
  }

  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  Widget tab() {
    switch (index) {
      case 0:
        return HomeTab(draft: draft, go: go);
      case 1:
        return TalkTab(draft: draft);
      case 2:
        return const ToolkitTab();
      default:
        return const HelpTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) go(0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.025), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(key: ValueKey(index), child: tab()),
          ),
        ),
        bottomNavigationBar: keyboardOpen ? null : AppNavBar(index: index, onTap: go),
      ),
    );
  }
}

class AppNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const AppNavBar({super.key, required this.index, required this.onTap});

  static const items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Talk'),
    (Icons.spa_outlined, Icons.spa_rounded, 'Toolkit'),
    (Icons.support_agent_outlined, Icons.support_agent_rounded, 'Help'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: P.navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: Tap(
                    onTap: () => onTap(i),
                    child: Semantics(
                      selected: i == index,
                      label: items[i].$3,
                      child: ExcludeSemantics(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              width: i == index ? 62 : 36,
                              height: 34,
                              decoration: BoxDecoration(
                                color: i == index ? P.gold : Colors.transparent,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: Icon(
                                i == index ? items[i].$2 : items[i].$1,
                                size: 23,
                                color: i == index ? P.navy : P.cream,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              items[i].$3,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                color: i == index ? P.gold : P.cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 1: Home
// ---------------------------------------------------------------------------
class HomeTab extends StatelessWidget {
  final Draft draft;
  final ValueChanged<int> go;
  const HomeTab({super.key, required this.draft, required this.go});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const TabHeader(kicker: 'SHEGUARD', title: 'You are safe here'),
        // Hero card
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [P.navy, P.navyMid],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -40,
                    bottom: -50,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: P.orange.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: P.cream.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline_rounded, size: 14, color: P.gold),
                                  SizedBox(width: 6),
                                  Text('Private space',
                                      style: TextStyle(
                                          color: P.cream,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(
                              width: 80,
                              height: 80,
                              child: OverflowBox(
                                maxWidth: 120,
                                maxHeight: 120,
                                child: CalmOrb(size: 80),
                              ),
                            ),
                          ],
                        ),
                        const Text(
                          'You deserve to feel safe.',
                          style: TextStyle(
                            color: P.cream,
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Talk things through and find your next safe step. '
                          'You choose what you share.',
                          style: TextStyle(
                            color: P.cream.withValues(alpha: 0.9),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: P.gold,
                            foregroundColor: P.navy,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            go(1);
                          },
                          icon: const Icon(Icons.chat_bubble_rounded, size: 20),
                          label: const Text('Talk it through'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Emergency strip
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Tap(
            onTap: () => go(3),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              decoration: BoxDecoration(
                color: P.brickPale,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: P.brick.withValues(alpha: 0.5), width: 1.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(color: P.brick, shape: BoxShape.circle),
                    child: const Icon(Icons.sos_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('In danger right now?',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16, color: P.navy)),
                        SizedBox(height: 2),
                        Text('Open helplines. Emergency: 112',
                            style: TextStyle(fontSize: 13, color: P.soft)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: P.navy),
                ],
              ),
            ),
          ),
        ),
        const SectionLabel("What's on your mind?"),
        SizedBox(
          height: 124,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: concerns.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final c = concerns[i];
              return Tap(
                onTap: () {
                  draft.setCategory(c.label);
                  go(1);
                },
                child: Container(
                  width: 144,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.tint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(c.icon, color: P.navy, size: 26),
                      Text(
                        c.label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          height: 1.2,
                          color: P.navy,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SectionLabel('Calm yourself first'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: _MiniTool(
                  icon: Icons.air_rounded,
                  label: 'Breathe',
                  onTap: () => showBreatheSheet(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniTool(
                  icon: Icons.visibility_outlined,
                  label: 'Ground',
                  onTap: () => showGroundingSheet(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniTool(
                  icon: Icons.record_voice_over_outlined,
                  label: 'Words',
                  onTap: () => showScriptsSheet(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'AI support, not a replacement for a counsellor. AI can misunderstand, '
            'so talk to a trusted adult about anything serious.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: P.soft, height: 1.4),
          ),
        ),
      ],
    );
  }
}

class _MiniTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MiniTool({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: P.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: P.line, width: 1.5),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: P.goldPale, shape: BoxShape.circle),
              child: Icon(icon, color: P.navy, size: 22),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 14, color: P.navy)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 2: Talk (sends the message to the backend / Claude)
// ---------------------------------------------------------------------------
class TalkTab extends StatefulWidget {
  final Draft draft;
  const TalkTab({super.key, required this.draft});

  @override
  State<TalkTab> createState() => _TalkTabState();
}

class _TalkTabState extends State<TalkTab> {
  static const starters = [
    'It keeps happening at…',
    'I feel…',
    "I don't know what to do about…",
  ];

  final scroll = ScrollController();
  final inputFocus = FocusNode();
  int _lastCount = -1;
  bool _lastBusy = false;

  Draft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    d.addListener(_onDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(animate: false));
  }

  @override
  void dispose() {
    d.removeListener(_onDraft);
    scroll.dispose();
    inputFocus.dispose();
    super.dispose();
  }

  void _onDraft() {
    final busy = d.loading || d.error != null;
    if (d.messages.length != _lastCount || busy != _lastBusy) {
      _lastCount = d.messages.length;
      _lastBusy = busy;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    }
  }

  void _toBottom({bool animate = true}) {
    if (!mounted || !scroll.hasClients) return;
    final end = scroll.position.maxScrollExtent;
    if (animate) {
      scroll.animateTo(end,
          duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      scroll.jumpTo(end);
    }
  }

  void _send() {
    HapticFeedback.selectionClick();
    d.send();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: P.bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: const Heading('Start a new chat?', size: 22),
        content: const Text(
          'This clears the conversation from the app. Messages already sent to the AI provider may be subject to its data-retention policies.',
          style: TextStyle(color: P.soft, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: P.navy),
            child: const Text('Keep chatting'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: P.brick),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      d.reset();
    }
  }

  void _showHelplines() => showToolSheet(
        context,
        title: 'Helplines',
        subtitle: 'Free to call. Tap a number to copy it.',
        child: const HelplineList(emphasize: true),
      );

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final msgs = d.messages;
        final lastAiIndex = msgs.lastIndexWhere((m) => !m.fromUser);
        final extra = (d.loading ? 1 : 0) + (d.error != null ? 1 : 0);
        // item 0 is the local greeting (never sent to the backend)
        final itemCount = 1 + msgs.length + extra;

        return Column(
          children: [
            const TabHeader(kicker: 'Private chat', title: 'Talk to SHEGUARD'),
            if (!(keyboardOpen && msgs.isNotEmpty))
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: concerns.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = concerns[i];
                    return _CategoryChip(
                      concern: c,
                      selected: d.category == c.label,
                      onTap: d.loading ? null : () => d.setCategory(c.label),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
              child: Row(
                children: [
                  _DangerPill(
                    value: d.urgent,
                    onChanged: (v) => d.setUrgent(v),
                  ),
                  const Spacer(),
                  if (msgs.isNotEmpty)
                    Tap(
                      onTap: _confirmReset,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: P.card,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: P.line, width: 1.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_square, size: 16, color: P.navy),
                            SizedBox(width: 6),
                            Text('New chat',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: P.navy)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (d.urgent)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: _EmergencyBanner(onHelplines: _showHelplines),
              ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics()),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                itemCount: itemCount,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _ChatBubble(
                          msg: ChatMsg(
                            false,
                            "Hi, I'm SHEGUARD. This is a private space to talk "
                            'things through. Share only what feels okay, and '
                            'please leave out names, phone numbers and addresses. '
                            'What would you like to talk about?',
                          ),
                        ),
                        if (msgs.isEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 40, top: 2),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final s in starters)
                                  ActionChip(
                                    label: Text(s),
                                    onPressed: () {
                                      d.addStarter(s);
                                      inputFocus.requestFocus();
                                    },
                                    backgroundColor: P.cream,
                                    side: BorderSide.none,
                                    shape: const StadiumBorder(),
                                    labelStyle: const TextStyle(
                                      color: P.navy,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 32, top: 4),
                            child: TextButton.icon(
                              onPressed: () {
                                d.fillDemo();
                                inputFocus.requestFocus();
                              },
                              style: TextButton.styleFrom(foregroundColor: P.navy),
                              icon: const Icon(Icons.science_outlined, size: 18),
                              label: const Text('Try a fictional demo example'),
                            ),
                          ),
                        ],
                      ],
                    );
                  }

                  final m = i - 1;
                  if (m < msgs.length) {
                    final msg = msgs[m];
                    return _ChatBubble(
                      msg: msg,
                      footnote: (m == lastAiIndex && d.notice != null) ? d.notice : null,
                      onHelplines: msg.urgent && !msg.fromUser ? _showHelplines : null,
                    );
                  }

                  // loading / error rows
                  final k = m - msgs.length;
                  if (d.loading && k == 0) return _TypingBubble(slow: d.slow);
                  return _ErrorBubble(
                    message: d.error ?? '',
                    detail: d.errorDetail,
                    onRetry: d.retry,
                    onHelplines: _showHelplines,
                  );
                },
              ),
            ),
            if (msgs.any((m) => !m.fromUser) && !keyboardOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Tap(
                  onTap: d.loading ? null : () => showSummarySheet(context, d),
                  child: Opacity(
                    opacity: d.loading ? 0.5 : 1,
                    child: Container(
                      height: 46,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: P.cream,
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_unread_outlined,
                              size: 19, color: P.navy),
                          SizedBox(width: 8),
                          Text(
                            'Make a message for a parent or teacher',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: P.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _Composer(
              controller: d.controller,
              focusNode: inputFocus,
              loading: d.loading,
              onSend: _send,
            ),
          ],
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMsg msg;
  final String? footnote;
  final VoidCallback? onHelplines;
  const _ChatBubble({required this.msg, this.footnote, this.onHelplines});

  @override
  Widget build(BuildContext context) {
    final user = msg.fromUser;
    final urgent = msg.urgent && !user;
    final maxW = MediaQuery.sizeOf(context).width * (user ? 0.78 : 0.86);

    final bubbleColor = user ? P.navy : (urgent ? P.brickPale : P.card);
    final textColor = user ? P.cream : P.navy;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(22),
          topRight: const Radius.circular(22),
          bottomLeft: Radius.circular(user ? 22 : 6),
          bottomRight: Radius.circular(user ? 6 : 22),
        ),
        border: user
            ? null
            : Border.all(color: urgent ? P.brick : P.line, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          user
              ? Text(msg.text,
                  style: TextStyle(fontSize: 16, height: 1.45, color: textColor))
              : ReplyText(text: msg.text, color: textColor),
          if (onHelplines != null) ...[
            const SizedBox(height: 10),
            Tap(
              onTap: onHelplines,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: P.brick,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_in_talk_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 6),
                    Text('Call a helpline now',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final tappable = GestureDetector(
      onLongPress: () => copyText(context, msg.text, 'Message copied'),
      child: bubble,
    );

    return FadeSlide(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: user ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!user) ...[
                  _AiAvatar(urgent: urgent),
                  const SizedBox(width: 8),
                ],
                Flexible(child: tappable),
              ],
            ),
            if (footnote != null)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 6, right: 8),
                child: Text(
                  footnote!,
                  style: const TextStyle(fontSize: 11.5, color: P.soft, height: 1.35),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AiAvatar extends StatelessWidget {
  final bool urgent;
  const _AiAvatar({this.urgent = false});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: urgent ? P.brick : P.gold,
          shape: BoxShape.circle,
        ),
        child: Icon(
          urgent ? Icons.support_agent_rounded : Icons.favorite_rounded,
          size: 17,
          color: urgent ? Colors.white : P.navy,
        ),
      );
}

/// "SHEGUARD is typing" bubble with three bouncing dots.
class _TypingBubble extends StatefulWidget {
  final bool slow;
  const _TypingBubble({required this.slow});

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const _AiAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: P.card,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                  bottomLeft: Radius.circular(6),
                ),
                border: Border.all(color: P.line, width: 1.5),
              ),
              child: widget.slow
                  ? const Text(
                      'Still thinking. Thank you for waiting…',
                      style: TextStyle(color: P.soft, fontSize: 14.5),
                    )
                  : AnimatedBuilder(
                      animation: _c,
                      builder: (_, __) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++)
                            Padding(
                              padding: EdgeInsets.only(right: i == 2 ? 0 : 5),
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  -4 *
                                      math.max(
                                        0.0,
                                        math.sin((_c.value * 2 * math.pi) - i * 0.9),
                                      ),
                                ),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: P.soft,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  final String message;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback onHelplines;
  const _ErrorBubble({
    required this.message,
    required this.detail,
    required this.onRetry,
    required this.onHelplines,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: P.brickPale,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                  color: P.navy, height: 1.4, fontWeight: FontWeight.w700),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!, style: const TextStyle(fontSize: 11, color: P.soft)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tap(
                  onTap: onRetry,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: P.navy,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 16, color: P.cream),
                        SizedBox(width: 6),
                        Text('Try again',
                            style: TextStyle(
                                color: P.cream,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Tap(
                  onTap: onHelplines,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: P.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: P.brick, width: 1.5),
                    ),
                    child: const Text('Helplines',
                        style: TextStyle(
                            color: P.brick,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: const BoxDecoration(
        color: P.bg,
        border: Border(top: BorderSide(color: P.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 5,
              maxLength: 1200,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                  null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 16, color: P.navy, height: 1.35),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: P.line, width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: P.line, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(26),
                  borderSide: const BorderSide(color: P.navy, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) {
              final enabled = value.text.trim().isNotEmpty && !loading;
              return Tap(
                onTap: enabled ? onSend : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: enabled ? P.gold : P.line,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    color: enabled ? P.navy : P.soft,
                    semanticLabel: 'Send',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DangerPill extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _DangerPill({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: () {
        HapticFeedback.mediumImpact();
        onChanged(!value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value ? P.brick : P.brickPale,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: P.brick, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 17, color: value ? Colors.white : P.brick),
            const SizedBox(width: 6),
            Text(
              value ? 'In danger: ON' : 'I may be in danger',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: value ? Colors.white : P.brick,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  final VoidCallback onHelplines;
  const _EmergencyBanner({required this.onHelplines});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: P.brickPale,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: P.brick, width: 1.5),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'If you are in danger now, call 112 or tell a trusted adult near you.',
              style: TextStyle(
                  fontSize: 13, height: 1.35, fontWeight: FontWeight.w700, color: P.navy),
            ),
          ),
          const SizedBox(width: 8),
          Tap(
            onTap: onHelplines,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: P.brick,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('Helplines',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet: AI-written summary the student can edit, then copy.
Future<void> showSummarySheet(BuildContext context, Draft draft) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: P.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (_) => _SummarySheet(draft: draft),
  );
}

class _SummarySheet extends StatefulWidget {
  final Draft draft;
  const _SummarySheet({required this.draft});

  @override
  State<_SummarySheet> createState() => _SummarySheetState();
}

class _SummarySheetState extends State<_SummarySheet> {
  final text = TextEditingController();
  String audience = 'parent';
  bool loading = true;
  bool copied = false;
  String? error;
  int _req = 0;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    text.addListener(() {
      if (mounted) setState(() {});
    });
    _generate();
  }

  @override
  void dispose() {
    _req++;
    _copiedTimer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final req = ++_req;
    setState(() {
      loading = true;
      error = null;
      copied = false;
    });
    try {
      final result = await widget.draft.buildSummary(audience);
      if (!mounted || req != _req) return;
      text.text = result;
      setState(() => loading = false);
    } on TimeoutException {
      if (!mounted || req != _req) return;
      setState(() {
        loading = false;
        error = 'That took too long. Please try again.';
      });
    } catch (_) {
      if (!mounted || req != _req) return;
      setState(() {
        loading = false;
        error = "We couldn't write the message. Check your connection and try again.";
      });
    }
  }

  void _pick(String a) {
    if (loading || a == audience) return;
    HapticFeedback.selectionClick();
    audience = a;
    _generate();
  }

  Future<void> _copy() async {
    final value = text.text.trim();
    if (value.isEmpty) return;
    HapticFeedback.mediumImpact();
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => copied = false);
    });
  }

  Widget _audienceChip(String value, String label, IconData icon) {
    final selected = audience == value;
    return Tap(
      onTap: () => _pick(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? P.navy : P.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? P.navy : P.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? P.cream : P.navy),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: selected ? P.cream : P.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCopy = !loading && error == null && text.text.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Heading('Message to share', size: 24),
              const SizedBox(height: 6),
              const Text(
                'A short summary of your chat. Read it, change anything that '
                "isn't right, then copy it.",
                style: TextStyle(color: P.soft, height: 1.4, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _audienceChip('parent', 'For a parent', Icons.family_restroom_outlined),
                  _audienceChip('teacher', 'For a teacher', Icons.school_outlined),
                ],
              ),
              const SizedBox(height: 16),
              if (loading)
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: P.card,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: P.line, width: 1.5),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 3, color: P.navy),
                      ),
                      SizedBox(height: 12),
                      Text('Writing a short message…',
                          style: TextStyle(color: P.soft, fontSize: 14.5)),
                    ],
                  ),
                )
              else if (error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: P.brickPale,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error!,
                          style: const TextStyle(
                              color: P.navy, height: 1.4, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      Tap(
                        onTap: _generate,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: P.navy,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.refresh_rounded, size: 16, color: P.cream),
                              SizedBox(width: 6),
                              Text('Try again',
                                  style: TextStyle(
                                      color: P.cream,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                TextField(
                  controller: text,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 900,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                      null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 16, color: P.navy, height: 1.45),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: P.card,
                    contentPadding: const EdgeInsets.all(16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: P.line, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: P.line, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: const BorderSide(color: P.navy, width: 2),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Written by AI from your chat, so please check it is correct '
                'before you send it. You decide who sees it.',
                style: TextStyle(fontSize: 12.5, color: P.soft, height: 1.35),
              ),
              const SizedBox(height: 14),
              Tap(
                onTap: canCopy ? _copy : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 54,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: !canCopy ? P.line : (copied ? P.navy : P.gold),
                    borderRadius: BorderRadius.circular(27),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 20,
                        color: copied ? P.cream : (canCopy ? P.navy : P.soft),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        copied
                            ? 'Copied. Paste it into WhatsApp, SMS or email'
                            : 'Copy message',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: copied ? P.cream : (canCopy ? P.navy : P.soft),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canCopy)
                Align(
                  alignment: Alignment.center,
                  child: TextButton.icon(
                    onPressed: _generate,
                    style: TextButton.styleFrom(foregroundColor: P.navy),
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    label: const Text('Write it again'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final Concern concern;
  final bool selected;
  final VoidCallback? onTap;
  const _CategoryChip({required this.concern, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? P.navy : P.card,
          borderRadius: BorderRadius.circular(23),
          border: Border.all(color: selected ? P.navy : P.line, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(concern.icon, size: 19, color: selected ? P.gold : P.soft),
            const SizedBox(width: 8),
            Text(
              concern.label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: selected ? P.cream : P.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 3: Toolkit (calming + preparing tools, all interactive and local)
// ---------------------------------------------------------------------------
class ToolkitTab extends StatelessWidget {
  const ToolkitTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const TabHeader(kicker: 'Tools for you', title: 'Calm toolkit'),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'Small things that help in the moment. Nothing here is saved.',
            style: TextStyle(color: P.soft, fontSize: 15, height: 1.4),
          ),
        ),
        _ToolCard(
          icon: Icons.air_rounded,
          title: 'Breathe with me',
          text: 'A slow guided breath to settle your body.',
          color: P.navy,
          dark: true,
          onTap: () => showBreatheSheet(context),
        ),
        _ToolCard(
          icon: Icons.visibility_outlined,
          title: 'Ground yourself',
          text: 'The 5-4-3-2-1 steps when your mind is racing.',
          color: P.gold,
          onTap: () => showGroundingSheet(context),
        ),
        _ToolCard(
          icon: Icons.record_voice_over_outlined,
          title: 'Words to say',
          text: 'Ready-made sentences to start a hard talk.',
          color: P.cream,
          onTap: () => showScriptsSheet(context),
        ),
        _ToolCard(
          icon: Icons.checklist_rounded,
          title: 'My safety checklist',
          text: 'Tick off what you already have in place.',
          color: P.orange,
          onTap: () => showSafetySheet(context),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final Color color;
  final bool dark;
  final VoidCallback onTap;
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
    required this.onTap,
    this.dark = false,
  });

  @override
  Widget build(BuildContext context) {
    final fg = dark ? P.cream : P.navy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Tap(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(28)),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: dark ? P.gold : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: P.navy, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800, color: fg)),
                    const SizedBox(height: 3),
                    Text(text,
                        style: TextStyle(
                            fontSize: 13.5,
                            height: 1.35,
                            color: fg.withValues(alpha: 0.88))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Toolkit sheets ---------------------------------------------------------
void showBreatheSheet(BuildContext context) => showToolSheet(
      context,
      title: 'Breathe with me',
      subtitle: 'In through your nose, out slowly through your mouth.',
      child: const _BreatheWidget(),
    );

void showGroundingSheet(BuildContext context) => showToolSheet(
      context,
      title: 'Ground yourself',
      subtitle: 'Tap each step as you do it. Go slowly.',
      child: const _CheckList(items: [
        ('5', 'things you can see'),
        ('4', 'things you can touch'),
        ('3', 'things you can hear'),
        ('2', 'things you can smell'),
        ('1', 'slow, deep breath'),
      ]),
    );

void showSafetySheet(BuildContext context) => showToolSheet(
      context,
      title: 'My safety checklist',
      subtitle: 'Tap what is already true for you. Not saved anywhere.',
      child: const _CheckList(items: [
        ('1', 'I know one adult I could tell'),
        ('2', 'I know a safe place I can go'),
        ('3', 'I know the numbers 112 and 1098'),
        ('4', 'I have a friend who can stay with me'),
      ]),
    );

void showScriptsSheet(BuildContext context) => showToolSheet(
      context,
      title: 'Words to say',
      subtitle: 'Tap a sentence to copy it, then send or say it.',
      child: Builder(
        builder: (ctx) => Column(
          children: [
            for (final s in const [
              'Can we talk privately? Something has been bothering me.',
              'I need help and I do not know how to start.',
              'I need someone to listen first. Can we talk quietly?',
              'I do not feel safe. Can you stay with me?',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Tap(
                  onTap: () => copyText(ctx, s, 'Sentence copied'),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: P.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: P.line, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(s,
                              style: const TextStyle(
                                  fontSize: 15.5, height: 1.4, color: P.navy)),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.copy_rounded, size: 18, color: P.soft),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

class _CheckList extends StatefulWidget {
  final List<(String, String)> items;
  const _CheckList({required this.items});

  @override
  State<_CheckList> createState() => _CheckListState();
}

class _CheckListState extends State<_CheckList> {
  final done = <int>{};

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < widget.items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tap(
              onTap: () => setState(() {
                if (!done.add(i)) done.remove(i);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: done.contains(i) ? P.goldPale : P.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: done.contains(i) ? P.orange : P.line,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: done.contains(i) ? P.navy : P.cream,
                        shape: BoxShape.circle,
                      ),
                      child: done.contains(i)
                          ? const Icon(Icons.check_rounded, color: P.gold, size: 22)
                          : Text(widget.items[i].$1,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: P.navy, fontSize: 17)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.items[i].$2,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600, color: P.navy),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BreatheWidget extends StatefulWidget {
  const _BreatheWidget();

  @override
  State<_BreatheWidget> createState() => _BreatheWidgetState();
}

class _BreatheWidgetState extends State<_BreatheWidget>
    with SingleTickerProviderStateMixin {
  // 4 seconds in, 6 seconds out.
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  double scaleAt(double v) {
    if (v < 0.4) return Curves.easeInOut.transform(v / 0.4);
    return 1 - Curves.easeInOut.transform((v - 0.4) / 0.6);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: AnimatedBuilder(
        animation: c,
        builder: (_, __) {
          final s = scaleAt(c.value);
          final inhale = c.value < 0.4;
          final size = 120 + 110 * s;
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: size + 36,
                        height: size + 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: P.orange.withValues(alpha: 0.18),
                        ),
                      ),
                      Container(
                        width: size,
                        height: size,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [P.gold, P.orange],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: P.orange.withValues(alpha: 0.4),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Text(
                          inhale ? 'Breathe in' : 'Breathe out',
                          style: const TextStyle(
                            color: P.navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Text(
                'Repeat for a minute or two.',
                style: TextStyle(color: P.soft, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab 4: Help
// ---------------------------------------------------------------------------
class HelpTab extends StatelessWidget {
  const HelpTab({super.key});

  @override
  Widget build(BuildContext context) {
    final others = helplines.where((h) => h.number != '112').toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const TabHeader(kicker: 'You are not alone', title: 'Get help'),
        // Emergency card
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: P.brick,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'In danger right now?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '112',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 54,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Emergency / Police. Move to a safe place and call with a trusted adult.',
                  style: TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: P.brick,
                  ),
                  onPressed: () => copyText(context, '112', 'Emergency number copied'),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  label: const Text('Copy 112'),
                ),
              ],
            ),
          ),
        ),
        const SectionLabel('Free helplines'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: HelplineList(lines: others),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Text(
            'Tap a number to copy it, then call from your phone, ideally with a '
            'trusted adult beside you. Numbers can change, so ask a trusted adult to confirm.',
            style: TextStyle(fontSize: 12.5, color: P.soft, height: 1.4),
          ),
        ),
        const SectionLabel('People you can talk to'),
        const _TrustedRow(
          icon: Icons.school_outlined,
          title: 'A trusted teacher',
          text: 'Choose someone you feel comfortable approaching.',
        ),
        const _TrustedRow(
          icon: Icons.support_agent,
          title: 'School counsellor',
          text: 'Ask whether you can speak privately.',
        ),
        const _TrustedRow(
          icon: Icons.family_restroom,
          title: 'Parent, guardian or trusted adult',
          text: 'Ask them to come with you when you ask for help.',
        ),
      ],
    );
  }
}
