# GanttDay

<p align="center">
  <img src="logo.png" alt="GanttDay logo" width="120" />
</p>

**Windows 个人甘特日程** — 在时间线上看到什么时候做什么。

English: A local-first personal Gantt day scheduler for Windows (Flutter).

## 功能

- **日 / 周 / 月**视图：横向时间轴，小时网格，15 分钟吸附
- **标签**分类与过滤（主标签决定基础色）
- **紧迫度着色**：越接近计划结束越鲜艳；逾期有斜纹标记
- **完成对照**：计划条置灰 + 实际用时条叠合显示
- **本机存储**：SQLite，无账号、无云同步
- **备份**：设置里导出 / 导入 JSON

## 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install)（稳定版，启用 Windows desktop）
- Windows 上构建需要 Visual Studio 的 **Desktop development with C++** 工作负载

## 开发

```bash
git clone git@github.com:S-hive/clock.git
cd clock
flutter pub get
flutter run -d windows
```

运行测试：

```bash
flutter test
```

Release 构建：

```bash
flutter build windows --release
```

产物在 `build/windows/x64/runner/Release/`。

## 数据与备份

- 数据保存在本机应用支持目录中的 SQLite 数据库
- **设置 → 导出 / 导入** 可备份或迁移全部任务、标签与设置
- **没有**多端同步；换电脑请用导出的 JSON

设计规格见：[docs/superpowers/specs/2026-08-08-gantday-design.md](docs/superpowers/specs/2026-08-08-gantday-design.md)

## 已知限制（v1）

- 仅 Windows
- 单人纯本机，无提醒通知、无云同步、无多人协作
- 无系统日历读写、无任务依赖 / 里程碑

## License

[MIT](LICENSE)
