import 'config/app_env.dart';
import 'main.dart';

/// 生产环境独立入口
/// 运行命令: flutter run -d macos -t lib/main_prod.dart
void main() async {
  await startApp(environment: AppEnvironment.prod);
}
