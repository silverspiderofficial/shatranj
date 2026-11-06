import '../logic/hint_explainer.dart';

/// Short learning tips per game phase: (Persian, English).
const Map<GamePhase, List<(String, String)>> kTips = {
  GamePhase.opening: [
    ('با سربازهای e یا d مرکز را بگیرید.', 'Take the center with your e- or d-pawn.'),
    ('اسب‌ها را قبل از فیل‌ها توسعه دهید.', 'Develop knights before bishops.'),
    ('در گشایش یک مهره را دو بار حرکت ندهید.', 'Avoid moving the same piece twice in the opening.'),
    ('وزیر را زود وارد بازی نکنید؛ هدف حملهٔ مهره‌های حریف می‌شود.', 'Don\'t bring your queen out early; it becomes a target.'),
    ('زود قلعه بروید تا شاه امن شود.', 'Castle early to keep your king safe.'),
    ('رخ‌ها را با خالی کردن ردیف اول به هم وصل کنید.', 'Connect your rooks by clearing the back rank.'),
    ('سربازهای جلوی شاهِ قلعه‌رفته را بی‌دلیل حرکت ندهید.', 'Don\'t push the pawns in front of your castled king without reason.'),
  ],
  GamePhase.middlegame: [
    ('قبل از هر حرکت بپرسید: حریف چه تهدیدی دارد؟', 'Before every move ask: what is my opponent threatening?'),
    ('کیش‌ها، زدن‌ها و تهدیدها را اول بررسی کنید.', 'Check checks, captures and threats first.'),
    ('چنگال اسب را جدی بگیرید؛ اسب به مهره‌هایی با رنگ خانهٔ مخالف حمله می‌کند.', 'Watch for knight forks.'),
    ('مهرهٔ میخ‌شده نمی‌تواند آزادانه حرکت کند؛ به آن فشار بیاورید.', 'A pinned piece cannot move freely; pile up on it.'),
    ('رخ‌ها را در ستون‌های باز قرار دهید.', 'Put your rooks on open files.'),
    ('اسب در خانهٔ پیشرفته‌ای که سرباز حریف نمی‌تواند آن را بزند، بسیار قوی است.', 'A knight on an outpost is very strong.'),
    ('وقتی جلو هستید، مهره تعویض کنید؛ وقتی عقب هستید، از تعویض پرهیز کنید.', 'Trade pieces when ahead, avoid trades when behind.'),
  ],
  GamePhase.endgame: [
    ('در آخر بازی شاه را فعال کنید و به مرکز بیاورید.', 'Activate your king in the endgame.'),
    ('سرباز آزاد باید جلو برود.', 'Passed pawns must be pushed.'),
    ('رخ را پشت سرباز آزاد قرار دهید.', 'Place rooks behind passed pawns.'),
    ('اپوزیسیون: شاه‌ها روبه‌روی هم با یک خانه فاصله؛ طرفی که نوبتش نیست برتری دارد.', 'Opposition: kings facing with one square between; the side not to move has it.'),
    ('مراقب پات باشید؛ وقتی خیلی جلو هستید به شاه حریف خانهٔ خالی بدهید.', 'Beware of stalemate when you are far ahead.'),
    ('قاعدهٔ مربع: ببینید شاه می‌تواند به سرباز آزاد برسد یا نه.', 'Rule of the square: can the king catch the passed pawn?'),
  ],
};

/// Interactive rule lessons for beginners.
class Lesson {
  const Lesson({
    required this.titleFa,
    required this.titleEn,
    required this.textFa,
    required this.textEn,
    required this.fen,
    this.keepTurn = true,
  });

  final String titleFa;
  final String titleEn;
  final String textFa;
  final String textEn;
  final String fen;

  /// When true the learner keeps the move after each move (piece lessons).
  final bool keepTurn;
}

