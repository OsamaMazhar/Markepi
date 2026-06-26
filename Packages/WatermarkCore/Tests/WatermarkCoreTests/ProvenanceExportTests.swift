import Testing
import Foundation
@testable import WatermarkCore

@Suite("ProvenanceExport")
struct ProvenanceExportTests {

    // MARK: - Task 2: C2PA Signing Identity Store

    @Suite("C2PASigningIdentityStore")
    struct SigningIdentityStoreTests {

        @Test("Current identity always returns a non-nil display name")
        func identityHasDisplayName() {
            let store = C2PASigningIdentityStore()
            let identity = store.currentIdentity()
            #expect(identity.displayName == "Markepi device signing identity")
        }

        @Test("Identity type is one of secureEnclave / localSoftware / unsupported")
        func identityTypeIsValid() {
            let store = C2PASigningIdentityStore()
            let identity = store.currentIdentity()
            switch identity.type {
            case .secureEnclave, .localSoftware, .unsupported:
                break // valid
            }
        }

        @Test("Identity type raw value is stable for receipt encoding")
        func identityTypeRawValueStable() {
            #expect(C2PASigningIdentity.IdentityType.secureEnclave.rawValue == "secureEnclave")
            #expect(C2PASigningIdentity.IdentityType.localSoftware.rawValue == "localSoftware")
            #expect(C2PASigningIdentity.IdentityType.unsupported.rawValue == "unsupported")
        }

        @Test("Display name never describes a verified legal identity (D-24)")
        func displayNameIsNotVerifiedLegalIdentity() {
            let store = C2PASigningIdentityStore()
            let name = store.currentIdentity().displayName
            #expect(!name.lowercased().contains("verified"))
            #expect(!name.lowercased().contains("legal"))
            #expect(name.contains("device"))
        }
    }
}
