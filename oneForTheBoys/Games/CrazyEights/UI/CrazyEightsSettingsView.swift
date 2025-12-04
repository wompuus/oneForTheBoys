import SwiftUI
import OFTBShared

struct CrazyEightsSettingsView: View {
    @Binding var settings: CrazyEightsSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Stepper("Starting cards: \(settings.startingHandCount)", value: $settings.startingHandCount, in: 1...50)
                Stepper("Skips per color: \(settings.skipPerColor)", value: $settings.skipPerColor, in: 0...50)
                Stepper("Reverses per color: \(settings.reversePerColor)", value: $settings.reversePerColor, in: 0...50)
                Stepper("+2 per color: \(settings.draw2PerColor)", value: $settings.draw2PerColor, in: 0...50)
                Stepper("Wild count: \(settings.wildCount)", value: $settings.wildCount, in: 0...50)
                Stepper("Wild+4 count: \(settings.wildDraw4Count)", value: $settings.wildDraw4Count, in: 0...50)
            }

            Divider()

            Toggle("Allow stacking draws", isOn: $settings.allowStackDraws)
            Toggle("Allow mixed stacking (+2 on +4)", isOn: $settings.allowMixedDrawStacking)
                .disabled(!settings.allowStackDraws)

            Toggle("Shot Caller UNO", isOn: $settings.shotCallerEnabled)
            Toggle("THE BOMB", isOn: $settings.bombEnabled)
            Stepper("Bomb draw per opponent: \(settings.bombDrawCount)", value: $settings.bombDrawCount, in: 1...20)
#if DEBUG
//            Toggle("DEBUG: every number card is a bomb", isOn: $settings.debugAllNumbersAreBombs)
//                .disabled(!settings.bombEnabled)
#endif
            Toggle("Fog of War card", isOn: $settings.fogEnabled)
            if settings.fogEnabled {
                Stepper("Fog cards in deck: \(settings.fogCardCount)", value: $settings.fogCardCount, in: 1...20)
                Stepper("Fog duration (turns): \(settings.fogBlindTurns)", value: $settings.fogBlindTurns, in: 1...5)
            }
            Toggle("Allow 7-0 hand swap rule", isOn: $settings.allowSevenZeroRule)

            Toggle("Allow join in progress", isOn: $settings.allowJoinInProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
