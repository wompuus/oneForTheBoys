import SwiftUI

struct DartsSettingsView: View {
    @Binding var settings: DartsSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Darts Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Starting Score")
                    .font(.subheadline)
                Stepper(value: $settings.startingScore, in: 101...1001, step: 50) {
                    Text("\(settings.startingScore)")
                }
            }

            Toggle("Double Out Required", isOn: $settings.doubleOutRequired)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
