import 'package:flutter/material.dart';

/// Design tokens — 設計書 §17.1. One source of truth for every colour in the app.
abstract final class HinaColors {
  // Brand
  static const sky = Color(0xFF5AA8D6); // map route / pins / links
  static const leaf = Color(0xFF7FB366); // success / safe
  static const mist = Color(0xFFC8E6E9); // pale surfaces on map
  static const sand = Color(0xFFEADCC8); // card tint / dividers
  static const sun = Color(0xFFF2C94C); // primary CTA / セナヴィの首輪

  // Base
  static const bg = Color(0xFFFAF8F4);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF2B2B2B);
  static const inkSub = Color(0xFF7A7570);
  static const line = Color(0xFFE6E0D8);

  // Status (5) — shared by Friends, own chip, markers
  static const stSafe = Color(0xFF7FB366);
  static const stAssessing = Color(0xFFF2C94C);
  static const stEvacuating = Color(0xFFF0A24B);
  static const stArrived = Color(0xFF8E7CC3);
  static const stUnknown = Color(0xFF9E9E9E);

  // Warning — only for alert banners / danger
  static const alert = Color(0xFFE57373);
  static const alertBg = Color(0xFFFDECEA);

  // Hazard overlays (applied with opacity 0.35)
  static const hzFlood = Color(0xFFB39DDB);
  static const hzLandslide = Color(0xFFD7B377);
  static const hzTsunami = Color(0xFF80CBC4);

  // Demo
  static const demoBand = Color(0xFFFFE08A);
}
