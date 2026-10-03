import Foundation

public enum ComplimentaryPolicy {
    // Account verified in the signed-in Limits page on 2026-10-03: usage tier 1.
    // These are the published Tier 1–2 allowances, not an API-provided balance.
    public static let largerCap = 250_000
    public static let smallerCap = 2_500_000

    // Source: OpenAI Help article 10306912, checked 2026-10-03.
    // Store aliases without snapshot dates so aliases and dated model IDs match.
    public static let largerModels = [
        "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.5",
        "gpt-5.4", "gpt-5.2", "gpt-5.1", "gpt-5.1-codex", "gpt-5-codex",
        "gpt-5", "gpt-5-chat-latest", "gpt-4.5-preview", "gpt-4.1", "gpt-4o",
        "o3", "o1-preview", "o1",
        // The account's incentive-tier usage confirms free eligibility, but the
        // published article omits 6.1 Sol. Larger-pool assignment is an inference
        // from its Sol family, not a verified allowance-group entitlement.
        "gpt-6.1-sol"
    ]
    public static let smallerModels = [
        "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.4-mini", "gpt-5.4-nano",
        "gpt-5.1-codex-mini", "gpt-5-mini", "gpt-5-nano", "gpt-4.1-mini",
        "gpt-4.1-nano", "gpt-4o-mini", "o4-mini", "o1-mini", "codex-mini-latest"
    ]

    public static func canonicalModel(_ model: String) -> String {
        model.replacingOccurrences(of: "_", with: ".")
            .replacingOccurrences(of: "-\\d{4}-\\d{2}-\\d{2}$", with: "", options: .regularExpression)
    }

    public static func isInferred(_ model: String) -> Bool {
        canonicalModel(model) == "gpt-6.1-sol"
    }
}
