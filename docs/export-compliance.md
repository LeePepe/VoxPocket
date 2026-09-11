# TestFlight 出口合规声明

核对日期：2026-09-11。适用于当前 macOS / iOS 主 App，使用共享的
`VoxPocket/VoxPocket/Info.plist`（Debug / Release 均引用该文件）。

## 声明依据

`ITSAppUsesNonExemptEncryption` 为布尔 `false`，表示当前 App 不使用非豁免加密，
不是声称完全不使用密码技术。未填写 Apple 未签发的 `ITSEncryptionExportComplianceCode`。

- 转写、精炼、遥测和模型下载通过系统网络 API（`URLSession` / HTTPS）通信。
- TelemetryDeck SwiftSDK 2.12.0 的 `Helpers/CryptoHashing.swift` 用系统
  CryptoKit / CommonCrypto 的 SHA-256 对遥测用户标识做哈希。
- WhisperKit 0.16.0 引入 swift-transformers 1.1.9；其
  `Sources/Hub/HubApi.swift` 用 SHA-256 校验下载文件完整性。
- swift-crypto 4.2.0 的 `Crypto` 产品在 Apple 平台使用系统 CryptoKit；
  默认包配置不在这些平台启用 BoringSSL 后端。
- 当前业务代码及所核对的运行时依赖中未发现自定义加密、VPN 或端到端加密功能。

新增密码功能、改变依赖或加密实现后必须重新核对；本声明不替代适用的其他出口报告义务。

## 验证

```bash
python3 scripts/tests/test_export_compliance.py
python3 scripts/tests/test_export_compliance.py /path/to/VoxPocket.app/Contents/Info.plist
```

iOS 包使用 `/path/to/VoxPocket.app/Info.plist`。检查声明存在且为布尔 `false`，
并确保没有填入未签发的合规代码。

此修改只影响以后构建和上传的包。已上传 build 仍需在 App Store Connect 对应 build
的出口合规页面完成问卷；本地改 plist 不会更新远端已有 build。

## Apple 参考

- [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)
- [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)
