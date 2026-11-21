import 'config/app_env.dart';
import 'main.dart';

/// 开发环境独立入口
/// 运行命令: flutter run -d macos -t lib/main_dev.dart
void main() async {
  await startApp(environment: AppEnvironment.dev);
}
