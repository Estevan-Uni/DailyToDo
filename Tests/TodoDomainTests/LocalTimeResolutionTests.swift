import Foundation
import Testing
@testable import TodoDomain

@Suite struct LocalTimeResolutionTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    @Test func ordinaryTimeAndInvalidMinute() throws {
        let day = try LocalDate("2027-01-15")
        let value = try day.resolveTime(minute: 9 * 60, timeZone: losAngeles)
        #expect(value.kind == .exact && value.alternative == nil)
        #expect(value.requestedTimeLabel == "09:00" && value.resolvedTimeLabel == "09:00")
        #expect(value.instant == (try day.instant(minute: 9 * 60, timeZone: losAngeles)))
        #expect(LocalTimeResolution.offsetLabel(value.utcOffset) == "UTC−08:00")
        #expect(throws: DomainError.invalidTime) { try day.resolveTime(minute: 1440, timeZone: losAngeles) }
    }
    @Test func springGapShowsActualTimeWithSameInstantPolicy() throws {
        let day = try LocalDate("2027-03-14")
        let value = try day.resolveTime(minute: 150, timeZone: losAngeles)
        #expect(value.kind == .advanced && value.alternative == nil)
        #expect(value.requestedMinute == 150 && value.resolvedMinute == 180)
        #expect(value.instant == (try day.instant(minute: 180, timeZone: losAngeles)))
        #expect(value.utcOffset == -7 * 3600)
    }
    @Test func fallFoldIdentifiesBothOccurrencesAndKeepsFirst() throws {
        let day = try LocalDate("2027-11-07")
        let value = try day.resolveTime(minute: 90, timeZone: losAngeles)
        #expect(value.kind == .repeated && value.requestedMinute == value.resolvedMinute)
        #expect(value.alternative?.timeIntervalSince(value.instant) == 3600)
        #expect(value.utcOffset == -7 * 3600 && value.alternativeUTCOffset == -8 * 3600)
        #expect(value.instant == (try day.instant(minute: 90, timeZone: losAngeles)))
    }
    @Test func halfHourTransitionsAndEntireMissingDate() throws {
        let zone = TimeZone(identifier: "Australia/Lord_Howe")!
        let gap = try LocalDate("2026-10-04").resolveTime(minute: 135, timeZone: zone)
        #expect(gap.kind == .advanced && gap.resolvedMinute == 150)
        let fold = try LocalDate("2026-04-05").resolveTime(minute: 105, timeZone: zone)
        #expect(fold.kind == .repeated && fold.alternative?.timeIntervalSince(fold.instant) == 1800)
        let apia = TimeZone(identifier: "Pacific/Apia")!
        #expect(throws: DomainError.unavailableLocalTime) { try LocalDate("2011-12-30").resolveTime(minute: 600, timeZone: apia) }
        #expect(LocalTimeResolution.offsetLabel(19800) == "UTC+05:30")
    }
}
