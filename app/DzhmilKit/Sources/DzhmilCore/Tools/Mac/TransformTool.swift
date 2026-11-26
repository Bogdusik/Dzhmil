struct TransformTool: SafeTool {
    let transform: @Sendable () async -> Bool
    let name = "transform_into_hornet"
    let description = "Transform into Hornet (Шершень), your villain fighter jet form, and fly around the screen for half a minute. Call it only when the user asks you to transform or to become Hornet."
    let inputSchema = Schema.object([:])

    func run(_ input: JSONValue) async throws -> String {
        guard await transform() else {
            throw ToolError.message("Hornet can't take off now: not while you are hidden, in Quiet Mode, over a fullscreen app or already flying.")
        }
        return "You will turn into Hornet right after this reply. Say one short, theatrical villain line as Hornet, nothing menacing towards the user."
    }
}
