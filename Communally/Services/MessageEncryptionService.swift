//
//  MessageEncryptionService.swift
//  Communally
//
//  AES-GCM encryption for messages stored in Firestore.
//  Protects message content from Firestore data breaches — Communally holds the key
//  so moderation and safety review remain possible.
//

import Foundation
import CryptoKit

enum MessageEncryptionService {

    // 256-bit symmetric key. All app instances share this key (Option A / at-rest encryption).
    // Never log or transmit this value.
    private static let keyBytes: [UInt8] = [
        0x2c, 0xe2, 0x24, 0xeb, 0xf9, 0x70, 0x92, 0x8b,
        0x2a, 0x09, 0xb3, 0xe2, 0x62, 0x1b, 0x50, 0x60,
        0xc1, 0xab, 0xbc, 0xa7, 0x68, 0x7a, 0xbd, 0x0b,
        0x8b, 0x2f, 0x10, 0x30, 0x64, 0x69, 0x8f, 0xc9
    ]

    private static let key = SymmetricKey(data: Data(keyBytes))

    /// Encrypts plaintext and returns a base64-encoded AES-GCM combined blob (nonce + ciphertext + tag).
    /// Returns the original string unchanged if encryption fails (safe fallback).
    static func encrypt(_ plaintext: String) -> String {
        guard let data = plaintext.data(using: .utf8) else { return plaintext }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return plaintext }
            return combined.base64EncodedString()
        } catch {
            return plaintext
        }
    }

    /// Decrypts a base64-encoded AES-GCM blob and returns plaintext.
    /// Falls back to returning the input unchanged — handles pre-encryption legacy messages gracefully.
    static func decrypt(_ ciphertext: String) -> String {
        guard let data = Data(base64Encoded: ciphertext) else { return ciphertext }
        do {
            let sealed = try AES.GCM.SealedBox(combined: data)
            let decrypted = try AES.GCM.open(sealed, using: key)
            return String(data: decrypted, encoding: .utf8) ?? ciphertext
        } catch {
            // Not an encrypted blob (legacy plaintext message) — return as-is.
            return ciphertext
        }
    }
}
