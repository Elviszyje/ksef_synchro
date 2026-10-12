import SwiftUI
import StoreKit

/// Napiwek dla autora: konsumowalne zakupy w aplikacji (wymóg App Store 3.1.1).
/// Niczego nie odblokowują.
enum TipJar {
    static let productIDs = ["pl.ksefektywnie.tip.coffee", "pl.ksefektywnie.tip.lunch", "pl.ksefektywnie.tip.big"]

    /// Konsumowalne transakcje trzeba zakończyć; dotyczy też zakupów przerwanych przy poprzednim uruchomieniu.
    static func finishPendingTransactions() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { await transaction.finish() }
        }
    }
}

struct TipJarView: View {
    @State private var thanks = false
    /// nil — ładowanie; pusta lista — produkty nieskonfigurowane w App Store Connect (np. wczesny TestFlight).
    @State private var available: [String]?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 56)).foregroundStyle(.tint)
                Text("Dziękuję, że korzystasz z KS-eFektywnie!").font(.title3.bold()).multilineTextAlignment(.center)
                Text("Aplikacja działa w całości na Twoim telefonie, bez kont i reklam. Jeśli oszczędza Ci czas, możesz postawić autorowi kawę.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)

                if available?.isEmpty == true {
                    Text("Napiwki będą dostępne w wersji opublikowanej w App Store.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                VStack(spacing: 12) {
                    ForEach(available ?? [], id: \.self) { id in
                        ProductView(id: id) {
                            Image(systemName: icon(for: id)).font(.title2).foregroundStyle(.tint)
                        }
                        .productViewStyle(.compact)
                        .padding()
                        .glassEffect(in: .rect(cornerRadius: 16))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Tip for developer")
        .task {
            let products = (try? await Product.products(for: TipJar.productIDs)) ?? []
            available = TipJar.productIDs.filter { id in products.contains { $0.id == id } }
        }
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                thanks = true
            }
        }
        .alert("Dziękuję!", isPresented: $thanks) {
            Button("OK") {}
        } message: {
            Text("Twoje wsparcie bardzo pomaga w dalszym rozwoju aplikacji.")
        }
    }

    private func icon(for id: String) -> String {
        switch id {
        case TipJar.productIDs[0]: "cup.and.saucer"
        case TipJar.productIDs[1]: "fork.knife"
        default: "heart.fill"
        }
    }
}
