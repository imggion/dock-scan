import SwiftUI

struct DockscanNavigateAction {
    var showImage: (_ imageRef: String) -> Void = { _ in }
    var showNetwork: (_ networkName: String) -> Void = { _ in }
    var showVolume: (_ volumeName: String) -> Void = { _ in }
}

private struct DockscanNavigateKey: EnvironmentKey {
    static let defaultValue = DockscanNavigateAction()
}

extension EnvironmentValues {
    var dockscanNavigate: DockscanNavigateAction {
        get { self[DockscanNavigateKey.self] }
        set { self[DockscanNavigateKey.self] = newValue }
    }
}

