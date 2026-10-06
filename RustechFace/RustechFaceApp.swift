import SwiftUI

@main
struct RustechFaceApp: App {
    @StateObject private var robot = RobotController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(robot)
                .environmentObject(robot.settings)
                .environmentObject(robot.commands)
                .environmentObject(robot.camera)
                .statusBar(hidden: true)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    robot.start()
                }
        }
    }
}
