import Foundation

/// Reviewed runtime roots and save-field offsets for an exact game profile.
/// The operation service binds this layout to the manifest's build and module UUID.
public struct DaveRuntimeLayout: Equatable, Sendable {
    public let saveSystemInstanceMethodRVA: UInt64
    public let saveSystemHasInstanceMethodRVA: UInt64
    public let ingredientsInstanceMethodRVA: UInt64
    public let ingredientsConstructorMethodRVA: UInt64
    public let saveDataPlayerInfoOffset: UInt64
    public let saveDataIngredientsDictionaryOffset: UInt64
    public let saveDataJungleOffset: UInt64
    public let jungleVillageItemsDictionaryOffset: UInt64

    public static let v106675 = DaveRuntimeLayout(
        saveSystemInstanceMethodRVA: 0x98D7948,
        saveSystemHasInstanceMethodRVA: 0x98D7950,
        ingredientsInstanceMethodRVA: 0x98D6E88,
        ingredientsConstructorMethodRVA: 0x98D6E80,
        saveDataPlayerInfoOffset: 0x220,
        saveDataIngredientsDictionaryOffset: 0x100,
        saveDataJungleOffset: 0x2A8,
        jungleVillageItemsDictionaryOffset: 0x150
    )

    // Verified against v1.0.6.756 metadata field tables and arm64 symbols.
    public static let v106756 = DaveRuntimeLayout(
        saveSystemInstanceMethodRVA: 0x99A7AC0,
        saveSystemHasInstanceMethodRVA: 0x99A7AC8,
        ingredientsInstanceMethodRVA: 0x99A6FD0,
        ingredientsConstructorMethodRVA: 0x99A6FC8,
        saveDataPlayerInfoOffset: 0x240,
        saveDataIngredientsDictionaryOffset: 0x120,
        saveDataJungleOffset: 0x2C8,
        jungleVillageItemsDictionaryOffset: 0x178
    )
}
