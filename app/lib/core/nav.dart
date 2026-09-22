import 'package:flutter/widgets.dart';

/// アプリ全体で1つのナビゲータ。画面を閉じた後でも通知を出せるように、
/// context ではなくここから Overlay を取る(閉じたシートの context は死んでいる)。
final rootNavigatorKey = GlobalKey<NavigatorState>();
