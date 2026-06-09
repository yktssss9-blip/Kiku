import SwiftUI

struct StopTimeSlider: View {
    let isActive: Bool
    let onToggle: () -> Void

    @GestureState private var dragX: CGFloat = 0
    @State private var isDragging = false

    private let height: CGFloat = 56
    private let thumbDia: CGFloat = 48
    private let pad: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - thumbDia - pad * 2, 1)
            let baseX: CGFloat = isActive ? travel : 0
            let constrainedDrag = isActive ? min(0, dragX) : max(0, dragX)
            let thumbX = min(max(baseX + constrainedDrag, 0), travel) + pad

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(isActive ? Color.orange : Color(UIColor.tertiarySystemFill))
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)

                // Label
                Group {
                    if isActive {
                        Text("← スライドしてオフ")
                            .padding(.leading, thumbDia + pad * 2 + 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("スライドしてStop Timeをオン →")
                            .padding(.trailing, 16)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(isActive ? .white.opacity(0.9) : Color.secondary)
                .opacity(isDragging ? 0 : 1)
                .animation(.easeOut(duration: 0.12), value: isDragging)

                // Thumb
                ZStack {
                    Circle()
                        .fill(isActive ? Color.white : Color.orange)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(isActive ? Color.orange : Color.white)
                        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                }
                .frame(width: thumbDia, height: thumbDia)
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .offset(x: thumbX)
                .animation(isDragging ? nil : .spring(response: 0.35, dampingFraction: 0.75), value: dragX)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isActive)
                .gesture(
                    DragGesture(minimumDistance: 5)
                        .updating($dragX) { value, state, _ in
                            state = value.translation.width
                        }
                        .onChanged { _ in isDragging = true }
                        .onEnded { value in
                            isDragging = false
                            let threshold = travel * 0.4
                            if !isActive && value.translation.width > threshold {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onToggle()
                            } else if isActive && value.translation.width < -threshold {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                onToggle()
                            }
                        }
                )
            }
        }
        .frame(height: height)
    }
}
