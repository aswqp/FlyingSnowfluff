import Foundation

public struct Size2D: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = max(0, width)
        self.height = max(0, height)
    }
}

public struct PetWindowLayout: Equatable, Sendable {
    public static let logicalPetWidth = 192.0
    public static let logicalPetHeight = 208.0

    public var petRect: Rect2D
    public var windowSize: Size2D

    public init(petRect: Rect2D, windowSize: Size2D) {
        self.petRect = petRect
        self.windowSize = windowSize
    }

    public static func make(
        petHeight: Double = logicalPetHeight,
        containerWidth: Double = logicalPetWidth,
        bubbleHeight: Double = 0,
        spacing: Double = 0
    ) -> PetWindowLayout {
        let resolvedPetHeight = max(0, petHeight)
        let resolvedBubbleHeight = max(0, bubbleHeight)
        let resolvedSpacing = max(0, spacing)
        let petWidth = resolvedPetHeight * logicalPetWidth / logicalPetHeight
        let windowWidth = max(max(0, containerWidth), petWidth)
        let petRect = Rect2D(
            x: (windowWidth - petWidth) / 2,
            y: resolvedBubbleHeight + resolvedSpacing,
            width: petWidth,
            height: resolvedPetHeight
        )
        return PetWindowLayout(
            petRect: petRect,
            windowSize: Size2D(
                width: windowWidth,
                height: resolvedBubbleHeight + resolvedSpacing + resolvedPetHeight
            )
        )
    }
}
