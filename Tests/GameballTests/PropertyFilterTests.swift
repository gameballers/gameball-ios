//
//  PropertyFilterTests.swift
//  GameballTests
//

import XCTest
@testable import Gameball

final class PropertyFilterTests: XCTestCase {

    // MARK: - Equality

    func testEqualsMatchesString() {
        let filter = PropertyFilter(name: "category", op: .equals, value: "electronics")
        XCTAssertTrue(filter.matches(properties: ["category": "electronics"]))
        XCTAssertFalse(filter.matches(properties: ["category": "groceries"]))
    }

    /// JSON hands us `Int` or `Double` unpredictably for the same authored number, so
    /// comparison has to be numeric. Comparing "100" to "100.0" as strings would fail.
    func testEqualsComparesNumbersNumerically() {
        let filter = PropertyFilter(name: "price", op: .equals, value: 100)
        XCTAssertTrue(filter.matches(properties: ["price": 100.0]))
        XCTAssertTrue(filter.matches(properties: ["price": 100]))
        XCTAssertTrue(filter.matches(properties: ["price": NSNumber(value: 100.0)]))
    }

    func testNotEqualsInvertsEquals() {
        let filter = PropertyFilter(name: "category", op: .notEquals, value: "electronics")
        XCTAssertTrue(filter.matches(properties: ["category": "groceries"]))
        XCTAssertFalse(filter.matches(properties: ["category": "electronics"]))
    }

    // MARK: - Ordering

    func testGreaterThanOnNumbers() {
        let filter = PropertyFilter(name: "price", op: .greaterThan, value: 100)
        XCTAssertTrue(filter.matches(properties: ["price": 150]))
        XCTAssertFalse(filter.matches(properties: ["price": 50]))
    }

    func testGreaterThanOrEqualBoundary() {
        let filter = PropertyFilter(name: "price", op: .greaterThanOrEqual, value: 100)
        XCTAssertTrue(filter.matches(properties: ["price": 100]))
        XCTAssertTrue(filter.matches(properties: ["price": 101]))
        XCTAssertFalse(filter.matches(properties: ["price": 99]))
    }

    func testLessThanOnNumbers() {
        let filter = PropertyFilter(name: "price", op: .lessThan, value: 100)
        XCTAssertTrue(filter.matches(properties: ["price": 50]))
        XCTAssertFalse(filter.matches(properties: ["price": 150]))
    }

    func testLessThanOrEqualBoundary() {
        let filter = PropertyFilter(name: "price", op: .lessThanOrEqual, value: 100)
        XCTAssertTrue(filter.matches(properties: ["price": 100]))
        XCTAssertTrue(filter.matches(properties: ["price": 99]))
        XCTAssertFalse(filter.matches(properties: ["price": 101]))
    }

    // MARK: - Substring

    func testContainsIsCaseInsensitiveSubstring() {
        let filter = PropertyFilter(name: "product", op: .contains, value: "PRO")
        XCTAssertTrue(filter.matches(properties: ["product": "iPhone Pro"]))
        XCTAssertFalse(filter.matches(properties: ["product": "iPhone SE"]))
    }

    // MARK: - Absence

    /// A filter is a *requirement*, so a missing property is failure for every operator —
    /// negative ones included. Letting `notEquals` pass on absence would turn a filter
    /// into decoration and widen the campaign to everyone.
    func testMissingPropertyNeverMatches() {
        let operators: [FilterOperator] = [
            .equals, .notEquals, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .contains
        ]
        for op in operators {
            let filter = PropertyFilter(name: "absent", op: op, value: 100)
            XCTAssertFalse(filter.matches(properties: ["present": 100]),
                           "operator \(op) matched on a missing property")
        }
    }

    // MARK: - Wire names

    func testOperatorWireNamesAreCaseInsensitive() {
        XCTAssertEqual(FilterOperator(wireName: "Is"), .equals)
        XCTAssertEqual(FilterOperator(wireName: "is"), .equals)
        XCTAssertEqual(FilterOperator(wireName: "Equals"), .equals)
        XCTAssertEqual(FilterOperator(wireName: "IsNot"), .notEquals)
        XCTAssertEqual(FilterOperator(wireName: "notequals"), .notEquals)
        XCTAssertEqual(FilterOperator(wireName: "GreaterThan"), .greaterThan)
        XCTAssertEqual(FilterOperator(wireName: "GreaterThanOrEqual"), .greaterThanOrEqual)
        XCTAssertEqual(FilterOperator(wireName: "LessThan"), .lessThan)
        XCTAssertEqual(FilterOperator(wireName: "LessThanOrEqual"), .lessThanOrEqual)
        XCTAssertEqual(FilterOperator(wireName: "Contains"), .contains)
    }

    func testUnknownOperatorWireNameIsNil() {
        XCTAssertNil(FilterOperator(wireName: "Regex"))
        XCTAssertNil(FilterOperator(wireName: ""))
    }

    // MARK: - Dashboard enum names and Between

    func testDashboardEnumNamesParse() {
        XCTAssertEqual(FilterOperator(wireName: "Is"), .equals)
        XCTAssertEqual(FilterOperator(wireName: "Equals"), .equals)
        XCTAssertEqual(FilterOperator(wireName: "Greater"), .greaterThan)
        XCTAssertEqual(FilterOperator(wireName: "Less"), .lessThan)
        XCTAssertEqual(FilterOperator(wireName: "Between"), .between)
        XCTAssertEqual(FilterOperator(wireName: "Contains"), .contains)
        XCTAssertEqual(FilterOperator(wireName: "greater_than_or_equal"), .greaterThanOrEqual)
        XCTAssertEqual(FilterOperator(wireName: "gte"), .greaterThanOrEqual)
        XCTAssertNil(FilterOperator(wireName: "regex"))
    }

    func testBetweenIsInclusiveOnBothBounds() {
        let filter = PropertyFilter(name: "amount", op: .between, value: "20,30")
        XCTAssertTrue(filter.matches(properties: ["amount": 20]))
        XCTAssertTrue(filter.matches(properties: ["amount": 25]))
        XCTAssertTrue(filter.matches(properties: ["amount": 30]))
        XCTAssertFalse(filter.matches(properties: ["amount": 19.99]))
        XCTAssertFalse(filter.matches(properties: ["amount": 30.01]))
    }

    func testBetweenToleratesSpacesReversedBoundsAndLists() {
        XCTAssertTrue(PropertyFilter(name: "a", op: .between, value: " 20 , 30 ")
                        .matches(properties: ["a": 25]))
        XCTAssertTrue(PropertyFilter(name: "a", op: .between, value: "30,20")
                        .matches(properties: ["a": 25]))
        XCTAssertTrue(PropertyFilter(name: "a", op: .between, value: [20, 30])
                        .matches(properties: ["a": "25"]))
    }

    func testBetweenWithUnreadableBoundsNeverMatches() {
        XCTAssertFalse(PropertyFilter(name: "a", op: .between, value: "20")
                        .matches(properties: ["a": 25]))
        XCTAssertFalse(PropertyFilter(name: "a", op: .between, value: "low,high")
                        .matches(properties: ["a": 25]))
        XCTAssertFalse(PropertyFilter(name: "a", op: .between, value: "20,30")
                        .matches(properties: ["a": "many"]))
    }
}
