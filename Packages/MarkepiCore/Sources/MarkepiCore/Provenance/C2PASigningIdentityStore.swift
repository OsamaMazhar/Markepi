import Foundation
import Security

/// A LOCAL device signing identity. NOT a verified legal/person identity (D-24).
///
/// Created by `C2PASigningIdentityStore`: Secure Enclave-backed keys are
/// preferred on real iOS devices; a local Keychain software identity is used
/// only when the Secure Enclave is unavailable (simulator/development).
/// Secure Enclave private keys are non-exportable by construction.
///
/// `SecKey` is a CoreFoundation reference type that is not marked `Sendable`
/// in Swift 6. The key is only ever used from the C2PA client actor boundary
/// (or the no-op path), so we mark the struct `@unchecked Sendable` to carry
/// it across isolation domains without weakening the adapter contract.
public struct C2PASigningIdentity: @unchecked Sendable {
    /// Receipt-safe identity type for audit/display (D-24).
    public enum IdentityType: String, Codable, Sendable {
        case secureEnclave
        case localSoftware
        case unsupported

        public var isUsableForSigning: Bool {
            self != .unsupported
        }
    }

    public let type: IdentityType

    /// Receipt-safe wording mandated by D-24. Never describes a verified
    /// legal/person identity.
    public var displayName: String { "Markepi device signing identity" }

    /// Private key handle; Secure Enclave keys are non-exportable by
    /// construction. nil when the platform offers no usable signing key.
    public let secKey: SecKey?

    public init(type: IdentityType, secKey: SecKey? = nil) {
        self.type = type
        self.secKey = secKey
    }
}

/// Creates/loads a signing key: Secure Enclave first, local Keychain software
/// fallback only when the SE is unavailable (simulator/dev) — D-24. No network
/// call is required to create or use the default signing identity.
///
/// Never exports Secure Enclave private key material. Never describes either
/// local identity as a verified legal/person identity.
public struct C2PASigningIdentityStore: Sendable {
    private static let secureEnclaveTag = "com.osamamazhar.markepi.c2pa.signing.secure-enclave".data(using: .utf8)!
    private static let softwareTag = "com.osamamazhar.markepi.c2pa.signing.software".data(using: .utf8)!

    public init() {}

    /// Returns the best available local signing identity on this device.
    ///
    /// Resolution order:
    ///   1. Secure Enclave-backed EC P-256 key (real device only)
    ///   2. Local Keychain software EC P-256 key (simulator/dev fallback)
    ///   3. Ephemeral in-memory EC P-256 key (keychain unavailable — e.g.
    ///      locked device edge cases or test runners). Not persisted, so the
    ///      identity rotates per process, but signing still succeeds — exports
    ///      must never silently drop Content Credentials just because the key
    ///      couldn't be stored (the certs are self-signed either way).
    ///   4. `.unsupported` when no key can be created at all
    public func currentIdentity() -> C2PASigningIdentity {
        if let key = makeKey(secureEnclave: true) {
            return C2PASigningIdentity(type: .secureEnclave, secKey: key)
        }
        if let key = makeKey(secureEnclave: false) {
            return C2PASigningIdentity(type: .localSoftware, secKey: key)
        }
        if let key = makeEphemeralKey() {
            return C2PASigningIdentity(type: .localSoftware, secKey: key)
        }
        return C2PASigningIdentity(type: .unsupported, secKey: nil)
    }

    /// Creates a random EC P-256 key. When `secureEnclave` is true, the key is
    /// bound to the Secure Enclave (non-exportable). On the Simulator the SE
    /// token is unavailable, so creation returns nil and the caller falls back
    /// to a software key. Any existing key with the same application tag is
    /// reused (kSecAttrIsPermanent stores it in the Keychain).
    private func makeKey(secureEnclave: Bool) -> SecKey? {
        let tag = secureEnclave ? Self.secureEnclaveTag : Self.softwareTag
        var attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
            ],
        ]
        if secureEnclave {
            attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }
        var error: Unmanaged<CFError>?
        // SecKeyCreateRandomKey returns nil when the requested token (SE) is
        // unavailable — e.g. on the Simulator — or when a key already exists
        // under the tag and cannot be overwritten.
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            // Try to fetch an existing key under the same identity class before
            // giving up. Do not let the Secure Enclave probe fetch a software key,
            // or the receipt could mislabel the identity type.
            return fetchExistingKey(secureEnclave: secureEnclave)
        }
        return key
    }

    /// Creates a non-persistent EC P-256 key that never touches the Keychain.
    /// Last-resort fallback so signing still works when key storage fails.
    private func makeEphemeralKey() -> SecKey? {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(attrs as CFDictionary, &error)
    }

    /// Loads a previously-created persistent key from the Keychain by tag.
    private func fetchExistingKey(secureEnclave: Bool) -> SecKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag as String: secureEnclave ? Self.secureEnclaveTag : Self.softwareTag,
            kSecReturnRef as String: true,
        ]
        if secureEnclave {
            query[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let ref = result else { return nil }
        // `ref` is a CF SecKey reference (kSecReturnRef). SecKey is a
        // CoreFoundation class type, so `as!`/`as?` only yield spurious
        // "always succeeds" diagnostics; unsafeDowncast expresses the
        // guaranteed-safe conversion without a warning.
        return unsafeDowncast(ref, to: SecKey.self)
    }
}
