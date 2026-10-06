import SwiftUI

struct ContentView: View {
    @EnvironmentObject var robot: RobotController
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var camera: CameraService

    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if settings.showCamera {
                CameraPreview(session: camera.session, orientation: camera.videoOrientation)
                    .ignoresSafeArea()
            } else {
                RoboEyesView(mood: robot.mood)
                    .ignoresSafeArea()
            }

            VStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(robot.espOnline ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(robot.statusText)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.45))
                            .padding(10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(robot)
                .environmentObject(settings)
                .environmentObject(robot.commands)
        }
    }
}