const kLessons = <Lesson>[
  Lesson(
    titleFa: 'شاه',
    titleEn: 'King',
    textFa: 'شاه در هر جهت فقط یک خانه حرکت می‌کند. شاه هرگز نباید به خانه‌ای برود که مورد حمله است. هدف شطرنج مات کردن شاه حریف است.',
    textEn: 'The king moves one square in any direction. It may never move into check. The goal of chess is to checkmate the enemy king.',
    fen: '7k/8/8/8/3K4/8/8/8 w - - 0 1',
  ),
  Lesson(
    titleFa: 'وزیر',
    titleEn: 'Queen',
    textFa: 'وزیر قوی‌ترین مهره است: هر تعداد خانه به صورت مستقیم یا مورب حرکت می‌کند، به شرطی که مهره‌ای سر راهش نباشد.',
    textEn: 'The queen is the strongest piece: it moves any number of squares straight or diagonally, without jumping.',
    fen: '7k/8/8/8/3Q4/8/8/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'رخ',
    titleEn: 'Rook',
    textFa: 'رخ به صورت افقی یا عمودی هر تعداد خانه حرکت می‌کند. سربازهای سیاه را بزنید!',
    textEn: 'The rook moves any number of squares horizontally or vertically. Capture the black pawns!',
    fen: '7k/1p6/8/8/3R2p1/8/8/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'فیل',
    titleEn: 'Bishop',
    textFa: 'فیل به صورت مورب هر تعداد خانه حرکت می‌کند و همیشه روی خانه‌های یک رنگ می‌ماند.',
    textEn: 'The bishop moves diagonally any number of squares and always stays on one color.',
    fen: '7k/6p1/1p6/8/3B4/8/8/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'اسب',
    titleEn: 'Knight',
    textFa: 'اسب به شکل L حرکت می‌کند: دو خانه در یک جهت و یک خانه به کنار. اسب تنها مهره‌ای است که می‌تواند از روی مهره‌ها بپرد.',
    textEn: 'The knight moves in an L: two squares one way and one to the side. It is the only piece that can jump.',
    fen: '7k/8/2p1p3/8/3N4/2PPP3/8/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'سرباز',
    titleEn: 'Pawn',
    textFa: 'سرباز یک خانه به جلو می‌رود (از خانهٔ اول خود می‌تواند دو خانه برود) و به صورت مورب یک خانه به جلو مهره می‌زند. سرباز به عقب برنمی‌گردد.',
    textEn: 'A pawn moves one square forward (two from its starting square) and captures one square diagonally forward. It never moves back.',
    fen: '7k/8/8/8/2p5/8/3P4/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'ارتقای سرباز',
    titleEn: 'Promotion',
    textFa: 'وقتی سرباز به آخرین ردیف برسد باید به وزیر، رخ، فیل یا اسب تبدیل شود. سرباز را به ردیف ۸ ببرید.',
    textEn: 'A pawn that reaches the last rank must become a queen, rook, bishop or knight. Push the pawn to the 8th rank.',
    fen: '7k/3P4/8/8/8/8/8/K7 w - - 0 1',
  ),
  Lesson(
    titleFa: 'قلعه رفتن',
    titleEn: 'Castling',
    textFa: 'شاه دو خانه به سمت رخ می‌رود و رخ از روی آن می‌پرد. شرط‌ها: شاه و آن رخ قبلاً حرکت نکرده باشند، بین آن‌ها خالی باشد، شاه کیش نباشد و از خانهٔ مورد حمله عبور نکند یا در آن قرار نگیرد. شاه را دو خانه به راست یا چپ ببرید.',
    textEn: 'The king moves two squares toward a rook and the rook jumps over it. Neither may have moved, the squares between must be empty, and the king may not be in check, pass through or land on an attacked square.',
    fen: 'r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1',
  ),
  Lesson(
    titleFa: 'آنپاسان',
    titleEn: 'En passant',
    textFa: 'سیاه همین حالا سرباز d را دو خانه جلو آورد. سرباز e5 شما می‌تواند آن را «در حین عبور» بزند و به d6 برود؛ فقط در همین حرکت!',
    textEn: 'Black just pushed the d-pawn two squares. Your e5 pawn can capture it "in passing" by moving to d6 — only right now!',
    fen: '4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1',
    keepTurn: false,
  ),
  Lesson(
    titleFa: 'کیش و مات',
    titleEn: 'Checkmate',
    textFa: 'وقتی شاه مورد حمله باشد «کیش» است. اگر هیچ راهی برای رفع کیش نباشد «مات» است و بازی تمام می‌شود. با رخ مات کنید!',
    textEn: 'A king under attack is in check. If there is no way out, it is checkmate and the game ends. Mate with the rook!',
    fen: '6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1',
    keepTurn: false,
  ),
  Lesson(
    titleFa: 'پات',
    titleEn: 'Stalemate',
    textFa: 'اگر نوبت بازیکنی باشد که کیش نیست ولی هیچ حرکت مجازی ندارد، بازی «پات» و مساوی است. اینجا وزیر به c7 برود پات می‌شود؛ مراقب باشید!',
    textEn: 'If the side to move is not in check but has no legal move, it is stalemate: a draw. Here Qc7 would stalemate — be careful!',
    fen: 'k7/8/1K6/8/8/8/8/2Q5 w - - 0 1',
    keepTurn: false,
  ),
  Lesson(
    titleFa: 'تساوی‌ها',
    titleEn: 'Draws',
    textFa: 'بازی مساوی می‌شود با: پات، توافق، تکرار سه‌بارهٔ یک وضعیت، ۵۰ حرکت بدون زدن مهره یا حرکت سرباز، و نبود مهرهٔ کافی برای مات (مثلاً شاه در برابر شاه، یا شاه و یک اسب/فیل).',
    textEn: 'A game is drawn by stalemate, agreement, threefold repetition, 50 moves without a capture or pawn move, or insufficient material (e.g. king vs king, or king and one minor piece).',
    fen: '8/8/4k3/8/8/3NK3/8/8 w - - 0 1',
  ),
];
