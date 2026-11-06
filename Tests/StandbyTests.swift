import Foundation

@main
struct StandbyTests {
    static func main() {
        var state = StandbyState()
        precondition(!state.transition(to: .active))
        precondition(!state.transition(to: .inactive), "system UI must not begin a background lease")
        precondition(!state.transition(to: .active))
        precondition(state.transition(to: .background))
        precondition(!state.transition(to: .background), "duplicate callbacks must not stack leases")
        state.leaseExpired = true
        precondition(!state.canPoll(lease: false, audio: false))
        precondition(state.canPoll(lease: false, audio: true), "actual standby playback can keep polling")
        precondition(!state.transition(to: .inactive))
        precondition(!state.transition(to: .background), "inactive must not renew an expired lease")
        precondition(!state.transition(to: .active))
        precondition(state.transition(to: .background), "a later real foreground visit permits a new lease")

        var phases = StandbyState()
        _ = phases.transition(to: .active)
        precondition(!phases.shouldPlay(enabled: true, blocked: false), "an active App needs no standby audio")
        precondition(phases.canPoll(lease: false, audio: false), "foreground polling continues without standby audio")
        _ = phases.transition(to: .inactive)
        precondition(phases.shouldPlay(enabled: true, blocked: false), "leaving active prepares standby before suspension")
        _ = phases.transition(to: .background)
        precondition(phases.shouldPlay(enabled: true, blocked: false), "background keeps standby")
        precondition(!phases.shouldPlay(enabled: false, blocked: false), "a disabled standby never plays")
        precondition(!phases.shouldPlay(enabled: true, blocked: true), "an audio interruption blocks standby")
        _ = phases.transition(to: .active)
        precondition(!phases.shouldPlay(enabled: true, blocked: false), "returning to the App stops standby audio")
        print("Standby lifecycle: passed")
    }
}
