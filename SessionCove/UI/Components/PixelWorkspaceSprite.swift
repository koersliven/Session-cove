import SwiftUI

struct PixelWorkspaceSprite: View {
    var mood: IslandMood = .recent

    /// Two small islands connected by a wooden bridge
    static let rows: [String] = [
        "...............................",
        "...........L...................",
        "..........LLL.........L........",
        "...........T.........LLL.......",
        "..........GTG.........T........",
        "......OOOGGGGOO....OOGGO.......",
        "....OOGSSSSGGGGO..OGGGGGOO.....",
        "...OOSSSSSSSSSSOOOOOSSSSSSO....",
        "..OOSSSSSSSSBBBBBBBSSSSSSOO....",
        "...OOSSSSSSSSSSOOOSSSSSSO......",
        "....OOSSSRSSSSO...OOSSOO.......",
        ".....OOOOOOOOO.....OOOO........",
        "...............................",
    ]

    var body: some View {
        Image(nsImage: PixelSpriteCache.workspace(mood: mood))
            .resizable()
            .interpolation(.none)
            .aspectRatio(contentMode: .fit)
    }
}
