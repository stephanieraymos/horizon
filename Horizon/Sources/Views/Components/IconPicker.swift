import SwiftUI

/// A grid of common SF Symbols for choosing a category icon. Present as a sheet.
struct IconPicker: View {
    let current: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    static let icons = [
        "tshirt", "shower", "laptopcomputer", "doc.text", "takeoutbag.and.cup.and.straw",
        "figure.and.child.holdinghands", "backpack", "shippingbox", "bag", "cart",
        "gamecontroller", "book", "camera", "bandage", "cross.case", "pawprint",
        "tent", "flame", "fork.knife", "cup.and.saucer", "sunglasses", "umbrella",
        "snowflake", "bicycle", "gift", "key", "creditcard", "phone", "headphones",
        "battery.100", "binoculars", "map", "suitcase", "sun.max", "heart", "star",
        "bolt", "leaf", "drop", "figure.hiking"
    ]

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Button {
                            onPick(icon); dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 56, height: 56)
                                .foregroundStyle(icon == current ? .white : Theme.Colors.brand)
                                .background(icon == current ? Theme.Colors.brand : Color.systemFill6,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
