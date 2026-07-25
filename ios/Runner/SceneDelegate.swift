import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    IncomingAudioImportStore.shared.accept(
      urls: connectionOptions.urlContexts.map(\.url)
    )
    super.scene(
      scene,
      willConnectTo: session,
      options: connectionOptions
    )
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    IncomingAudioImportStore.shared.accept(
      urls: URLContexts.map(\.url)
    )
    super.scene(scene, openURLContexts: URLContexts)
  }
}
