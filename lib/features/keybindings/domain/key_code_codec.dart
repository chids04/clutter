import 'package:flutter/services.dart';

import 'package:clutter/features/library/domain/library_entities.dart';
import 'package:clutter/shared/platform/desktop_platform.dart';

class KeyCodeCodec {
  static final Map<String, LogicalKeyboardKey> _keys = {
    'space': LogicalKeyboardKey.space,
    'key_a': LogicalKeyboardKey.keyA,
    'key_b': LogicalKeyboardKey.keyB,
    'key_c': LogicalKeyboardKey.keyC,
    'key_d': LogicalKeyboardKey.keyD,
    'key_e': LogicalKeyboardKey.keyE,
    'key_f': LogicalKeyboardKey.keyF,
    'key_g': LogicalKeyboardKey.keyG,
    'key_h': LogicalKeyboardKey.keyH,
    'key_i': LogicalKeyboardKey.keyI,
    'key_j': LogicalKeyboardKey.keyJ,
    'key_k': LogicalKeyboardKey.keyK,
    'key_l': LogicalKeyboardKey.keyL,
    'key_m': LogicalKeyboardKey.keyM,
    'key_n': LogicalKeyboardKey.keyN,
    'key_o': LogicalKeyboardKey.keyO,
    'key_p': LogicalKeyboardKey.keyP,
    'key_q': LogicalKeyboardKey.keyQ,
    'key_r': LogicalKeyboardKey.keyR,
    'key_s': LogicalKeyboardKey.keyS,
    'key_t': LogicalKeyboardKey.keyT,
    'key_u': LogicalKeyboardKey.keyU,
    'key_v': LogicalKeyboardKey.keyV,
    'key_w': LogicalKeyboardKey.keyW,
    'key_x': LogicalKeyboardKey.keyX,
    'key_y': LogicalKeyboardKey.keyY,
    'key_z': LogicalKeyboardKey.keyZ,
    'digit_0': LogicalKeyboardKey.digit0,
    'digit_1': LogicalKeyboardKey.digit1,
    'digit_2': LogicalKeyboardKey.digit2,
    'digit_3': LogicalKeyboardKey.digit3,
    'digit_4': LogicalKeyboardKey.digit4,
    'digit_5': LogicalKeyboardKey.digit5,
    'digit_6': LogicalKeyboardKey.digit6,
    'digit_7': LogicalKeyboardKey.digit7,
    'digit_8': LogicalKeyboardKey.digit8,
    'digit_9': LogicalKeyboardKey.digit9,
    'arrow_left': LogicalKeyboardKey.arrowLeft,
    'arrow_right': LogicalKeyboardKey.arrowRight,
    'arrow_up': LogicalKeyboardKey.arrowUp,
    'arrow_down': LogicalKeyboardKey.arrowDown,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'page_up': LogicalKeyboardKey.pageUp,
    'page_down': LogicalKeyboardKey.pageDown,
    'enter': LogicalKeyboardKey.enter,
    'tab': LogicalKeyboardKey.tab,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'insert': LogicalKeyboardKey.insert,
    'minus': LogicalKeyboardKey.minus,
    'equal': LogicalKeyboardKey.equal,
    'comma': LogicalKeyboardKey.comma,
    'period': LogicalKeyboardKey.period,
    'slash': LogicalKeyboardKey.slash,
    'semicolon': LogicalKeyboardKey.semicolon,
    'quote': LogicalKeyboardKey.quote,
    'bracket_left': LogicalKeyboardKey.bracketLeft,
    'bracket_right': LogicalKeyboardKey.bracketRight,
    'backslash': LogicalKeyboardKey.backslash,
    'backquote': LogicalKeyboardKey.backquote,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
  };

  static final Map<LogicalKeyboardKey, String> _codes = {
    for (final entry in _keys.entries) entry.value: entry.key,
  };

  static LogicalKeyboardKey? keyForCode(String? code) => _keys[code];

  static String? codeForKey(LogicalKeyboardKey key) => _codes[key];

  static bool isModifier(LogicalKeyboardKey key) => {
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  }.contains(key);

  static KeybindingData? capture(KeybindingAction action, KeyEvent event) {
    final code = codeForKey(event.logicalKey);
    if (code == null || isModifier(event.logicalKey)) return null;
    final hardware = HardwareKeyboard.instance;
    final primary = usesMacPrimaryModifier
        ? hardware.isMetaPressed
        : hardware.isControlPressed;
    return KeybindingData(
      action: action,
      keyCode: code,
      primary: primary,
      control: usesMacPrimaryModifier && hardware.isControlPressed,
      meta: !usesMacPrimaryModifier && hardware.isMetaPressed,
      alt: hardware.isAltPressed,
      shift: hardware.isShiftPressed,
    );
  }

  static bool matches(KeybindingData binding, KeyEvent event) {
    final key = keyForCode(binding.keyCode);
    if (key == null || event.logicalKey != key) return false;
    final hardware = HardwareKeyboard.instance;
    final primaryPressed = usesMacPrimaryModifier
        ? hardware.isMetaPressed
        : hardware.isControlPressed;
    final controlPressed = usesMacPrimaryModifier
        ? hardware.isControlPressed
        : false;
    final metaPressed = usesMacPrimaryModifier ? false : hardware.isMetaPressed;
    return binding.primary == primaryPressed &&
        binding.control == controlPressed &&
        binding.meta == metaPressed &&
        binding.alt == hardware.isAltPressed &&
        binding.shift == hardware.isShiftPressed;
  }

  static String label(KeybindingData binding) {
    if (binding.keyCode == null) return 'unbound';
    final parts = <String>[
      if (binding.primary) usesMacPrimaryModifier ? 'cmd' : 'ctrl',
      if (binding.control) 'ctrl',
      if (binding.meta) 'meta',
      if (binding.alt) usesMacPrimaryModifier ? 'option' : 'alt',
      if (binding.shift) 'shift',
      _keyLabel(binding.keyCode!),
    ];
    return parts.join(' + ');
  }

  static String _keyLabel(String code) {
    if (code.startsWith('key_') || code.startsWith('digit_')) {
      return code.substring(code.indexOf('_') + 1);
    }
    return code.replaceAll('_', ' ');
  }
}
