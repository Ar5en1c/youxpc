// RecipeStore.swift - File-based recipe storage
//
// Loads/saves/lists/deletes recipes from ~/.youxpc/recipes/
// Logs decode errors so broken recipes are visible, not silently skipped.

import Foundation

/// File-based recipe storage.
public enum RecipeStore {

    private static let recipesDir = NSString(string: "~/.youxpc/recipes").expandingTildeInPath

    /// Recipe names become file names and arrive from the agent, so they are
    /// limited to a safe alphabet. Without this, a name such as "../../x"
    /// reads, overwrites or deletes .json files outside the recipes directory.
    public static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil
    }

    /// File path for a recipe, or nil when the name is not allowed.
    private static func path(forRecipe name: String) -> String? {
        guard isValidName(name) else {
            Log.warn("Rejected recipe name '\(name)'")
            return nil
        }
        return (recipesDir as NSString).appendingPathComponent("\(name).json")
    }

    /// List all available recipes. Logs decode errors for broken recipe files.
    public static func listRecipes() -> [Recipe] {
        let fm = FileManager.default
        ensureDirectory()

        var recipes: [Recipe] = []
        guard let files = try? fm.contentsOfDirectory(atPath: recipesDir) else { return [] }

        let decoder = JSONDecoder()
        for file in files where file.hasSuffix(".json") {
            let path = (recipesDir as NSString).appendingPathComponent(file)
            guard let data = fm.contents(atPath: path) else { continue }
            do {
                let recipe = try decoder.decode(Recipe.self, from: data)
                recipes.append(recipe)
            } catch {
                // Log decode errors so broken recipes are visible
                Log.warn("Failed to decode recipe '\(file)': \(error)")
            }
        }

        return recipes.sorted { $0.name < $1.name }
    }

    /// Load a specific recipe by name. Returns nil with logged error if decode fails.
    public static func loadRecipe(named name: String) -> Recipe? {
        guard let path = path(forRecipe: name) else { return nil }
        guard let data = FileManager.default.contents(atPath: path) else {
            Log.info("Recipe '\(name)' not found at \(path)")
            return nil
        }
        do {
            return try JSONDecoder().decode(Recipe.self, from: data)
        } catch {
            Log.error("Failed to decode recipe '\(name)': \(error)")
            return nil
        }
    }

    /// Save a recipe.
    public static func saveRecipe(_ recipe: Recipe) throws {
        ensureDirectory()
        guard let path = path(forRecipe: recipe.name) else {
            throw ToolError.invalidParameter(
                "Recipe name '\(recipe.name)' is not allowed. Use 1-64 letters, digits, '-' or '_'."
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(recipe)
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Delete a recipe by name.
    public static func deleteRecipe(named name: String) -> Bool {
        guard let path = path(forRecipe: name) else { return false }
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Save a recipe from raw JSON string. Returns recipe name on success.
    /// Validates the JSON parses correctly before saving.
    public static func saveRecipeJSON(_ jsonString: String) throws -> String {
        guard let data = jsonString.data(using: .utf8) else {
            throw ToolError.invalidParameter("Invalid JSON string")
        }
        do {
            let recipe = try JSONDecoder().decode(Recipe.self, from: data)
            try saveRecipe(recipe)
            return recipe.name
        } catch let decodingError as DecodingError {
            // Give the agent a helpful error message about what's wrong with the JSON
            let detail: String
            switch decodingError {
            case let .keyNotFound(key, context):
                detail = "Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .typeMismatch(type, context):
                detail = "Type mismatch: expected \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .valueNotFound(type, context):
                detail = "Missing value of type \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            case let .dataCorrupted(context):
                detail = "Corrupted data at \(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
            @unknown default:
                detail = "\(decodingError)"
            }
            throw ToolError.invalidParameter("Recipe JSON decode error: \(detail)")
        }
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            atPath: recipesDir,
            withIntermediateDirectories: true
        )
    }
}
