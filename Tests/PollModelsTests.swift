import Foundation

@main
struct PollModelsTests {
    static func main() throws {
        let full = #"{"island":{"state":"happy","line":"在呢。","hide":false},"messages":[{"id":"m1","text":"hello","title":"demo"},{"id":7}]}"#
        let answer = try JSONDecoder().decode(PollResponse.self, from: Data(full.utf8))
        precondition(answer.island?.state == "happy" && answer.island?.line == "在呢。")
        precondition(answer.messages?.count == 1, "a malformed message is skipped alone")
        precondition(answer.messages?.first?.title == "demo")

        let broken = #"{"island":"oops","messages":{"x":1}}"#
        let survived = try JSONDecoder().decode(PollResponse.self, from: Data(broken.utf8))
        precondition(survived.island == nil && survived.messages == nil, "broken keys are dropped, decoding still succeeds")

        let empty = try JSONDecoder().decode(PollResponse.self, from: Data("{}".utf8))
        precondition(empty.island == nil && empty.messages == nil)
        print("Poll answer decoding: passed")
    }
}
