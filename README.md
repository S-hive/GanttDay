# GanttDay

<p align="center">
  <img src="logo.png" alt="GanttDay logo" width="128" />
</p>

<p align="center">
  <strong>Windows 个人甘特日程</strong> — 在时间线上看到什么时候做什么。
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white" alt="Flutter" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white" alt="Dart" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/platform-Windows-0078D6?logo=windows&logoColor=white" alt="Windows" />
  <img src="https://img.shields.io/badge/storage-local%20SQLite-lightgrey" alt="Local SQLite" />
</p>

English: A local-first personal Gantt scheduler for Windows, built with Flutter. No account, no cloud.

---

## 目录

- [简介](#简介)
- [功能](#功能)
- [界面与操作](#界面与操作)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [数据与备份](#数据与备份)
- [项目结构](#项目结构)
- [已知限制](#已知限制)
- [许可证](#许可证)

## 简介

GanttDay 把一天、一周、一个月画成横向甘特图：任务是时间轴上的色条，而不是日历格子里的一行字。适合需要对照「计划 vs 实际」的个人日程，数据全部存在本机 SQLite，不经过任何服务器。

| | |
| --- | --- |
| 平台 | Windows 桌面（Flutter） |
| 版本 | 1.0.0 |
| 存储 | 本机 SQLite（`gantday.db`） |
| 同步 | 无；换机器请导出 JSON |
| 许可 | [MIT](LICENSE) |
| 仓库 | [github.com/S-hive/GanttDay](https://github.com/S-hive/GanttDay) |

<img width="1280" height="747" alt="Snipaste_2026-09-04_20-08-50" src="https://github.com/user-attachments/assets/228e0422-dede-4e48-a967-4109cddc03f2" />
<img width="1280" height="747" alt="Snipaste_2026-09-04_20-06-21" src="https://github.com/user-attachments/assets/74fd3b4a-c25f-4f46-975f-f8fdda2ad2d3" />
<img width="1280" height="747" alt="Snipaste_2026-09-04_20-05-24" src="https://github.com/user-attachments/assets/2f9ccb7c-88fe-4c6a-93af-97b05d8b6d01" />

## 功能

- **日 / 周 / 月视图**  
  底部三等分导航切换。日视图为横向小时网格，任务条按重叠自动分行；周视图按天分列；月视图用跨日色条铺在日历格上。

- **时间轴交互（日视图）**  
  拖动色条移动或缩放计划时间；空白处长按拖拽创建任务；短拖空白区域平移时间轴。时间吸附 **15 分钟**，最短时长 15 分钟。

- **计划 vs 实际**  
  右键色条打开完成对话框，在迷你日轴上圈出实际用时。完成后：计划条置灰，实际条按任务颜色叠在上面。未完成且已逾期的计划条同样置灰。可再次右键实际条取消完成。

- **标签**  
  任务可挂 **一个** 标签（决定颜色，除非覆盖）。

- **默认色**  
  设置里 **标签** 与 **默认色** 分开管理，色块 60×30 直角。主题主色跟随当前默认色。任务可单独覆盖 ARGB（色值拷贝，不绑表）。

- **本机优先**  
  无账号、无云同步、无遥测。数据库打不开时会提示备份损坏文件后再重建，不会静默清空。

- **备份**  
  设置页导出 / 导入 JSON（当前备份格式 version **3**），包含任务、标签、默认色与设置。导入时校验结构，重复任务会跳过。也可以导入旧的 version 1 / 2。

## 界面与操作

| 操作 | 说明 |
| --- | --- |
| 底部导航 | 日 / 周 / 月 |
| 日视图：拖动色条 | 移动整段计划，或拖两端缩放 |
| 日视图：空白长按拖拽 | 框出时间范围并创建任务 |
| 单击色条 | 右侧抽屉打开任务表单（标题、计划时间、一个标签、覆盖色、备注） |
| 右键色条 | 完成对话框：圈选实际起止；已完成任务可右****键实际条取消完成 |
| 设置（侧栏） | 标签、默认色、导出 / 导入 |

任务表单在右侧抽屉中打开（约屏宽 40%，夹在 360–480px）。计划时间支持行内编辑，同样按 15 分钟吸附。

## 环境要求

- [Flutter](https://docs.flutter.dev/get-started/install) 稳定版，并启用 **Windows desktop**
- Dart SDK `^3.12.2`（见 `pubspec.yaml`）
- Windows 上构建需要 Visual Studio 的 **Desktop development with C++** 工作负载

确认桌面支持：

```bash
flutter doctor
flutter config --enable-windows-desktop
```

## 快速开始

```bash
git clone https://github.com/S-hive/GanttDay.git
cd GanttDay
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

可执行文件在 `build/windows/x64/runner/Release/`。

> Windows 无障碍树在密集甘特 UI 上容易损坏。首次安装后若热重启异常，请结束进程（Ctrl+C）后重新 `flutter run`，不要只依赖 hot restart。

## 数据与备份

- 数据库路径：应用支持目录下的 `gantday.db`（由 `path_provider` 的 `getApplicationSupportDirectory()` 决定）
- **设置 → 导出**：写出 `gantday-backup.json`（任务、标签、默认色、可视时段等）
- **设置 → 导入**：校验后合并；重复任务跳过，不会覆盖已有 id
- **没有**多端同步。换电脑请先导出 JSON，再在新机器导入
- 库文件损坏时，应用会提示将原文件重命名为 `gantday.db.corrupt-<时间戳>` 后再开新库

设计规格与演进记录见 [`docs/superpowers/`](docs/superpowers/)。

## 项目结构

```
lib/
  main.dart                 # 启动、打开 SQLite、Windows 安全绑定
  app.dart                  # 服务注入与主题（跟随当前默认色）
  domain/                   # 纯逻辑：任务/标签/默认色、甘特几何、完成轴
  data/                     # SQLite 仓储、备份 JSON、Windows 文件选择
  platform/                 # 仓储与设置接口（便于测试替换）
  ui/
    day/                    # 日甘特：绘制、手势、时间标签
    week/                   # 周视图
    month/                  # 月视图与跨日条
    task/                   # 任务表单
    complete/               # 完成对话框
    settings/               # 标签、默认色、备份
    shell/                  # 底栏导航与总壳
    common/                 # 侧栏抽屉、60×30 色块、取色器等
test/                       # 领域、数据、部分 UI 逻辑测试
windows/                    # Flutter Windows 工程
docs/superpowers/           # 规格与实现计划
```

领域层（`lib/domain`）不依赖 Flutter Widget，时间用整型「墙钟分钟」`WallMinutes` 表示，便于单测。

## 已知限制

当前版本面向单人本机使用，以下能力不在范围内：

- 仅 Windows，未适配 macOS / Linux / 移动端
- 无系统通知、无云同步、无多人协作
- 不读写系统日历（Outlook / Google Calendar 等）
- 无任务依赖、里程碑或资源负载
- 设置中的「紧迫窗口」字段仍会保存，着色逻辑已不再使用该值

## 许可证

[MIT](LICENSE) © 2026 S-hive
