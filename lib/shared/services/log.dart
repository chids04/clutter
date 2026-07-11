import 'package:logger/logger.dart';

class Log {
  static final logger = Logger(
    printer: PrettyPrinter(
      methodCount: 1,
      errorMethodCount: 8,
      lineLength: 80,
      colors: true,
      printEmojis: true,
      stackTraceBeginIndex: 2,
    ),
  );

  static void d(dynamic message) => logger.d(message);
  static void i(dynamic message) => logger.i(message);
  static void w(dynamic message) => logger.w(message);
  static void e(dynamic message, [dynamic error, StackTrace? st]) =>
      logger.e(message, error: error, stackTrace: st);
}
