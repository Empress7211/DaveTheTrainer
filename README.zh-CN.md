# DaveTheTrainer

<p align="center">
  <img src="Assets/AppIcon/DaveTheTrainerIcon.png" width="144" alt="DaveTheTrainer 应用图标">
</p>

<p align="center">
  面向 macOS 版 <code>DAVE THE DIVER</code> 的 manifest 驱动修改器。
</p>

<p align="center">
  <a href="README.md">English README</a> ·
  <a href="https://github.com/Empress7211/DaveTheTrainer/releases/latest">下载最新版</a>
</p>

DaveTheTrainer 是一个原生 macOS SwiftUI 修改器。它不是通用内存扫描器，也不是
Cheat Engine 风格工具。玩家按钮都绑定到已审查的 manifest feature、已验证的
Mach-O 模块形态、确定的补丁点或运行时对象路径。安装路径可以变化，但玩家内存写入
必须匹配经过审核的精确构建 profile。`v1.0.6.675.mac` 是完整验证的 profile，
`v1.0.6.710.mac` 是根据 issue #2 报告建立的部分兼容 profile，
`v1.0.6.756.mac` 已补齐全部 22 个控件的精确 profile；完整游戏效果仍待实测，写入默认关闭，需明确开启实验功能。

> 本项目与 MINTROCKET、Nexon 或 `DAVE THE DIVER` 创作者没有隶属、赞助、
> 背书或官方合作关系。

## 项目状态

| 项目 | 状态 |
| --- | --- |
| 平台 | macOS |
| 应用类型 | 原生 SwiftUI app |
| 包管理 | Swift Package Manager |
| 已验证基线版本 | `v1.0.6.675.mac` |
| 证据支持的部分版本 | `v1.0.6.710.mac` |
| 实验 profile，默认禁止写入 | `v1.0.6.756.mac`；全部控件已适配，游戏实测待完成 |
| 目标模块 | `GameAssembly.dylib` |
| Manifest schema | `1.0` |
| 测试 | 覆盖 manifest 策略、事务补丁、运行时增量、发布脚本和玩家路径契约 |
| 协议 | MIT |

## 下载和安装

