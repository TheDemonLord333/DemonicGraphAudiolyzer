import SwiftUI

/// Named parameters of a project or voice: constant with a slider, or a list that switches
/// per beat or per bar. Each parameter becomes a definition line before the formulas.
struct SynthParameterListEditor: View {
    @Binding var parameters: [SynthParameter]
    var issues: [SynthIssue]
    /// Names the simple editor detected in the formulas (value 1 until they get a slider).
    var autoParameters: [String] = []
    var identifierPrefix: String
    var onHelp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                DemonSubheader("Parameter")
                Spacer(minLength: 4)
                Button(action: onHelp) {
                    Image(systemName: "book.fill")
                        .foregroundStyle(DemonTheme.neonGreen)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Anleitung zu Parametern öffnen")
            }
            if parameters.isEmpty {
                DemonCaption("Keine Parameter. Ein Parameter ist ein Name mit Regler (konstant) oder mit einer Werteliste, die pro Beat oder pro Takt weiterschaltet.")
            }
            ForEach($parameters) { $parameter in
                SynthParameterRow(parameter: $parameter, identifier: "\(identifierPrefix)-\(parameter.name)") {
                    let id = parameter.id
                    parameters.removeAll { $0.id == id }
                }
            }
            ForEach(issues.indices, id: \.self) { index in
                Label(issues[index].message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(DemonTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let missing = autoParameters.filter { name in !parameters.contains { $0.name == name } }
            if !missing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DemonCaption("Automatisch erkannt (Wert 1): \(missing.joined(separator: ", ")). Als Regler übernehmen, um den Wert einzustellen:")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(missing, id: \.self) { name in
                                Button {
                                    parameters.append(SynthParameter(name: name, value: 1))
                                } label: {
                                    Label(name, systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(DemonChipButtonStyle(tint: DemonTheme.neonGreen))
                                .accessibilityLabel("\(name) als Regler übernehmen")
                            }
                        }
                    }
                }
            }
            Button {
                parameters.append(SynthParameter(name: nextName, value: 1))
            } label: {
                Label("Parameter hinzufügen", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(DemonChipButtonStyle())
            .disabled(parameters.count >= 16)
            .accessibilityIdentifier("\(identifierPrefix)-addParameter")
        }
    }

    private var nextName: String {
        let used = Set(parameters.map(\.name))
        for candidate in ["p", "q", "k", "m", "depth", "amount", "speed"] where !used.contains(candidate) {
            return candidate
        }
        var index = 1
        while used.contains("p\(index)") { index += 1 }
        return "p\(index)"
    }
}

/// One parameter: name, kind, slider or value list, range.
struct SynthParameterRow: View {
    @Binding var parameter: SynthParameter
    var identifier: String
    var onDelete: () -> Void
    @State private var showRange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                DemonTextField(title: "Name", text: $parameter.name, monospaced: true, identifier: "\(identifier)-name")
                    .frame(maxWidth: 140)
                DemonMenuPicker(title: "Art", selection: $parameter.mode,
                                options: SynthParameter.Mode.allCases.map { (value: $0, title: $0.title) })
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(DemonTheme.danger)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Parameter \(parameter.name) entfernen")
            }
            switch parameter.mode {
            case .constant:
                DemonSlider(title: parameter.name.isEmpty ? "Wert" : parameter.name,
                            value: $parameter.value,
                            range: sliderRange,
                            format: { NumberText.compact($0) })
                HStack(spacing: 8) {
                    NumericField(title: "Wert", value: $parameter.value, accessibilityIdentifier: "\(identifier)-value")
                    if showRange {
                        NumericField(title: "Minimum", value: $parameter.minimum)
                        NumericField(title: "Maximum", value: $parameter.maximum)
                    }
                    Button {
                        showRange.toggle()
                    } label: {
                        Image(systemName: "arrow.left.and.right")
                    }
                    .buttonStyle(DemonChipButtonStyle(isActive: showRange))
                    .accessibilityLabel("Reglerbereich einstellen")
                    .padding(.top, 18)
                }
            case .perBeat, .perBar:
                NumberListField(title: parameter.mode == .perBar ? "Werte, Takt für Takt" : "Werte, Beat für Beat",
                                values: $parameter.values, identifier: "\(identifier)-values")
                DemonCaption(listExplanation)
            }
        }
        .demonInset(tint: DemonTheme.blurple.opacity(0.5), padding: 10)
        .onChange(of: parameter.value) { _, value in
            // The slider range grows with typed values so the slider never hides the value.
            if value < parameter.minimum { parameter.minimum = value }
            if value > parameter.maximum { parameter.maximum = value }
        }
    }

    private var sliderRange: ClosedRange<Double> {
        let low = min(parameter.minimum, parameter.maximum)
        let high = max(parameter.minimum, parameter.maximum)
        return high > low ? low...high : low...(low + 1)
    }

    private var listExplanation: String {
        let counter = parameter.mode == .perBar ? "bar" : "floor(beat)"
        return "Wirkt wie \(parameter.name) = Liste[mod(\(counter), \(max(parameter.values.count, 1)))]: Wert 1 gilt im ersten \(parameter.mode == .perBar ? "Takt" : "Beat"), danach der nächste; am Ende beginnt die Liste von vorn."
    }
}
