import SwiftUI
import Observation

/// Subtelna animacja: miniaturka faktury „wpada” do zakładki Przelewy po zatwierdzeniu do zapłaty.
@Observable
final class PaymentsFlight {
    struct Flight: Identifiable, Equatable {
        let id = UUID()
        let start: CGPoint
    }

    private(set) var flights: [Flight] = []
    /// Licznik lądowań — wyzwala haptykę na pasku zakładek.
    private(set) var landings = 0

    /// - Parameter start: punkt startu w układzie globalnym (np. środek przycisku albo wiersza).
    func launch(from start: CGPoint) {
        flights.append(Flight(start: start))
    }

    func land(_ flight: Flight) {
        flights.removeAll { $0.id == flight.id }
        landings += 1
    }
}

/// Nakładka rysująca lecące miniaturki nad całym interfejsem (bez przechwytywania dotyku).
/// Rysuje w układzie globalnym (cały ekran), tym samym co punkt startu.
struct PaymentsFlightOverlay: View {
    @Environment(PaymentsFlight.self) private var flight
    /// Pozycja zakładki Przelewy jako ułamek szerokości paska (3. z 5 zakładek = środek).
    let tabFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            // Środek ikony w pływającym pasku zakładek (ok. 48 pt nad dolną krawędzią ekranu).
            let target = CGPoint(x: geo.size.width * tabFraction, y: screenHeight - 48)
            ZStack {
                ForEach(flight.flights) { item in
                    FlyingInvoice(start: item.start, end: target) { flight.land(item) }
                }
            }
            .frame(width: geo.size.width, height: screenHeight, alignment: .topLeading)
            .offset(y: -geo.safeAreaInsets.top)
        }
        .allowsHitTesting(false)
    }
}

struct FlyingInvoice: View {
    let start: CGPoint
    let end: CGPoint
    let onLanded: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Image(systemName: "doc.text.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.tint)
            .padding(8)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            .modifier(ArcFlight(progress: progress, start: start, end: end))
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7)) { progress = 1 } completion: { onLanded() }
            }
            .accessibilityHidden(true)
    }
}

/// Położenie na krzywej Béziera (łuk ku górze), skala i przezroczystość zależne od postępu.
struct ArcFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        let control = CGPoint(x: (start.x + end.x) / 2 + 40, y: min(start.y, end.y) - 60)
        let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + t * t * end.x
        let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + t * t * end.y
        content
            .scaleEffect(1 - 0.5 * t)
            .opacity(t < 0.9 ? 1 : Double(1 - (t - 0.9) / 0.1))
            .position(x: x, y: y)
    }
}
