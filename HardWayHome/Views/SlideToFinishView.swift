import SwiftUI
import UIKit

struct SlideToFinishView: View {
    let onSlideComplete: () -> Void
    @Binding var shouldReset: Bool

    @State private var dragOffset: CGFloat = 0
    @State private var trackWidth: CGFloat = 0

    private let thumbSize: CGFloat = 56
    private let threshold: CGFloat = 0.85

    private var maxOffset: CGFloat {
        max(trackWidth - thumbSize, 0)
    }

    private var progress: CGFloat {
        guard maxOffset > 0 else { return 0 }
        return dragOffset / maxOffset
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: thumbSize / 2)
                    .fill(Color.red.opacity(0.3))

                // Progress fill
                RoundedRectangle(cornerRadius: thumbSize / 2)
                    .fill(Color.red)
                    .frame(width: thumbSize + dragOffset)

                // Label
                Text("Slide to Finish")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(Double(max(1 - progress * 2, 0))))
                    .frame(maxWidth: .infinity)

                // Draggable thumb
                Circle()
                    .fill(.white)
                    .frame(width: thumbSize - 8, height: thumbSize - 8)
                    .overlay(
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.red)
                            .font(.system(size: 16, weight: .bold))
                    )
                    .padding(4)
                    .offset(x: dragOffset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                dragOffset = min(max(value.translation.width, 0), maxOffset)
                            }
                            .onEnded { _ in
                                if progress >= threshold {
                                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        dragOffset = maxOffset
                                    }
                                    onSlideComplete()
                                } else {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        dragOffset = 0
                                    }
                                }
                            }
                    )
            }
            .frame(height: thumbSize)
            .onAppear { trackWidth = geo.size.width }
            .onChange(of: geo.size.width) { _, w in trackWidth = w }
        }
        .frame(height: 56)
        .onChange(of: shouldReset) { _, reset in
            if reset {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    dragOffset = 0
                }
                shouldReset = false
            }
        }
    }
}
