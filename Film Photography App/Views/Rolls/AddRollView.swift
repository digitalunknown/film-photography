import SwiftUI

struct AddRollView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedStockId: UUID?
    @State private var status: RollStatus = .inFridge
    @State private var format: FilmFormat = .format35Full
    @State private var selectedCameraId: UUID?
    @State private var exposuresText = "36"
    @State private var pushPull = 0
    @State private var frameCountText = "0"
    @State private var storageLocation = "Fridge"
    @State private var labName = "The Darkroom"
    @State private var includeExpiryDate = false
    @State private var expiryDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var tagInput = ""

    private var exposures: Int {
        max(Int(exposuresText.filter(\.isNumber)) ?? format.defaultExposures, 1)
    }

    private var frameCount: Int {
        max(Int(frameCountText.filter(\.isNumber)) ?? 0, 0)
    }

    private var canSave: Bool {
        guard selectedStockId != nil else { return false }
        if status == .inCamera { return selectedCameraId != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            store.showingLoadFlow = true
                        }
                    } label: {
                        Text("Load with photo →")
                            .font(InstrumentFont.mono(13))
                    }
                }

                Section("Film") {
                    Picker("Stock", selection: $selectedStockId) {
                        Text("Select stock").tag(nil as UUID?)
                        ForEach(store.stocks) { stock in
                            Text(stock.name).tag(stock.id as UUID?)
                        }
                    }

                    Picker("Format", selection: $format) {
                        ForEach(FilmFormat.allCases) { fmt in
                            Text(fmt.displayName).tag(fmt)
                        }
                    }
                    .onChange(of: format) { _, newFormat in
                        if exposuresText == "36" || exposuresText == "72" || exposuresText == "24" {
                            exposuresText = String(newFormat.defaultExposures)
                        }
                    }

                    TextField("Expected frames", text: $exposuresText)
                        .keyboardType(.numberPad)
                        .submitLabel(.done)

                    Picker("Push/pull", selection: $pushPull) {
                        Text("Box speed").tag(0)
                        Text("Push +1").tag(1)
                        Text("Push +2").tag(2)
                        Text("Pull −1").tag(-1)
                    }

                    Toggle("Expiry date", isOn: $includeExpiryDate)
                    if includeExpiryDate {
                        DatePicker("Date", selection: $expiryDate, displayedComponents: .date)
                    }
                }

                Section("Pipeline") {
                    Picker("Status", selection: $status) {
                        ForEach(RollStatus.pipelineCases, id: \.self) { stage in
                            Text(stage.displayName).tag(stage)
                        }
                    }
                }

                if status == .inCamera {
                    Section("Camera") {
                        Picker("Loaded in", selection: $selectedCameraId) {
                            Text("Select camera").tag(nil as UUID?)
                            ForEach(availableCameras) { camera in
                                Text(camera.name).tag(camera.id as UUID?)
                            }
                        }

                        TextField("Frame count", text: $frameCountText)
                            .keyboardType(.numberPad)
                            .submitLabel(.done)
                    }
                } else if status.showsCamera {
                    Section("Camera") {
                        Picker("Shot with", selection: $selectedCameraId) {
                            Text("None").tag(nil as UUID?)
                            ForEach(store.cameras) { camera in
                                Text(camera.name).tag(camera.id as UUID?)
                            }
                        }
                    }
                }

                if status == .shotUndeveloped {
                    Section("Storage") {
                        TextField("Location", text: $storageLocation, prompt: Text("Fridge"))
                            .submitLabel(.done)
                    }
                }

                if status == .atLab {
                    Section("Lab") {
                        TextField("Lab name", text: $labName)
                            .submitLabel(.done)
                    }
                }

                Section("Tags") {
                    TextField("Optional tag", text: $tagInput)
                        .submitLabel(.done)
                }
            }
            .instrumentFormStyle()
            .navigationTitle("Add Roll")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(InstrumentFont.mono(13))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .font(InstrumentFont.mono(13))
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedStockId == nil {
                    selectedStockId = store.stocks.first?.id
                }
                exposuresText = String(format.defaultExposures)
            }
        }
    }

    private var availableCameras: [Camera] {
        store.cameras.filter { store.loadedRoll(for: $0.id) == nil || $0.id == selectedCameraId }
    }

    private func save() {
        guard let stockId = selectedStockId else { return }
        let tags = tagInput.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [tagInput.lowercased()]
        store.addRoll(
            stockId: stockId,
            status: status,
            cameraId: selectedCameraId,
            format: format,
            exposures: exposures,
            pushPull: pushPull,
            frameCount: frameCount,
            storageLocation: storageLocation,
            labName: labName,
            expiryDate: includeExpiryDate ? expiryDate : nil,
            tags: tags
        )
        dismiss()
    }
}

#Preview {
    AddRollView()
        .environment(AppStore())
}
