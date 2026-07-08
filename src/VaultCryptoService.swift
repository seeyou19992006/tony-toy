import Foundation
import CryptoKit

// MARK: - 加密服务

class VaultCryptoService {
    /// 加密：返回 ciphertext + tag（不含 nonce，nonce 由调用方单独存储）
    func encrypt(_ data: Data, keyData: Data, nonce: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: aesNonce)
        // sealedBox.ciphertext + sealedBox.tag，不含 nonce
        return sealedBox.ciphertext + sealedBox.tag
    }

    /// 解密：接收 ciphertext + tag，配合独立 nonce 还原明文
    func decrypt(_ data: Data, keyData: Data, nonce: Data) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let aesNonce = try AES.GCM.Nonce(data: nonce)
        // 从 data 拆出 ciphertext 和 tag（tag 固定 16 字节，在末尾）
        let tagLength = 16
        guard data.count > tagLength else {
            throw VaultError.encryptionFailed
        }
        let ciphertext = data.prefix(data.count - tagLength)
        let tag = data.suffix(tagLength)
        let sealedBox = try AES.GCM.SealedBox(nonce: aesNonce,
                                              ciphertext: ciphertext,
                                              tag: tag)
        return try AES.GCM.open(sealedBox, using: key)
    }
}
