import Foundation
import Testing
@testable import PulseBar

struct ProcessCommandRunnerTests {
    @Test
    func cancelAllTerminatesAnActiveCommand() async {
        let runner = ProcessCommandRunner()
        let task = Task.detached {
            runner.run("/bin/sleep", arguments: ["10"], timeout: 20)
        }

        for _ in 0..<50 where runner.activeProcessCount == 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(runner.activeProcessCount == 1)

        let startedAt = Date()
        runner.cancelAll()
        let result = await task.value

        #expect(result.wasCancelled)
        #expect(runner.activeProcessCount == 0)
        #expect(Date().timeIntervalSince(startedAt) < 1)
    }

    @Test
    func timeoutTerminatesACommand() async {
        let runner = ProcessCommandRunner()
        let startedAt = Date()
        let result = await Task.detached {
            runner.run("/bin/sleep", arguments: ["10"], timeout: 0.1)
        }.value

        #expect(result.timedOut)
        #expect(!result.wasCancelled)
        #expect(runner.activeProcessCount == 0)
        #expect(Date().timeIntervalSince(startedAt) < 1)
    }
}
