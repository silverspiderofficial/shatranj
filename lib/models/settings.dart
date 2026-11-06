import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';

enum BoardTheme {
  wood(ChessboardColorScheme.wood),
  green(ChessboardColorScheme.green),
  blue(ChessboardColorScheme.blue),
  dark(ChessboardColorScheme.grey);

  const BoardTheme(this.scheme);
  final ChessboardColorScheme scheme;
}

/// Piece sets offered in settings (all bundled offline inside chessground).
const kPieceSets = <PieceSet>[
  PieceSet.cburnett,
  PieceSet.merida,
  PieceSet.alpha,
  PieceSet.staunty,
  PieceSet.california,
  PieceSet.leipzig,
];

/// Hints allowed per single-player game: -1 unlimited, 3, or 0 (off).
enum HintLimit {
  unlimited(-1),
  three(3),
  off(0);

  const HintLimit(this.count);
  final int count;
}

@immutable
class AppSettings {
  const AppSettings({
    this.languageFa = true,
    this.themeMode = ThemeMode.system,
    this.boardTheme = BoardTheme.wood,
    this.pieceSet = PieceSet.cburnett,
    this.sound = true,
    this.coordinates = true,
    this.showLegalMoves = true,
    this.highlightLastMove = true,
    this.evalBar = false,
    this.blunderWarning = true,
    this.hintLimit = HintLimit.unlimited,
    this.tips = true,
  });

  final bool languageFa;
  final ThemeMode themeMode;
  final BoardTheme boardTheme;
  final PieceSet pieceSet;
  final bool sound;
  final bool coordinates;
  final bool showLegalMoves;
  final bool highlightLastMove;
  final bool evalBar;
  final bool blunderWarning;
  final HintLimit hintLimit;
  final bool tips;

  AppSettings copyWith({
    bool? languageFa,
    ThemeMode? themeMode,
    BoardTheme? boardTheme,
    PieceSet? pieceSet,
    bool? sound,
    bool? coordinates,
    bool? showLegalMoves,
    bool? highlightLastMove,
    bool? evalBar,
    bool? blunderWarning,
    HintLimit? hintLimit,
    bool? tips,
  }) => AppSettings(
    languageFa: languageFa ?? this.languageFa,
    themeMode: themeMode ?? this.themeMode,
    boardTheme: boardTheme ?? this.boardTheme,
    pieceSet: pieceSet ?? this.pieceSet,
    sound: sound ?? this.sound,
    coordinates: coordinates ?? this.coordinates,
    showLegalMoves: showLegalMoves ?? this.showLegalMoves,
    highlightLastMove: highlightLastMove ?? this.highlightLastMove,
    evalBar: evalBar ?? this.evalBar,
    blunderWarning: blunderWarning ?? this.blunderWarning,
    hintLimit: hintLimit ?? this.hintLimit,
    tips: tips ?? this.tips,
  );

  /// chessground settings derived from the app settings.
  ChessboardSettings boardSettings({
    PieceOrientationBehavior orientation = PieceOrientationBehavior.facingUser,
    bool premoves = false,
  }) => ChessboardSettings(
    colorScheme: boardTheme.scheme,
    pieceAssets: pieceSet.assets,
    enableCoordinates: coordinates,
    showLastMove: highlightLastMove,
    showValidMoves: showLegalMoves,
    enablePremoves: premoves,
    pieceOrientationBehavior: orientation,
  );
}
