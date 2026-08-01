public enum TranscriptFixtures {
    public static let accumulatingIdentity = [
        line(id: "msg_01AccumulatingIdentity", output: 100, cacheRead: 20_000),
        line(id: "msg_01AccumulatingIdentity", output: 180, cacheRead: 20_000),
        line(id: "msg_01AccumulatingIdentity", output: 210, cacheRead: 20_000)
    ]

    public static let twoModelFallback = """
    {"message":{"model":"claude-opus-4-8","id":"msg_01TwoModelFallback","type":"message",\
    "role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,\
    "cache_read_input_tokens":9389,"output_tokens":2609,"service_tier":"standard",\
    "iterations":[{"input_tokens":2,"output_tokens":4,"cache_read_input_tokens":20513,\
    "cache_creation_input_tokens":9136,"type":"message","model":"claude-fable-5"},\
    {"input_tokens":2,"output_tokens":2609,"cache_read_input_tokens":9389,\
    "cache_creation_input_tokens":0,"type":"fallback_message","model":"claude-opus-4-8"}]}},\
    "requestId":"req_01TwoModelFallback","type":"assistant","uuid":"uuid-two-model-fallback",\
    "timestamp":"2026-07-24T15:21:21.297Z","version":"2.1.218"}
    """

    public static let syntheticModel = """
    {"message":{"model":"<synthetic>","id":"msg_01SyntheticModel","type":"message",\
    "role":"assistant","usage":{"input_tokens":0,"cache_creation_input_tokens":0,\
    "cache_read_input_tokens":0,"output_tokens":0,"service_tier":"standard"}},\
    "requestId":"req_01SyntheticModel","type":"assistant","uuid":"uuid-synthetic-model",\
    "timestamp":"2026-07-24T15:22:00.000Z","version":"2.1.218"}
    """

    public static let withoutRequestIdentifier = """
    {"message":{"model":"claude-opus-5","id":"msg_01WithoutRequestIdentifier","type":"message",\
    "role":"assistant","usage":{"input_tokens":4,"cache_creation_input_tokens":128,\
    "cache_read_input_tokens":9000,"output_tokens":77,"service_tier":"standard"}},\
    "type":"assistant","uuid":"uuid-without-request-identifier",\
    "timestamp":"2026-07-24T15:23:00.000Z","version":"2.1.218"}
    """

    public static let withoutAnyIdentifier = """
    {"message":{"model":"claude-opus-5","type":"message","role":"assistant",\
    "usage":{"input_tokens":4,"cache_creation_input_tokens":0,\
    "cache_read_input_tokens":10,"output_tokens":8,"service_tier":"standard"}},\
    "type":"assistant","timestamp":"2026-07-24T15:24:00.000Z","version":"2.1.218"}
    """

    public static let identitySplitAcrossFiles = (
        first: line(id: "msg_01SplitAcrossFiles", output: 120, cacheRead: 5_000),
        second: line(id: "msg_01SplitAcrossFiles", output: 480, cacheRead: 5_000)
    )

    public static let singleIterationWithoutModel = """
    {"message":{"model":"claude-opus-5","id":"msg_01SingleIteration","type":"message",\
    "role":"assistant","usage":{"input_tokens":2,"cache_creation_input_tokens":0,\
    "cache_read_input_tokens":1000,"output_tokens":50,"service_tier":"standard",\
    "iterations":[{"input_tokens":2,"output_tokens":50,"cache_read_input_tokens":1000,\
    "cache_creation_input_tokens":0,"type":"message"}]}},\
    "requestId":"req_01SingleIteration","type":"assistant","uuid":"uuid-single-iteration",\
    "timestamp":"2026-07-24T15:25:00.000Z","version":"2.1.220"}
    """

    public static let truncatedTail = String(
        line(id: "msg_01TruncatedTail", output: 900, cacheRead: 3_000).prefix(150)
    )

    public static func line(
        id: String,
        output: Int,
        model: String = "claude-opus-5",
        input: Int = 2,
        cacheRead: Int = 0,
        cacheCreation: Int = 0,
        at instant: String = "2026-07-24T15:21:21.297Z",
        version: String = "2.1.218"
    ) -> String {
        """
        {"message":{"model":"\(model)","id":"\(id)","type":"message","role":"assistant",\
        "usage":{"input_tokens":\(input),"cache_creation_input_tokens":\(cacheCreation),\
        "cache_read_input_tokens":\(cacheRead),"output_tokens":\(output),\
        "service_tier":"standard"}},"requestId":"req_\(id)","type":"assistant",\
        "uuid":"uuid-\(id)","timestamp":"\(instant)","version":"\(version)"}
        """
    }
}
