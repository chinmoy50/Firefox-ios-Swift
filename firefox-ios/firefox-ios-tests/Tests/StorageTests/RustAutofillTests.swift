// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import MozillaAppServices
import Shared
import XCTest

@testable import Storage

class RustAutofillTests: XCTestCase {
    var files: FileAccessor!
    var autofill: RustAutofill!
    var encryptionKey: String!

    override func setUp() {
        super.setUp()
        files = MockFiles()

        if let rootDirectory = try? files.getAndEnsureDirectory() {
            let databasePath = URL(fileURLWithPath: rootDirectory, isDirectory: true)
                .appendingPathComponent("testAutofill.db").path
            try? files.remove("testAutofill.db")

            if let key = try? createAutofillKey() {
                encryptionKey = key
            } else {
                XCTFail("Encryption key wasn't created")
            }

            autofill = RustAutofill(databasePath: databasePath)
            _ = autofill.reopenIfClosed()
        } else {
            XCTFail("Could not retrieve root directory")
        }
    }

    func addCreditCard(completion: @escaping (CreditCard?, Error?) -> Void) {
        let creditCard = UnencryptedCreditCardFields(
            ccName: "Jane Doe",
            ccNumber: "1234567890123456",
            ccNumberLast4: "3456",
            ccExpMonth: 03,
            ccExpYear: 2027,
            ccType: "Visa")
        return autofill.addCreditCard(creditCard: creditCard, completion: completion)
    }

    func addCreditCard() async throws -> CreditCard {
        let creditCard = UnencryptedCreditCardFields(
            ccName: "Jane Doe",
            ccNumber: "1234567890123456",
            ccNumberLast4: "3456",
            ccExpMonth: 03,
            ccExpYear: 2027,
            ccType: "Visa")

        return try await withCheckedThrowingContinuation { continuation in
            autofill.addCreditCard(creditCard: creditCard) { card, error in
                guard let card else {
                    continuation.resume(throwing: error ?? NSError(domain: "Couldn't add credit card", code: 0))
                    return
                }
                continuation.resume(returning: card)
            }
        }
    }

    func getCreditCard(id: String) async throws -> CreditCard {
        return try await withCheckedThrowingContinuation { continuation in
            autofill.getCreditCard(id: id) { card, error in
                guard let card else {
                    continuation.resume(throwing: error ?? NSError(domain: "Couldn't get credit card", code: 0))
                    return
                }
                continuation.resume(returning: card)
            }
        }
    }

