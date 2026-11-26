@testable import NexusMasterSync
import XCTest

final class H264Tests: XCTestCase {
    func testSplitsNALsWithThreeAndFourByteStartCodes() {
        let stream = Data([0, 0, 0, 1, 0x67, 1, 2, 0, 0, 1, 0x68, 3, 0, 0, 0, 1, 0x65, 9])
        XCTAssertEqual(H264.nalUnits(in: stream), [Data([0x67, 1, 2]), Data([0x68, 3]), Data([0x65, 9])])
    }

    func testNoStartCodeMeansNoNAL() {
        XCTAssertEqual(H264.nalUnits(in: Data([1, 2, 3])), [])
        XCTAssertEqual(H264.nalUnits(in: Data()), [])
    }

    func testLengthPrefixedUsesFourByteSizes() {
        let stream = Data([0, 0, 0, 1, 0x41, 1, 2, 0, 0, 1, 0x41, 3, 4, 5, 6])
        XCTAssertEqual(H264.lengthPrefixed(fromAnnexB: stream),
                       Data([0, 0, 0, 3, 0x41, 1, 2, 0, 0, 0, 5, 0x41, 3, 4, 5, 6]))
    }

    func testParameterSetsFindSPSAndPPS() throws {
        let config = Data([0, 0, 0, 1, 0x06, 0xAA, 0, 0, 0, 1, 0x67, 1, 2, 3, 0, 0, 0, 1, 0x68, 4, 5])
        let sets = try XCTUnwrap(H264.parameterSets(fromConfig: config))
        XCTAssertEqual(sets.sps, Data([0x67, 1, 2, 3]))
        XCTAssertEqual(sets.pps, Data([0x68, 4, 5]))
    }

    func testParameterSetsNeedBoth() {
        XCTAssertNil(H264.parameterSets(fromConfig: Data([0, 0, 0, 1, 0x67, 1, 2])))
        XCTAssertNil(H264.parameterSets(fromConfig: Data([0, 0, 0, 1, 0x68, 1, 2])))
        XCTAssertNil(H264.parameterSets(fromConfig: Data()))
    }
}
