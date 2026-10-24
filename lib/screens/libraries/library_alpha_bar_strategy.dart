import '../../media/library_first_character.dart';
import 'alpha_jump_helper.dart';

/// Alpha-jump-bar behaviour.
///
/// Silo has no per-letter count endpoint. The bar synthesises the 27-letter
/// alphabet (`#`, `A`–`Z`) and acts as a name-prefix filter that refetches
/// the page when the user picks a letter.
class LibraryAlphaBarStrategy {
  static const _letters = [
    '#',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
  ];

  const LibraryAlphaBarStrategy();

  /// Whether the bar should be rendered at all.
  bool shouldShow({
    required int totalItemCount,
    required int loadedCharacterCount,
    required String? sortKey,
    required bool isFolderGrouping,
    required String? alphaPrefix,
    required bool isPhone,
  }) {
    if (isPhone) return false;
    if (isFolderGrouping) return false;
    if (loadedCharacterCount == 0) return false;
    return totalItemCount >= 80 || alphaPrefix != null;
  }

  /// The synthesised letter buckets plus their helper — the caller stores
  /// both in widget state.
  Future<({List<LibraryFirstCharacter> chars, AlphaJumpHelper helper})> loadCharacters({
    required bool descending,
  }) async {
    final synthetic = [for (final l in _letters) LibraryFirstCharacter(key: l, title: l, size: 1)];
    return (chars: synthetic, helper: AlphaJumpHelper(synthetic, descending: descending));
  }

  /// Letter to highlight: whatever filter is active.
  String currentLetter(int index, AlphaJumpHelper helper, {String? alphaPrefix}) => alphaPrefix ?? '';

  /// Handle a tap on the letter at [targetIndex]. We map the bar offset back to a letter (the synthesised `size: 1` entries
  /// make offset == position in [helper.letters]) and toggle the filter —
  /// re-tap the active letter to clear, otherwise set the new prefix.
  void onLetterPressed(
    int targetIndex,
    AlphaJumpHelper helper, {
    required String? currentPrefix,
    required void Function(String? nextPrefix) onPrefixChange,
  }) {
    if (targetIndex < 0 || targetIndex >= helper.letters.length) return;
    final letter = helper.letters[targetIndex];
    final next = (currentPrefix == letter) ? null : letter;
    onPrefixChange(next);
  }
}
