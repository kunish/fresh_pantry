import Foundation
import Testing
@testable import FreshPantry

/// Hermetic tests for `OpenFoodFactsService` — the network paths are driven by a
/// stubbed `URLProtocol` (no live OFF calls), and the user-visible scoring /
/// category-keyword / nutriment logic (INVARIANTS #9/#10) is exercised directly.
@MainActor
@Suite(.serialized)
struct OpenFoodFactsServiceTests {
    // MARK: Stub plumbing (mirrors AiClientTests)

    final class StubURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = Self.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    /// Respond by matching the request URL against substrings → (status, body).
    /// Any unmatched URL returns 404 (so the SearchALicious fallback can be
    /// exercised or a clean miss simulated).
    private func respond(_ routes: [(match: String, status: Int, body: String)]) {
        StubURLProtocol.handler = { request in
            let urlString = request.url?.absoluteString ?? ""
            for route in routes where urlString.contains(route.match) {
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: nil
                )!
                return (response, Data(route.body.utf8))
            }
            let notFound = HTTPURLResponse(
                url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil
            )!
            return (notFound, Data("{}".utf8))
        }
    }

    private let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Barcode lookup → parsed FoodDetails

    @Test func barcodeLookupParsesNutritionAndCategory() async throws {
        respond([(
            match: "/api/v2/product/",
            status: 200,
            body: #"""
            {"product": {
                "product_name": "Cheddar Cheese",
                "generic_name": "Aged cheddar",
                "categories_tags": ["en:dairies", "en:cheeses"],
                "image_front_small_url": "https://img.example/cheese.jpg",
                "completeness": 0.9,
                "nutriments": {
                    "energy-kcal_100g": 402,
                    "proteins_100g": 25,
                    "carbohydrates_100g": 1.3,
                    "fat_100g": 33
                }
            }}
            """#
        )])

        let details = await OpenFoodFactsService.lookupDetails(
            name: "奶酪", barcode: "1234567890123", fetchedAt: fetchedAt, session: stubbedSession()
        )

        let unwrapped = try #require(details)
        #expect(unwrapped.source == "Open Food Facts")
        // Barcode path: product_name wins (preferFallbackDisplayName=false).
        #expect(unwrapped.displayName == "Cheddar Cheese")
        // "en:cheeses" contains "cheese" → 乳品蛋类.
        #expect(unwrapped.category == FoodCategories.dairyAndEggs)
        #expect(unwrapped.imageUrl == "https://img.example/cheese.jpg")
        // generic_name present → used as description.
        #expect(unwrapped.description == "Aged cheddar")
        let nutrition = try #require(unwrapped.nutrition)
        #expect(nutrition.energyKcal == 402)
        #expect(nutrition.protein == 25)
        #expect(nutrition.carbs == 1.3)
        #expect(nutrition.fat == 33)
    }

    @Test func barcodeLookup404ReturnsNil() async {
        respond([(match: "/api/v2/product/", status: 404, body: "{}")])
        let details = await OpenFoodFactsService.lookupDetails(
            name: "奶酪", barcode: "0000", fetchedAt: fetchedAt, session: stubbedSession()
        )
        #expect(details == nil)
    }

    // MARK: Name search → bestProduct picks the highest score

    @Test func nameSearchPicksBestScoredProduct() async throws {
        // Three candidates: the exact-name + image + complete one must win over a
        // longer noisy name and an incomplete one.
        respond([(
            match: "/cgi/search.pl",
            status: 200,
            body: #"""
            {"products": [
                {"product_name": "tomato ketchup deluxe sauce extra", "completeness": 0.9,
                 "image_front_small_url": "https://img/x.jpg"},
                {"product_name": "tomato", "completeness": 0.9,
                 "image_front_small_url": "https://img/tomato.jpg"},
                {"product_name": "tomato", "completeness": 0.1}
            ]}
            """#
        )])

        let details = await OpenFoodFactsService.lookupDetails(
            name: "tomato", fetchedAt: fetchedAt, session: stubbedSession()
        )
        let unwrapped = try #require(details)
        // Name path with preferFallbackDisplayName=true → fallbackName wins display.
        #expect(unwrapped.displayName == "tomato")
        #expect(unwrapped.imageUrl == "https://img/tomato.jpg")
    }

    @Test func nameSearchFallsBackToSearchAliciousWhenLegacyEmpty() async throws {
        respond([
            (match: "/cgi/search.pl", status: 200, body: #"{"products": []}"#),
            (match: "/search.openfoodfacts.org/search", status: 200, body: #"""
            {"hits": [
                {"product_name": "apple", "completeness": 0.8,
                 "image_front_small_url": "https://img/apple.jpg"}
            ]}
            """#),
        ])

        let details = await OpenFoodFactsService.lookupDetails(
            name: "apple", fetchedAt: fetchedAt, session: stubbedSession()
        )
        let unwrapped = try #require(details)
        #expect(unwrapped.displayName == "apple")
        #expect(unwrapped.imageUrl == "https://img/apple.jpg")
    }

    @Test func nameSearchAllEmptyReturnsNil() async {
        respond([
            (match: "/cgi/search.pl", status: 200, body: #"{"products": []}"#),
            (match: "/search.openfoodfacts.org/search", status: 200, body: #"{"hits": []}"#),
        ])
        let details = await OpenFoodFactsService.lookupDetails(
            name: "definitelynotafood", fetchedAt: fetchedAt, session: stubbedSession()
        )
        #expect(details == nil)
    }

    // MARK: searchByName

    @Test func searchByNameReturnsProductAndImage() async throws {
        respond([(
            match: "/cgi/search.pl",
            status: 200,
            body: #"{"products": [{"product_name": "Banana", "image_front_small_url": "https://img/b.jpg"}]}"#
        )])
        let result = await OpenFoodFactsService.searchByName("banana", session: stubbedSession())
        let unwrapped = try #require(result)
        #expect(unwrapped.productName == "Banana")
        #expect(unwrapped.imageUrl == "https://img/b.jpg")
    }

    @Test func searchByNameEmptyReturnsNil() async {
        respond([(match: "/cgi/search.pl", status: 200, body: #"{"products": []}"#)])
        let result = await OpenFoodFactsService.searchByName("nothing", session: stubbedSession())
        #expect(result == nil)
    }

    // MARK: Category keyword mapping (FIRST-match wins, INVARIANT #10)

    @Test func resolveCategoryMapsCheeseToDairy() {
        #expect(OpenFoodFactsService.resolveCategory(["en:cheeses"]) == FoodCategories.dairyAndEggs)
    }

    @Test func resolveCategoryMapsFreshVegetablesToProduce() {
        // "en:fresh-vegetables" — "fresh" is the FIRST mapping key it contains and
        // also maps to 果蔬生鲜.
        #expect(OpenFoodFactsService.resolveCategory(["en:fresh-vegetables"]) == FoodCategories.freshProduce)
    }

    @Test func resolveCategoryMapsMeatToMeatAndSeafood() {
        #expect(OpenFoodFactsService.resolveCategory(["en:meats"]) == FoodCategories.meatAndSeafood)
    }

    @Test func resolveCategoryUnmappedReturnsNil() {
        // "en:unknown" contains none of the ~50 keyword substrings → no match.
        #expect(OpenFoodFactsService.resolveCategory(["en:unknown"]) == nil)
        #expect(OpenFoodFactsService.resolveCategory([]) == nil)
        #expect(OpenFoodFactsService.resolveCategory(nil) == nil)
    }

    @Test func unmappedTagFallsBackToFoodKnowledge() {
        // categories_tags resolves to nil → productToFoodDetails uses
        // FoodKnowledge.categoryFor("牛奶") = 乳品蛋类.
        let product: [String: Any] = [
            "product_name": "Some Milk",
            "categories_tags": ["en:unknown"],
        ]
        let details = OpenFoodFactsService.productToFoodDetails(
            product, fallbackName: "牛奶", fetchedAt: fetchedAt, preferFallbackDisplayName: false
        )
        #expect(details?.category == FoodCategories.dairyAndEggs)
    }

    // MARK: Quality score formula (user-visible best-match selection)

    @Test func qualityScoreRewardsImageCompletenessAndExactName() {
        let exact: [String: Any] = [
            "product_name": "tomato",
            "completeness": 1.0,
            "image_front_small_url": "https://img/x.jpg",
        ]
        // image 80 + completeness 1*30 + name 10 + exact 70 = 190.
        #expect(OpenFoodFactsService.productQualityScore(exact, fallbackName: "tomato") == 190)
    }

    @Test func qualityScorePenalizesLowCompleteness() {
        let sparse: [String: Any] = ["product_name": "tomato", "completeness": 0.1]
        // no image; completeness 0.1*30=3, <0.25 → -100; name 10 + exact 70 = -17.
        #expect(OpenFoodFactsService.productQualityScore(sparse, fallbackName: "tomato") == -17)
    }

    @Test func qualityScorePenalizesExtraNameLength() {
        let long: [String: Any] = ["product_name": "tomatoes"]
        // name 10 + contains "tomato" 50 + extraLength(8-6=2)*-5=-10 = 50.
        #expect(OpenFoodFactsService.productQualityScore(long, fallbackName: "tomato") == 50)
    }

    // MARK: Nutriment parsing (exact OFF keys, INVARIANT #10)

    @Test func nutritionForProductParsesExactKeys() throws {
        let product: [String: Any] = [
            "nutriments": [
                "energy-kcal_100g": 89,
                "proteins_100g": "1.1",   // string form tolerated
                "carbohydrates_100g": 22.8,
                "fat_100g": 0.3,
            ],
        ]
        let nutrition = try #require(OpenFoodFactsService.nutritionForProduct(product))
        #expect(nutrition.energyKcal == 89)
        #expect(nutrition.protein == 1.1)
        #expect(nutrition.carbs == 22.8)
        #expect(nutrition.fat == 0.3)
    }

    @Test func nutritionForProductNilWhenNoMacros() {
        #expect(OpenFoodFactsService.nutritionForProduct(["nutriments": [:]]) == nil)
        #expect(OpenFoodFactsService.nutritionForProduct([:]) == nil)
    }

    // MARK: searchTermsFor includes the FoodKnowledge English name

    @Test func searchTermsForIncludesEnglishName() {
        // "牛奶" → English "milk"; distinct → both terms.
        #expect(OpenFoodFactsService.searchTermsFor("牛奶") == ["牛奶", "milk"])
    }

    @Test func searchTermsForOmitsDuplicateEnglishName() {
        // "milk" has no Chinese→English distinct mapping → single term.
        #expect(OpenFoodFactsService.searchTermsFor("milk") == ["milk"])
    }
}
