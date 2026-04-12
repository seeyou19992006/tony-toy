import Foundation
import CryptoKit

// MARK: - 加密服务

class VaultCryptoService {
    /// 加密
    func encrypt(_ data: Data, keyData: Data, nonce: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: aesNonce)
        guard let combined = sealedBox.combined else {
            throw VaultError.encryptionFailed
        }
        return combined
    }
    
    /// 解密
    func decrypt(_ data: Data, keyData: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
