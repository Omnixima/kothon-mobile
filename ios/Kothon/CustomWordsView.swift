// "আমার শব্দ": the user's replacements ("শুনলে → লিখুন", every model).
// See CustomWords.

import SwiftUI

struct CustomWordsView: View {
    @State private var replacements = CustomWords.replacements
    @State private var newHeard = ""
    @State private var newWrite = ""

    var body: some View {
        List {
            Section {
                ForEach(replacements) { r in
                    HStack(spacing: 8) {
                        Text(r.heard).font(.bn(.body))
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(r.write).font(.bn(.body, .semibold))
                    }
                }
                .onDelete { replacements.remove(atOffsets: $0); CustomWords.replacements = replacements }
                HStack(spacing: 8) {
                    TextField("শুনলে", text: $newHeard)
                        .font(.bn(.body))
                        .autocorrectionDisabled()
                    Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                    TextField("লিখুন", text: $newWrite)
                        .font(.bn(.body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addReplacement)
                    Button("যোগ", action: addReplacement)
                        .font(.bn(.body, .semibold))
                        .disabled(newHeard.isEmpty || newWrite.isEmpty)
                }
            } header: {
                Text("শুনলে → লিখুন").font(.bn(.footnote, .semibold))
            } footer: {
                Text("লেখায় বাম পাশের শব্দ এলে ডান পাশেরটা বসবে, যেমন \"আইএ এস\" → iOS। পুরো শব্দ মিললে তবেই বদলায়; \"আইএ এসের\" হয়ে যায় \"iOS-এর\"। মুছতে বাঁ দিকে টানুন।")
                    .font(.bn(.caption))
            }

            Section {
                Button("শুরুর তালিকায় ফিরিয়ে নিন", role: .destructive) {
                    replacements = CustomWords.builtInReplacements
                    CustomWords.replacements = replacements
                }
                .font(.bn(.body))
            }
        }
        .scrollContentBackground(.hidden)
        .background(KothonBackdrop())
        .navigationTitle("আমার শব্দ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addReplacement() {
        let h = newHeard.trimmingCharacters(in: .whitespaces)
        let w = newWrite.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty, !w.isEmpty else { return }
        replacements.removeAll { $0.heard == h }
        replacements.append(Replacement(heard: h, write: w))
        CustomWords.replacements = replacements
        newHeard = ""; newWrite = ""
    }
}
