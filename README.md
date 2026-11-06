# شطرنج آفلاین (Shatranj) — Offline Chess for Android

اپ کامل شطرنج آفلاین با Flutter. رابط فارسی (راست‌به‌چپ) و انگلیسی، صفحهٔ شطرنج همیشه چپ‌به‌راست. بدون اینترنت، بدون مجوز (نه مخاطبین، نه حافظه، نه شبکه).

A complete offline chess app built with Flutter. Persian (RTL) and English UI; the board always stays LTR. No internet, no permissions.

## دانلود / Download
آخرین نسخه را از بخش **Releases** همین مخزن دانلود کنید:
https://github.com/silverspiderofficial/shatranj/releases/latest

- `arm64-v8a` — تقریباً همهٔ گوشی‌های جدید (پیشنهادی)
- `armeabi-v7a` — گوشی‌های قدیمی ۳۲ بیتی
- `universal` — اگر مطمئن نیستید

نصب: فایل را روی گوشی باز کنید، اجازهٔ «نصب از منابع ناشناس» را برای مرورگر/مدیر فایل بدهید و نصب کنید. حداقل اندروید ۷.۰ (API 24).

## امکانات / Features
- بازی با کامپیوتر (Stockfish 19 روی خود گوشی) با ۱۰ سطح: سطح ۱ حرکت تصادفی، سطح ۲ تا ۱۰ با UCI_Elo از ۱۳۵۰ تا ۲۸۰۰ همراه Skill Level و محدودیت زمان/عمق
- انتخاب رنگ سفید/سیاه/تصادفی؛ موتور در رشته‌های بومی جدا فکر می‌کند و رابط قفل نمی‌شود
- بازی دونفره روی یک گوشی: صفحهٔ ثابت، چرخش خودکار، یا رودررو (مهره‌های حریف وارونه)
- همهٔ قوانین FIDE: قلعهٔ کوچک/بزرگ با همهٔ شرط‌ها، آنپاسان، ارتقا با پنجرهٔ انتخاب، کیش، مات، پات، تکرار سه‌باره، قانون ۵۰ حرکت، نبود مهرهٔ کافی، باخت/تساوی با اتمام وقت
- راهنما با فلش و توضیح فارسی (چنگال، زدن مهره، کیش، توسعه، …)، تعداد قابل تنظیم (نامحدود / ۳ / خاموش)
- هشدار اشتباه (افت بیش از ۲ پیاده یا مات‌شدن) با امکان برگرداندن
- نمایش حرکت‌های مجاز، نوار ارزیابی اختیاری، نکته‌های آموزشی گشایش/وسط‌بازی/آخر بازی
- Undo/Redo، ساعت (۱+۰، ۳+۲، ۵+۰، ۱۰+۰، ۱۵+۱۰، بدون زمان، سفارشی)، فهرست حرکت SAN
- پیشنهاد مساوی و تسلیم، ذخیرهٔ خودکار و ادامهٔ بازی نیمه‌تمام
- تاریخچه، تحلیل بعد از بازی با Stockfish (اشتباه بزرگ/اشتباه/بی‌دقتی + بهترین حرکت)
- ورود/خروجی PGN و FEN، کپی و اشتراک‌گذاری
- ۶۰۰ معمای آفلاین در ۶ سطح (پایگاه آزاد lichess، CC0) با ریتینگ معما
- آموزش تعاملی قوانین (۱۲ درس)
- ۴ تم صفحه (چوبی، سبز، آبی، تیره)، ۶ طرح مهره، حالت تاریک/روشن، صدا با امکان خاموش کردن
- چرخاندن صفحه، مختصات، برجسته‌سازی آخرین حرکت و شاه در کیش، آمار برد/باخت/مساوی هر سطح
- شطرنج ۹۶۰

## ساختار کد / Code layout
```
lib/
  main.dart                  App, theme, locale, engine cleanup on exit
  providers.dart             Riverpod providers (settings, db, engine, sound)
  l10n/strings.dart          Persian/English strings, Persian digits
  l10n/content.dart          Learning tips and rule lessons
  models/                    game_models.dart, settings.dart
  logic/chess_game.dart      Pure game logic on dartchess (FIDE end rules, undo/redo, PGN, Chess960, random bot)
  logic/hint_explainer.dart  Persian explanations for hints
  services/                  engine_service.dart (Stockfish/UCI), database_service.dart (sqflite), sound_service.dart
  controllers/game_controller.dart  Game flow, clocks, hints, blunder check, autosave
  screens/                   home, setup, game, analysis, puzzle, history+stats, settings, learn
  widgets/common.dart        LTR board wrapper, eval bar, clock, move list, export sheet
test/chess_game_test.dart    Unit tests for game logic
```

## ساخت / Build
```bash
flutter pub get
flutter test
flutter build apk --release --split-per-abi
```
GitHub Actions (`.github/workflows/build-apk.yml`) on every push to `main` builds the APKs and publishes a Release.

### امضای ثابت (اختیاری) / Stable signing (optional)
بدون کلید، هر بیلد با کلید debug موقت امضا می‌شود و برای نصب نسخهٔ جدید باید نسخهٔ قبلی را حذف کنید. برای به‌روزرسانی بدون حذف، یک keystore بسازید و در Settings → Secrets → Actions این‌ها را اضافه کنید:
`KEYSTORE_BASE64`، `KEYSTORE_PASSWORD`، `KEY_ALIAS`، `KEY_PASSWORD`.
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks   # value for KEYSTORE_BASE64
```

## مجوز / License
GPL-3.0 (see `LICENSE`). Uses [dartchess](https://pub.dev/packages/dartchess), [chessground](https://pub.dev/packages/chessground) and [multistockfish](https://pub.dev/packages/multistockfish) by lichess.org (GPL-3.0), Stockfish (GPL-3.0), lichess puzzle database (CC0), Vazirmatn font (OFL-1.1).