    func updateCreditCard(id: String,
                          creditCard: UnencryptedCreditCardFields) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            autofill.updateCreditCard(id: id, creditCard: creditCard) { success, error in
                guard let success else {
                    continuation.resume(throwing: error ?? NSError(domain: "Couldn't update credit card", code: 0))
                    return
                }
                continuation.resume(returning: success)
            }
        }
    }

    func addAddress(completion: @escaping (Result<Address, Error>) -> Void) {
        let address = UpdatableAddressFields(
            name: "Jane Doe",
            organization: "",
            streetAddress: "123 Second Avenue",
            addressLevel3: "",
            addressLevel2: "Chicago, IL",
            addressLevel1: "",
            postalCode: "",
            country: "United States",
            tel: "",
            email: "")
        return autofill.addAddress(address: address, completion: completion)
    }

    func addAddress() async throws -> Address {
        return try await withCheckedThrowingContinuation { continuation in
            let address = UpdatableAddressFields(
                name: "Jane Doe",
                organization: "",
                streetAddress: "123 Second Avenue",
                addressLevel3: "",
                addressLevel2: "Chicago, IL",
                addressLevel1: "",
                postalCode: "",
                country: "United States",
                tel: "",
                email: "")
            autofill.addAddress(address: address) { result in
                switch result {
                case .success(let addressAdded):
                    continuation.resume(returning: addressAdded)
                    return
                case .failure(let error):
                    continuation.resume(throwing: error)
                    return
                }
            }
        }
    }

    func testAddAndGetAddress() {
        let expectationAddAddress = expectation(description: "Completes the add address operation")
        let expectationGetAddress = expectation(description: "Completes the get address operation")

        addAddress { result in
            switch result {
            case .success(let address):
                XCTAssertEqual(address.name, "Jane Doe")
                XCTAssertEqual(address.streetAddress, "123 Second Avenue")
                XCTAssertEqual(address.addressLevel2, "Chicago, IL")
                XCTAssertEqual(address.country, "United States")
                expectationAddAddress.fulfill()
                self.autofill.getAddress(id: address.guid) { retrievedAddress, getAddressError in
                    guard let retrievedAddress = retrievedAddress, getAddressError == nil else {
                        XCTFail("Failed to get address. Retrieved Address: \(String(describing: retrievedAddress)), Error: \(String(describing: getAddressError))")
                        expectationGetAddress.fulfill()
                        return
                    }
                    XCTAssertEqual(address.guid, retrievedAddress.guid)
                    expectationGetAddress.fulfill()
                }

            case .failure(let error):
                XCTFail("Failed to add address, Error: \(String(describing: error))")
                expectationAddAddress.fulfill()
                return
            }
        }

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testAddAndGetAddress() async throws {
        
    }

    func testListAllAddressesSuccess() {
        let expectationListAddresses = expectation(description: "Completes the list all addresses operation")

        autofill.listAllAddresses { addresses, error in
            XCTAssertNil(error, "Error should be nil")
            XCTAssertNotNil(addresses, "Addresses should not be nil")

            // Assert on individual addresses in the list
            for address in addresses ?? [] {
                XCTAssertEqual(address.name, "Jane Doe")
                XCTAssertEqual(address.streetAddress, "123 Second Avenue")
                XCTAssertEqual(address.addressLevel2, "Chicago, IL")
                XCTAssertEqual(address.country, "United States")
            }

            expectationListAddresses.fulfill()
        }

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testAddCreditCard() {
        let expectationAddCard = expectation(description: "completed add card")
        let expectationGetCard = expectation(description: "completed getting card")

        addCreditCard { creditCard, err in
            XCTAssertNotNil(creditCard)
            XCTAssertNil(err)
            expectationAddCard.fulfill()

            self.autofill.getCreditCard(id: creditCard!.guid) { card, error in
                XCTAssertNotNil(card)
                XCTAssertNil(err)
                XCTAssertEqual(creditCard!.guid, card!.guid)
                expectationGetCard.fulfill()
            }
        }

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testListCreditCards() {
        let expectationCardList = expectation(description: "getting empty card list")
        let expectationAddCard = expectation(description: "add card")
        let expectationGetCards = expectation(description: "getting card list")
        autofill.listCreditCards { cards, err in
            XCTAssertNotNil(cards)
            XCTAssertNil(err)
            XCTAssertEqual(cards!.count, 0)
            expectationCardList.fulfill()

            self.addCreditCard { creditCard, err in
                XCTAssertNotNil(creditCard)
                XCTAssertNil(err)
                expectationAddCard.fulfill()

                self.autofill.listCreditCards { cards, err in
                    XCTAssertNotNil(cards)
                    XCTAssertNil(err)
                    XCTAssertEqual(cards!.count, 1)
                    expectationGetCards.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testListAllAddressesEmpty() {
        let expectationListAddresses = expectation(
            description: "Completes the list all addresses operation for an empty list"
        )

        autofill.listAllAddresses { addresses, error in
            XCTAssertNil(error, "Error should be nil")
            XCTAssertNotNil(addresses, "Addresses should not be nil")
            XCTAssertEqual(addresses?.count, 0, "Addresses count should be 0 for an empty list")

            expectationListAddresses.fulfill()
        }

        waitForExpectations(timeout: 3, handler: nil)
    }

    func testUpdateCreditCard() async throws {
        let creditCard = try await addCreditCard()
        let card = try await getCreditCard(id: creditCard.guid)
        let updatedCreditCard = UnencryptedCreditCardFields(ccName: creditCard.ccName,
                                                            ccNumber: creditCard.ccNumberEnc,
                                                            ccNumberLast4: creditCard.ccNumberLast4,
                                                            ccExpMonth: creditCard.ccExpMonth,
                                                            ccExpYear: Int64(2028),
                                                            ccType: creditCard.ccType)
        let result = try await updateCreditCard(id: creditCard.guid, creditCard: updatedCreditCard)
        let updatedCardVal = try await getCreditCard(id: creditCard.guid)

        XCTAssertEqual(creditCard.guid, card.guid)
        XCTAssertTrue(result)
        XCTAssertEqual(updatedCardVal.ccExpYear, updatedCreditCard.ccExpYear)
    }

    func testDeleteCreditCard() {
        let expectationAddCard = expectation(description: "completed add card")
        let expectationGetCard = expectation(description: "completed getting card")
        let expectationDeleteCard = expectation(description: "delete card")
        let expectationCheckDeleteCard = expectation(description: "check that no card exist")

        addCreditCard { creditCard, err in
            XCTAssertNotNil(creditCard)
            XCTAssertNil(err)
            expectationAddCard.fulfill()

            self.autofill.getCreditCard(id: creditCard!.guid) { card, error in
                XCTAssertNotNil(card)
                XCTAssertNil(err)
                XCTAssertEqual(creditCard!.guid, card!.guid)
                expectationGetCard.fulfill()

                self.autofill.deleteCreditCard(id: card!.guid) { success, err in
                    XCTAssert(success)
                    XCTAssertNil(err)
                    expectationDeleteCard.fulfill()

                    self.autofill.getCreditCard(id: creditCard!.guid) { deletedCreditCard, error in
                        XCTAssertNil(deletedCreditCard)
                        XCTAssertNotNil(error)

                        let expectedError =
                        "NoSuchRecord(guid: \"\(creditCard!.guid)\")"
                        XCTAssertEqual(expectedError, "\(error!)")
                        expectationCheckDeleteCard.fulfill()
                    }
                }
            }
        }

        waitForExpectations(timeout: 3, handler: nil)
    }
}
