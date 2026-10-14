import Testing
@testable import YouxPC

@Suite("RecipeStore name validation")
struct RecipeStoreTests {

    @Test("Ordinary recipe names are accepted", arguments: [
        "gmail-send", "arxiv-download", "finder_create_folder", "a", "Recipe2",
    ])
    func acceptsSafeNames(name: String) {
        #expect(RecipeStore.isValidName(name))
    }

    @Test("Names that could escape the recipes directory are rejected", arguments: [
        "../../.claude", "..", "a/b", "/etc/passwd", ".hidden", "", "name.json",
        "with space", "-leading-dash", String(repeating: "x", count: 65),
    ])
    func rejectsUnsafeNames(name: String) {
        #expect(!RecipeStore.isValidName(name))
    }

    @Test("Unsafe names never reach the filesystem")
    func unsafeNamesAreNotLoadedOrDeleted() {
        #expect(RecipeStore.loadRecipe(named: "../../.claude") == nil)
        #expect(RecipeStore.deleteRecipe(named: "../../.claude") == false)
    }
}
