//
//  HelpRuleView.swift
//  oneForTheBoys
//
//  Created by Wyatt Nail on 11/18/25.
//

import SwiftUI

enum CrazyEightsHelpRule {
    case shotCaller
    case bomb
}

struct CrazyEightsHelpView: View {
    let rule: CrazyEightsHelpRule

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch rule {
                case .shotCaller:
                    Text("Shot Caller UNO")
                        .font(.title2)
                        .bold()
                    Text("When enabled, playing a Wild lets you pick a color and a target player. That player must play the chosen color on their next turn or keep drawing until they can. Only that player is constrained; everyone else plays normally.")
                    Text("Use it to bully whoever is closest to winning.")
                        .foregroundStyle(.secondary)

                case .bomb:
                    Text("THE BOMB")
                        .font(.title2)
                        .bold()
                    Text("A single hidden card in the round is the bomb. When someone plays it, each opponent draws the configured number of cards. After it explodes, play direction reverses and the next player is skipped. The bomb then re-arms on a brand new hidden card so nobody can predict it.")
                    Text("The specific card is randomized and never shown in settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Rule Help")
    }
}
