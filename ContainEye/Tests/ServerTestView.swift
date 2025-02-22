//
//  ServerTestView.swift
//  ContainEye
//
//  Created by Hannes Nagel on 1/23/25.
//

import SwiftUI
import Blackbird
import ButtonKit
import UserNotifications
import MLXLMCommon

struct ServerTestView: View {
    @Binding var sheet : ContentView.Sheet?
    @Environment(\.blackbirdDatabase) var db
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey != "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var test
    @BlackbirdLiveModels({
        try await ServerTest.read(
            from: $0,
            matching: \.$credentialKey == "-",
            orderBy: .descending(\.$lastRun)
        )
    }) var suggestions
    @Environment(\.scenePhase) var scenePhase
    @State private var notificationsAllowed = true
    @Environment(\.namespace) var namespace
    @Environment(LLMEvaluator.self) var llm

    var body: some View {
        ScrollView {
            VStack{
                if test.didLoad {
                    VStack {
                        if test.results.isEmpty {
                            ContentUnavailableView("You don't have any tests yet.", systemImage: "testtube.2")
                                .containerRelativeFrame(.vertical){len, axis in
                                    len*0.4
                                }
                        } else {
                            Text("Active Tests")
                                .font(.title.bold())
                            if !notificationsAllowed {
                                HStack {
                                    Text("Notifications not allowed")
                                    Spacer()

                                    Button("Change") {
#if !os(macOS)
                                        UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)
#else
#warning("fix this for macOS")
#endif
                                    }
                                }
                                .padding()
                                .background(.orange, in: .capsule)
                                .padding(.vertical)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250))], spacing: 15){
                                ForEach(test.results) { test in
                                    TestSummaryView(test: test.liveModel)
                                }
                            }
                            .padding(.bottom, 100)
                        }
                        Text("Suggested")
                            .font(.title.bold())
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 250))], spacing: 15){
                            ForEach(suggestions.results) { test in
                                TestSummaryView(test: test.liveModel)
                            }
                        }
                    }
                    .animation(.smooth, value: test.results)
                    .padding(.vertical)
                }

                Button("Add Test", systemImage: "plus") {
                    sheet = .addTest
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .matchedTransitionSource(id: ContentView.Sheet.addTest, in: namespace!)
                NavigationLink("Learn more", value: Help.tests)


            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            test.results
                .contains(where: {$0.status != .success}) ? Color.clear.gradient : Color.green
                .opacity(0.1)
                .gradient
        )
    }
}



#Preview {
    let db = try! Blackbird.Database.inMemoryDatabase()
    let serverTest = ServerTest(id: 17891, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", status: .success)
    let _ = Task{try await serverTest.write(to: db) }
    let serverTest2 = ServerTest(id: 19311, title: "Test", credentialKey: UUID().uuidString, command: "echo test", expectedOutput: "test", status: .success)
    let _ = Task{try await serverTest2.write(to: db) }
    ServerTestView(sheet: .constant(nil))
        .environment(\.blackbirdDatabase, db)
}
