import Testing
@testable import PulseBar

struct NettopSampleParserTests {
    @Test
    func usesSecondDeltaSampleAsCurrentSpeedAndFirstSampleAsTotal() {
        let output = """
        ,bytes_in,bytes_out,
        Browser.101,900000,120000,
        Proxy.202,4000000,3000000,
        ,bytes_in,bytes_out,
        Browser.101,24000,6000,
        Proxy.202,0,0,
        """

        let rows = NettopSampleParser.processTraffic(from: output)

        #expect(rows.count == 1)
        guard let row = rows.first else {
            Issue.record("Expected one active process row")
            return
        }
        #expect(row.pid == 101)
        #expect(row.name == "Browser")
        #expect(row.receivedPerSecond == 24_000)
        #expect(row.sentPerSecond == 6_000)
        #expect(row.totalReceived == 900_000)
        #expect(row.totalSent == 120_000)
    }

    @Test
    func returnsNoRowsWhenCurrentSampleIsIdle() {
        let output = """
        ,bytes_in,bytes_out,
        Browser.101,900000,120000,
        ,bytes_in,bytes_out,
        Browser.101,0,0,
        """

        #expect(NettopSampleParser.processTraffic(from: output).isEmpty)
    }

    @Test
    func requiresBothCumulativeAndDeltaSamples() {
        let output = """
        ,bytes_in,bytes_out,
        Browser.101,900000,120000,
        """

        #expect(NettopSampleParser.processTraffic(from: output).isEmpty)
    }
}
