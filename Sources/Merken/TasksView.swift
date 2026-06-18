import SwiftUI

/// Full TasksView (header + body) — kept for backwards compat but not used directly.
struct TasksView: View {
    @EnvironmentObject var store: NoteStore
    var onClose: (() -> Void)? = nil
    var body: some View {
        TasksBodyOnly()
    }
}

/// Just the scrollable body of the Tasks panel — header lives in ContentView Row 1.
struct TasksBodyOnly: View {
    @EnvironmentObject var store: NoteStore
    @State private var newTask     = ""
    @FocusState private var inputFocused: Bool

    private var openTasks: [NoteTask] { store.tasks.filter { !$0.done } }
    private var doneTasks: [NoteTask] { store.tasks.filter {  $0.done } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // ── Add task ──────────────────────────────────────────────
                HStack(spacing: 8) {
                    TextField("Add a task…", text: $newTask)
                        .textFieldStyle(.plain)
                        .font(F.syneUI(13))
                        .foregroundColor(C.text)
                        .focused($inputFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(inputFocused ? C.textDim : C.border, lineWidth: 1)
                        )
                        .onSubmit { submit() }

                    Button("Add") { submit() }
                        .buttonStyle(.plain)
                        .font(F.syneUI(12))
                        .foregroundColor(C.textDim)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(C.border, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 20)

                // ── Open ──────────────────────────────────────────────────
                sectionLabel("Open")
                if openTasks.isEmpty {
                    emptyLabel("No open tasks.")
                } else {
                    ForEach(openTasks) { task in TaskRow(task: task) }
                }

                // ── Done ──────────────────────────────────────────────────
                sectionLabel("Done").padding(.top, 24)
                if doneTasks.isEmpty {
                    emptyLabel("No completed tasks.")
                } else {
                    ForEach(doneTasks) { task in TaskRow(task: task) }
                }

                Spacer(minLength: 32)
            }
        }
        .background(C.bgSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        let t = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if store.addTask(t) { newTask = ""; inputFocused = true }
    }

    @ViewBuilder private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(F.syneUI(9)).tracking(1.2).foregroundColor(C.textFaint)
            .padding(.horizontal, 16).padding(.bottom, 6)
    }

    @ViewBuilder private func emptyLabel(_ text: String) -> some View {
        Text(text).font(F.syneUI(12)).foregroundColor(C.textFaint)
            .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

// MARK: – Task row

struct TaskRow: View {
    @EnvironmentObject var store: NoteStore
    let task: NoteTask
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Checkbox — larger hit area for reliability
            Button {
                store.toggleTask(task)
            } label: {
                TaskCheckbox(done: task.done)
                    .frame(width: 14, height: 14)
                    .padding(4)          // expands hit area without visual change
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            // Text + source file name
            VStack(alignment: .leading, spacing: 2) {
                Text(task.text)
                    .font(F.syneUI(13))
                    .foregroundColor(task.done ? C.textDim : C.text)
                    .strikethrough(task.done, color: C.textDim)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(task.sourceFile.replacingOccurrences(of: ".md", with: ""))
                    .font(F.syneUI(10))
                    .foregroundColor(C.textFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Arrow — visible on hover, tappable
            Button {
                store.jumpToTaskNote(task)
            } label: {
                Icon.arrow.view(size: 11, color: hovered ? C.textDim : Color.clear)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open note")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(hovered ? C.bgHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.08), value: hovered)
    }
}

// MARK: – Checkbox shape

struct TaskCheckbox: View {
    let done: Bool

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(done ? C.primaryStart : C.textDim, lineWidth: 1.2)
                if done {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(C.primaryStart.opacity(0.15))
                    Path { p in
                        p.move(to:    CGPoint(x: s * 0.20, y: s * 0.52))
                        p.addLine(to: CGPoint(x: s * 0.42, y: s * 0.74))
                        p.addLine(to: CGPoint(x: s * 0.82, y: s * 0.26))
                    }
                    .stroke(C.primaryStart,
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}
