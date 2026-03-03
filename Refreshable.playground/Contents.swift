//: # How fresh is .refreshable?
//: Demonstrates the SwiftUI ScrollView + .refreshable cancellation bug
//: and the Task {}.value fix.

import UIKit
import SwiftUI
import PlaygroundSupport

// MARK: - Fake API simulating a network call

enum FakeAPI {
    static func fetchItems() async throws -> [String] {
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2s delay
        return (1...5).map { "Item \($0) — \(Date().formatted(date: .omitted, time: .standard))" }
    }
}

// MARK: - Step tracker for visualizing the chain of events

struct LogEntry: Identifiable {
    let id = UUID()
    let step: Int?
    let message: String
    let style: LogStyle
    let timestamp: Date = .now

    enum LogStyle {
        case info, success, error, step
    }
}

// MARK: - ViewModel with @Published properties

@MainActor
final class DemoViewModel: ObservableObject {
    @Published var items: [String] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var log: [LogEntry] = []

    func fetchData() async {
        let start = Date()
        addLog(step: 1, "User pulled → .refreshable creates structured child task", .step)

        // ⬇️ THIS @Published change triggers the view rebuild
        isLoading = true
        errorMessage = nil
        addLog(step: 2, "isLoading = true → @Published fires objectWillChange", .step)
        addLog(step: 3, "SwiftUI re-evaluates body → ScrollView rebuilds", .step)

        do {
            try Task.checkCancellation()
            addLog(step: 4, "Starting network call...", .info)

            let result = try await FakeAPI.fetchItems()
            try Task.checkCancellation()

            items = result
            let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))
            addLog(step: 5, "✓ SUCCESS — \(result.count) items loaded in \(elapsed)", .success)
        } catch is CancellationError {
            let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))
            errorMessage = "Cancelled after \(elapsed)"
            addLog(step: 4, "✗ CANCELLED after \(elapsed) — task killed by view rebuild", .error)
        } catch {
            errorMessage = error.localizedDescription
            addLog(step: nil, "✗ ERROR: \(error.localizedDescription)", .error)
        }

        isLoading = false
    }

    func clearLog() {
        log.removeAll()
        items.removeAll()
        errorMessage = nil
    }

    private func addLog(step: Int? = nil, _ message: String, _ style: LogEntry.LogStyle) {
        log.insert(LogEntry(step: step, message: message, style: style), at: 0)
    }
}

// MARK: - Shared content view (no duplication)

struct DemoContentView: View {
    @ObservedObject var viewModel: DemoViewModel
    let variant: Variant

    enum Variant: String {
        case bug = "BUG"
        case fix = "FIX"
    }

    var body: some View {
        VStack(spacing: 12) {
            statusCard
            if !viewModel.items.isEmpty { itemsCard }
            if !viewModel.log.isEmpty { logCard }
            Spacer(minLength: 40)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header banner
            HStack {
                Image(systemName: variant == .bug ? "ladybug.fill" : "checkmark.seal.fill")
                    .font(.title3)
                Text(variant == .bug
                     ? "ScrollView + .refreshable (Buggy)"
                     : "ScrollView + Task {}.value (Fixed)")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(variant == .bug ? .red : .green)

            Divider()

            // Current status
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                } else if let error = viewModel.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .fontWeight(.medium)
                } else if !viewModel.items.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Loaded \(viewModel.items.count) items")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                    Text("Pull down to refresh ↓")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)

            // Code snippet showing the difference
            VStack(alignment: .leading, spacing: 2) {
                Text("Code:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if variant == .bug {
                    codeBlock("""
                    .refreshable {
                        await viewModel.fetchData()
                    }
                    """)
                } else {
                    codeBlock("""
                    .refreshable {
                        await Task {
                            await viewModel.fetchData()
                        }.value
                    }
                    """)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Items Card

    private var itemsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Fetched Items", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(viewModel.items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Log Card (chain of events)

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Event Log", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(viewModel.log.count) events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.log) { entry in
                HStack(alignment: .top, spacing: 8) {
                    // Step number badge
                    if let step = entry.step {
                        Text("\(step)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(logColor(entry.style), in: Circle())
                    } else {
                        Circle()
                            .fill(logColor(entry.style))
                            .frame(width: 8, height: 8)
                            .padding(6)
                    }

                    Text(entry.message)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                        .foregroundStyle(logColor(entry.style))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func codeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func logColor(_ style: LogEntry.LogStyle) -> Color {
        switch style {
        case .info: .primary
        case .success: .green
        case .error: .red
        case .step: .orange
        }
    }
}

// MARK: - Buggy Tab

struct BuggyRefreshView: View {
    @StateObject private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                DemoContentView(viewModel: viewModel, variant: .bug)
            }
            .refreshable {
                // ⚠️ BUG: Direct await inside structured child task.
                // isLoading = true → view rebuild → task cancelled.
                await viewModel.fetchData()
            }
            .navigationTitle("🐛 Bug Demo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", systemImage: "trash") {
                        viewModel.clearLog()
                    }
                }
            }
        }
    }
}

// MARK: - Fixed Tab

struct FixedRefreshView: View {
    @StateObject private var viewModel = DemoViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                DemoContentView(viewModel: viewModel, variant: .fix)
            }
            .refreshable {
                // ✅ FIX: Unstructured Task escapes cancellation scope.
                // .value keeps the spinner alive until completion.
                await Task {
                    await viewModel.fetchData()
                }.value
            }
            .navigationTitle("✅ Fix Demo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", systemImage: "trash") {
                        viewModel.clearLog()
                    }
                }
            }
        }
    }
}

// MARK: - Main App with TabView

struct RefreshableBugDemoApp: View {
    var body: some View {
        TabView {
            BuggyRefreshView()
                .tabItem {
                    Label("Bug", systemImage: "ladybug")
                }

            FixedRefreshView()
                .tabItem {
                    Label("Fix", systemImage: "checkmark.seal")
                }
        }
        .tint(.orange)
    }
}

// MARK: - Playground Entry Point

PlaygroundPage.current.setLiveView(RefreshableBugDemoApp())
