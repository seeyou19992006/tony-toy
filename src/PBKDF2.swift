import Foundation
import CommonCrypto

/// 使用 CommonCrypto 实现 PBKDF2
func pbkdf2(password: String, salt: Data, keyByteCount: Int = 32, rounds: Int = 100_000) -> Data {
    var derivedKeyBytes = [UInt8](repeating: 0, count: keyByteCount)
    let keyByteCountUInt32 = UInt32(keyByteCount)

    // 将 Swift String 转换为 C 字符串
    guard let passwordCString = password.cString(using: .utf8) else {
        fatalError("PBKDF2 密码转换失败")
    }

    let result = salt.withUnsafeBytes { saltPtr in
        CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordCString,                // 使用 C 字符串
            passwordCString.count - 1,     // strlen（不含终止符）
            saltPtr.bindMemory(to: UInt8.self).baseAddress!,
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(rounds),
            &derivedKeyBytes,
            Int(keyByteCountUInt32)
        )
    }

    guard result == kCCSuccess else {
        fatalError("PBKDF2 密钥派生失败: \(result)")
    }

    return Data(derivedKeyBytes)
}
