//
//  MoreView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 2/13/25.
//

import SwiftUI

struct MoreView: View {
    @Binding var sheet: ContentView.Sheet?
    var body: some View {
        Form {
            Section("Get help"){
                NavigationLink("Learn about servers", value: Help.servers)
                NavigationLink("Learn about testing them", value: Help.tests)
                Link("Send me an email", destination: "mailto:contact@hannesnagel.com")
            }

            Section {
                Button("Tap to submit feedback") {
                    sheet = .feedback
                    Logger.telemetry("opened feedback sheet")
                }
                Link("Open a new Issue on GitHub", destination: "https://github.com/hannesmnagel/ContainEye/issues")
            }
            Section("About") {
                Link("View source code on GitHub", destination: "https://github.com/hannesmnagel/ContainEye")
            }
            Section("Credits (all MIT License)") {
                Link("Blackbird", destination: "https://github.com/marcoarment/Blackbird")
                Link("Citadel", destination: "https://github.com/orlandos-nl/Citadel")
                Link("ButtonKit", destination: "https://github.com/Dean151/ButtonKit")
                Link("KeychainAccess", destination: "https://github.com/kishikawakatsumi/KeychainAccess")
                Link("mlx-libraries", destination: "https://github.com/ml-explore/mlx-swift-examples/")
            }
        }
        .navigationTitle("More")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    struct Link: View {
        let text: LocalizedStringKey
        let destination: URL
        @Environment(\.openURL) var openURL

        init(_ text: LocalizedStringKey, destination: String) {
            self.text = text
            self.destination = URL(string: destination)!
        }

        var body: some View {
            Button(text) {
                Logger.telemetry("opened \(destination.absoluteString)")
                openURL(destination)
            }
        }
    }
}

#Preview {
    MoreView(sheet: .constant(nil))
}
