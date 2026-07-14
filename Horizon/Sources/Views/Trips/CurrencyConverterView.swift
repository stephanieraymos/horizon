import SwiftUI

/// A quick on-trip currency converter using keyless ECB rates (frankfurter.app).
/// No API key, no Supabase egress. Handy for reading foreign prices.
struct CurrencyConverterView: View {
    @Environment(\.dismiss) private var dismiss

    // Common travel currencies (ISO 4217).
    private let currencies = ["USD", "EUR", "GBP", "MXN", "CAD", "JPY", "AUD",
                              "CHF", "CNY", "INR", "THB", "KRW", "BRL", "NZD"]

    @AppStorage("fx.from") private var from = "USD"
    @AppStorage("fx.to") private var to = "EUR"
    @State private var amountText = "100"
    @State private var result: Double?
    @State private var rate: Double?
    @State private var isLoading = false
    @State private var errorText: String?

    private var amount: Double { Double(amountText.replacingOccurrences(of: ",", with: "")) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Picker("From", selection: $from) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                        Button {
                            swap(&from, &to)
                        } label: { Image(systemName: "arrow.left.arrow.right") }
                        .buttonStyle(.borderless)
                        Picker("To", selection: $to) {
                            ForEach(currencies, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    if isLoading {
                        HStack { ProgressView(); Text("Fetching rate…").foregroundStyle(.secondary) }
                    } else if let result {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(format(result)) \(to)").font(.title2.bold())
                            if let rate {
                                Text("1 \(from) = \(format(rate)) \(to)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if let errorText {
                        Text(errorText).font(.callout).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Rates from the European Central Bank via frankfurter.app.")
                }
            }
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task(id: "\(from)|\(to)|\(amountText)") { await convert() }
        }
    }

    private func format(_ v: Double) -> String {
        String(format: "%.2f", v)
    }

    private func convert() async {
        guard from != to else { result = amount; rate = 1; errorText = nil; return }
        guard amount > 0 else { result = nil; return }
        isLoading = true; errorText = nil
        defer { isLoading = false }
        guard let url = URL(string: "https://api.frankfurter.app/latest?amount=\(amount)&from=\(from)&to=\(to)") else { return }
        struct Response: Decodable { let rates: [String: Double] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let converted = try JSONDecoder().decode(Response.self, from: data).rates[to]
            if let converted {
                result = converted
                rate = amount > 0 ? converted / amount : nil
            } else {
                errorText = "Couldn't convert those currencies."
            }
        } catch {
            errorText = "Couldn't reach the rates service."
        }
    }
}
