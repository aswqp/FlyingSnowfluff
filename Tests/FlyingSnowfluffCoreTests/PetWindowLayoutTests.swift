import Testing
@testable import FlyingSnowfluffCore

@Suite("Pet window layout")
struct PetWindowLayoutTests {
    @Test func defaultLayoutUsesLogicalCellWithoutHorizontalStretching() {
        let layout = PetWindowLayout.make()

        #expect(layout.petRect == Rect2D(x: 0, y: 0, width: 192, height: 208))
        #expect(layout.windowSize == Size2D(width: 192, height: 208))
    }

    @Test func layoutCentersPetAndIncludesBubbleAndSpacingInWindowHeight() {
        let layout = PetWindowLayout.make(containerWidth: 320, bubbleHeight: 44, spacing: 12)

        #expect(layout.petRect == Rect2D(x: 64, y: 56, width: 192, height: 208))
        #expect(layout.windowSize == Size2D(width: 320, height: 264))
    }

    @Test func layoutSupportsConfiguredHeightsAtTheLogicalAspectRatio() {
        for height in [176.0, 208, 256, 320] {
            let layout = PetWindowLayout.make(petHeight: height, containerWidth: 400)

            #expect(layout.petRect.height == height)
            #expect(abs(layout.petRect.width * 208 - layout.petRect.height * 192) <= 0.000_001)
            #expect(abs(layout.petRect.x - (400 - layout.petRect.width) / 2) <= 0.000_001)
            #expect(layout.windowSize.height == height)
        }
    }

    @Test func pixelAlignmentRoundsNegativeEdgesToBackingPixelsWithoutNegativeSize() {
        let aligned = Rect2D(x: -1.26, y: -0.24, width: 3.51, height: 2.49).pixelAligned(backingScale: 2)

        #expect(aligned == Rect2D(x: -1.5, y: 0, width: 4, height: 2.5))
        #expect(aligned.x * 2 == (aligned.x * 2).rounded())
        #expect(aligned.maxX * 2 == (aligned.maxX * 2).rounded())
        #expect(aligned.y * 2 == (aligned.y * 2).rounded())
        #expect(aligned.maxY * 2 == (aligned.maxY * 2).rounded())

        let inverted = Rect2D(x: 3.2, y: -1.1, width: -1.1, height: -0.1).pixelAligned(backingScale: 2)
        #expect(inverted.width >= 0)
        #expect(inverted.height >= 0)
    }
}
