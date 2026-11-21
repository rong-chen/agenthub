/// 应用环境类型
enum AppEnvironment {
  dev,
  prod,
}

/// 全局运行环境配置管理
class AppEnv {
  static AppEnvironment _current = _detectEnvironment();

  /// 获取当前运行环境
  static AppEnvironment get current => _current;

  /// 设置当前运行环境
  static void setEnvironment(AppEnvironment env) {
    _current = env;
  }

  /// 是否为开发环境
  static bool get isDev => _current == AppEnvironment.dev;

  /// 是否为生产环境
  static bool get isProd => _current == AppEnvironment.prod;

  /// 依据编译参数或环境配置检测环境
  static AppEnvironment _detectEnvironment() {
    const envStr = String.fromEnvironment('ENV', defaultValue: 'prod');
    if (envStr.toLowerCase() == 'dev' || envStr.toLowerCase() == 'development') {
      return AppEnvironment.dev;
    }
    return AppEnvironment.prod;
  }

  /// 窗口标题
  static String get appTitle => isDev ? 'AgentHub (Dev)' : 'AgentHub';

  /// 本地数据库文件名（开发与生产数据物理隔离）
  static String get dbFileName => isDev ? 'agenthub_dev.db' : 'agenthub.db';

  /// 本地网关默认端口
  static int get defaultGatewayPort => isDev ? 18790 : 18789;

  /// 单实例应用互斥锁端口（本地回环）
  static int get singleInstancePort => isDev ? 39282 : 39281;
}