预构建 `.app` zip 发布在
[GitHub Releases](https://github.com/Empress7211/DaveTheTrainer/releases)。

当前 Release 包是 ad-hoc signed，未经过 Apple notarization。因此 macOS 首次
打开时可能提示“无法验证开发者”或阻止启动。请先阅读源码和 Release notes，再决定是否运行。

安装步骤：

1. 从最新 Release 下载 `DaveTheTrainer-v0.1.5-macOS.zip`。
2. 解压 zip。
3. 把 `DaveTheTrainer.app` 移动到 `/Applications` 或 `$HOME/Applications`。
4. 启动 macOS 版 `DAVE THE DIVER`。
5. 打开 `DaveTheTrainer.app`。

如果 Gatekeeper 阻止首次启动，优先使用 Finder 右键 `Open` 流程。如果你已经审查并信任该下载包，也可以移除 quarantine：

```bash
xattr -dr com.apple.quarantine /Applications/DaveTheTrainer.app
```

## 兼容性边界

当前仓库完整验证的 profile 是 `v1.0.6.675.mac`。修改器可以从运行进程识别 Steam
自定义库、任意安装目录和独立 Unity app bundle，但安装路径兼容不代表固定补丁 RVA
可以跨游戏更新复用。

| 游戏构建 | 覆盖范围 |
| --- | --- |
| `v1.0.6.675.mac` | 完整基线 profile |
| `v1.0.6.710.mac` | 72 个精确目标，覆盖无敌、氧气、弹药、鱼笼、负重、部分移动速度、无人机、体力和芥末；其他控件禁用 |
| `v1.0.6.756.mac` | 22 个控件的实验 profile；101 个代码目标及新版货币、库存字段路径；默认禁止写入 |

`.710` 目标已与用户报告中的 GameAssembly 字节证据逐点核对，并绑定其精确 UUID。
由于维护者本机没有该版本，尚未完成实际游戏行为验证。请逐项测试已启用功能，不要把
`bytesApplied` 等同于游戏内效果已确认。详见 [兼容证据说明](docs/compatibility-v1.0.6.710.mac.md)。

`.756` 已在本地 arm64 二进制上核对全部 101 个代码目标窗口和 RPG 跳板空间，
资源功能采用新版 metadata 字段布局。备份存档后，在页面明确开启“启用 .756 实验功能”
才允许写入；该开关每次启动默认关闭，且不能绕过精确版本或模块校验。恢复代码补丁不受该开关阻止。
完整潜水、战斗、寿司店效果及有库存时的素材修改仍待实测。
详见 [v1.0.6.756.mac 兼容证据](docs/compatibility-v1.0.6.756.mac.md)。

玩家内存写入必须精确匹配 manifest 中的 bundle ID、版本、build GUID 和 GameAssembly
arm64 UUID。未知构建仍可被识别并用于诊断，但会在读取或修改旧 RVA 前拒绝玩家写入。
点击“导出兼容报告”可在本地生成 JSON，为新增精确版本 profile 提供证据。该操作必须
由用户主动触发，应用不会自动上传报告。

## 功能范围

当前面向玩家的功能包括：

- 潜水补丁：无敌、氧气、弹药、螃蟹陷阱、负重、伤害、无人机、游速。
- 货币：金币、贝、丛林金币、匠人火焰。
- 背包：主线食材、分类食材、丛林 DLC 已有物品、鲛人村/丛林村庄已有物品。
- 寿司店：体力和芥末相关补丁。

背包功能默认只修改已有条目，除非 manifest 明确声明支持创建条目。缺失根对象、
缺失条目、目标不匹配和写后校验失败都会显式失败，不会假装成功。

## 使用方式

1. 先启动 macOS 版 `DAVE THE DIVER`。
2. 启动 `DaveTheTrainer`。
3. 确认修改器检测到游戏进程和 build fingerprint。
4. 如果提示构建不支持，点击“导出兼容报告”，把 JSON 附到兼容性 issue；此时不会执行玩家写入。
5. 在部分 profile 上，没有精确证据的控件会被禁用；请逐项测试可用功能，不要使用组合模式。
6. 在受支持构建上，只点击你确实要使用的一键功能。
7. 如果 macOS 请求管理员权限，请确认它只用于目标进程 attach/read/write 操作。

修改器会优先从正在运行的游戏进程反向定位实际 `.app`，因此支持 Steam 自定义库、
非 `/Applications` 安装目录和直接运行的 Unity app bundle。进程只按名称找到时仍只是候选；
attach 前必须继续通过 `CFBundleExecutable`、`com.nexon.dave`、IL2CPP metadata 和
`GameAssembly.dylib` 校验。只有游戏未运行时，才会检查默认的
`/Applications/DaveTheDiver.app`。

界面显示 `Install Not Resolved` 表示进程已找到，但其 app bundle 未通过上述安装校验；
这与 `Game Not Running` 不同，也不代表版本号本身不受支持。

当游戏未运行、构建或目标模块不匹配已审核 profile、功能目标校验失败、权限被拒绝或
写后校验失败时，应用会明确报错。

## 权限和隐私

DaveTheTrainer 会修改本机正在运行的游戏进程。macOS 可能要求管理员授权，
用于 task access 和进程内存读写。

应用不会上传 telemetry、内存 dump、存档、API key、崩溃日志或诊断信息。兼容报告只会
在用户点击后写成本地 JSON，其中包含构建指纹和定向的 manifest 目标字节，不含绝对路径和
完整提取符号名。其他日志或手工收集的数据在公开前仍应脱敏。

如果已显示 `Admin: Enabled`，但仍报 `task_for_pid ... failure (5)`，可能是游戏
的 Hardened Runtime 签名未允许调试附加。修改器现在会识别并说明这类拦截；
重复输入管理员密码不能解除目标的签名保护。要保持从 Steam 正常启动的使用方式，可先明确授权为
Steam 原包准备调试权限；此操作会更改本机签名，必须先保留完整原包备份。游戏模块、资源和存档不变。
独立副本仍可用于可选调试验证。步骤与恢复说明见下方权限文档。

详细说明见 [Permissions And Privacy](docs/permissions-and-privacy.md)。

## 从源码构建

```bash
git clone https://github.com/Empress7211/DaveTheTrainer.git
cd DaveTheTrainer
swift test
./script/build_and_run.sh
```

`script/build_and_run.sh` 会构建 SwiftPM executable，生成真实的
`DaveTheTrainer.app` bundle，签名，复制到
`${DAVE_TRAINER_LOCAL_APP_DIR:-$HOME/Applications}`，同时在 `dist/` 下生成
`DaveTheTrainer-v0.1.5-macOS.zip`。

GitHub Actions 运行公开测试套件，并跳过需要本机游戏安装或专有游戏文件的测试：

```bash
python3 -m unittest discover -s script/tests -v
swift test \
  --skip InstalledGameIntegrationTests \
  --skip Il2CppFeatureLocatorTests \
  --skip MachOModuleResolverTests
```

本机如果安装了基线游戏文件，可以运行完整测试：

```bash
swift test
```

## 项目结构

```text
Sources/
  DaveTrainerApp/      SwiftUI 应用、状态、视图和展示逻辑
  TrainerCore/         Manifest、补丁、扫描、运行时和存档服务
  MachMemory/          Mach task memory C bridge
Tests/
  DaveTrainerAppTests/ 玩家路径、发布脚本和 app service 契约测试
  TrainerCoreTests/    核心补丁、manifest、scanner 和 runtime 测试
docs/                  公开策略、发布和能力说明
script/                构建、发布和 legacy admin helper 脚本
Assets/                应用图标资源
```

## 开发原则

- Manifest first：玩家按钮映射到已审查的 manifest feature ID。
- 精确 profile 写入：玩家操作开始前必须匹配构建身份和 GameAssembly UUID。
- 证据驱动兼容：未知 build 通过显式本地报告收集目标证据，不在玩家路径猜测新地址。
- 不做静默 fallback：失败必须通过错误、日志或测试暴露。
- 事务式补丁：多点补丁先 preflight，再提交，失败时 rollback。
- 写后校验：运行时数值写入必须读回确认。
- 公开边界：不要提交游戏二进制、memory dump、存档 fixture、日志或签名材料。

## 文档

- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Changelog](CHANGELOG.md)
- [Release Checklist](docs/release-checklist.md)
- [Resource Capabilities](docs/resource-capabilities.md)
- [Inventory Taxonomy](docs/inventory-taxonomy.md)
- [Development Fixtures](docs/development-fixtures.md)
- [v1.0.6.710.mac 兼容证据](docs/compatibility-v1.0.6.710.mac.md)

## License

DaveTheTrainer 使用 [MIT License](LICENSE) 发布。
