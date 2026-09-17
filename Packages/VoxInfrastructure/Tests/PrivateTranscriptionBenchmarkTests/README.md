# 私密样本识别实验

MY-1544 的独立实验框架；只在明确获准的当前 Mac 执行。不改变 App、默认模型或发布设置。

## 运行边界

- 默认所有私密实验跳过；`BenchmarkContractTests` 只使用合成数据。
- 手动执行前须有明确音频/现有云端服务授权，测试代码已审查合并；不得在 CI 设置 opt-in。
- 样本位于当前用户 App 沙箱 `benchmarks/owner-20260910`，目录 0700，普通文件 0600，无符号链接。
- 清单包含 `audio_file`（固定 `sample.m4a`）、`reference_text`、`locale`、`duration_seconds`、`cold_runs=1`、`warm_runs=5`。
- 参考正文只供评分；识别、合并、精炼输入只来自音频/本轮识别结果。
- 不打印私密文件、供应商错误体或配置。只查看 `summary-*.json` 数值投影，完整文本保留在 `private-*.json`。
- `VOX_BENCHMARK_OUTPUT` 必须是样本目录内新建的 0700 子目录；文件用 O_EXCL/0600 创建，不覆盖历史结果。

## 顺序

先运行 `swift test --package-path Packages/VoxInfrastructure --filter BenchmarkContractTests`，再运行本层全量 build/test。
真实实验使用 `--filter ApprovedOwnerBenchmarkTests/testApprovedOwnerRun`，每组调用一个新的 `swift test` 进程。

显式传入环境：

- `VOX_BENCHMARK_OPT_IN=approved-owner-sample`
- `VOX_BENCHMARK_ROOT`：已授权样本目录
- `VOX_BENCHMARK_OUTPUT`：本轮新建结果目录
- `VOX_BENCHMARK_SHA`：实际已审查源码的完整 commit SHA
- `VOX_BENCHMARK_GROUP`：先 `prepare`，再依次 `appleAutomatic`、`appleOnDevice`、`azure`、`localBase`、`localTurbo`、`hybridAzure`、`hybridBase`、`hybridTurbo`

`prepare` 只做一次规范化：单声道 16kHz PCM16 WAV；Apple 缓冲从同一 WAV 解码。加载/转换在识别计时外。
每个可用组新进程/新适配器冷运行一次，再复用同一引擎热运行五次，串行执行，不输出 p95。
模型只取现有标准 WhisperKit 缓存；缺失明确记录 `missingModel`，不自动下载、清理缓存或回退。
Apple 只检查已有授权，不发起系统权限请求。不可用时记录固定状态，不能伪装为另一条路径成功。

## 结果口径与限制

- Apple 按 1x 速度提交 PCM，`firstPartialSeconds` 只统计非 final 结果；实际服务路由始终 `unknown`。
- Azure/本地文件转写是 batch，没有 first-partial；`requestSeconds` 与 Apple 总时间不能直接排名。
- `totalSeconds` 不含初始化；`preparationSeconds` 是该组初始化总耗时；`loadSeconds` 单独计本地模型加载，没有本地模型时为 N/A。
- 混合组组合真实 Apple 请求、生产文件引擎、`mergedTranscription`/`LLMTranscriptionMerger`、生产精炼服务。
  顺序为实时输入完成 → 文件 ASR → 合并 → 精炼；不是 UI/麦克风端到端性能或流式精炼重叠的测量。
- 纯 ASR 不精炼；混合组固定跳过前置分析，分别保存 ASR、合并、精炼评分和阶段耗时。
- 云端配置仅用生产私密配置加载器读取现有配置文件（无进程环境覆盖）；不根据部署别名猜实际 backing model。
- CER 使用 NFKC、小写、去空白/标点；混合 token 指汉字逐字、ASCII 英文/数字按词。
- 标点指标是标点序列编辑次数及参考数量，**不评价标点插入位置**；英文 `test` 按独立词元检查。
- 单段音频只能支持个案结论；Apple 权限、缓存、版本、下载状态、热冷定义必须随结果披露。

LokiKit 固定 `eff9c1712cd648ed0717e41183ad8bd7bf39cbea`；SPM 实际解析版本需随运行记录。
