import Foundation

enum AppTab: String, Codable, CaseIterable, Hashable {
    case home
    case search
    case cart
    case orders
    case account
}

enum CatalogSourceType: String, Codable, CaseIterable, Hashable {
    case seeded
    case snapshot

    var label: String {
        switch self {
        case .seeded:
            return "Default Catalog"
        case .snapshot:
            return "Imported Catalog"
        }
    }
}

enum DeliveryMode: String, Codable, CaseIterable, Hashable {
    case delivery
    case pickup

    var label: String {
        switch self {
        case .delivery:
            return "Delivery"
        case .pickup:
            return "Pickup"
        }
    }
}

enum SearchSortOption: String, Codable, CaseIterable, Hashable {
    case relevance
    case priceLowToHigh
    case priceHighToLow
    case unitPrice

    var label: String {
        switch self {
        case .relevance:
            return "Relevance"
        case .priceLowToHigh:
            return "Price: Low to High"
        case .priceHighToLow:
            return "Price: High to Low"
        case .unitPrice:
            return "Unit Price"
        }
    }
}

enum AvailabilityFilter: String, Codable, CaseIterable, Hashable {
    case all
    case delivery
    case pickup

    var label: String {
        switch self {
        case .all:
            return "All"
        case .delivery:
            return "Delivery"
        case .pickup:
            return "Pickup"
        }
    }
}

enum SubstitutionPreferenceType: String, Codable, CaseIterable, Hashable {
    case bestMatch
    case refundItem
    case doNotReplace
    case specificReplacement

    var label: String {
        switch self {
        case .bestMatch:
            return "Best match"
        case .refundItem:
            return "Refund item"
        case .doNotReplace:
            return "Do not replace"
        case .specificReplacement:
            return "Specific replacement"
        }
    }
}

struct SubstitutionPreference: Codable, Hashable {
    var type: SubstitutionPreferenceType
    var replacementProductID: String?

    var summary: String {
        switch type {
        case .bestMatch:
            return "Best match"
        case .refundItem:
            return "Refund item"
        case .doNotReplace:
            return "Do not replace"
        case .specificReplacement:
            return replacementProductID == nil ? "Specific replacement" : "Specific replacement selected"
        }
    }
}

enum OrderStatus: String, Codable, CaseIterable, Hashable {
    case scheduled
    case placed
    case shopperAssigned = "shopper_assigned"
    case shopping
    case outForDelivery = "out_for_delivery"
    case readyForPickup = "ready_for_pickup"
    case delivered
    case pickedUp = "picked_up"
    case canceled

    var label: String {
        switch self {
        case .scheduled:
            return "Scheduled"
        case .placed:
            return "Order placed"
        case .shopperAssigned:
            return "Shopper assigned"
        case .shopping:
            return "Shopping"
        case .outForDelivery:
            return "Out for delivery"
        case .readyForPickup:
            return "Ready for pickup"
        case .delivered:
            return "Delivered"
        case .pickedUp:
            return "Picked up"
        case .canceled:
            return "Canceled"
        }
    }

    var isPast: Bool {
        self == .delivered || self == .pickedUp || self == .canceled
    }

    var isScheduled: Bool {
        self == .scheduled
    }

    var isCancellable: Bool {
        switch self {
        case .scheduled, .placed, .shopperAssigned:
            return true
        default:
            return false
        }
    }
}

struct Store: Identifiable, Codable, Hashable {
    let id: String
    let storeName: String
    let tagline: String
    let addressLine: String
    let etaText: String
    let distanceMiles: Double
    let supportsDelivery: Bool
    let supportsPickup: Bool
    let deliveryFee: Double
    let pickupFee: Double
    let accentColorHex: String

    func supports(mode: DeliveryMode) -> Bool {
        switch mode {
        case .delivery:
            return supportsDelivery
        case .pickup:
            return supportsPickup
        }
    }

    /// Dynamic ETA based on current time + distance-based offset
    var dynamicETA: String {
        let cal = Calendar.current
        let now = Date()
        // Base delivery time: 35-55 min + distance-based offset
        let baseMinutes = 35 + Int(distanceMiles * 6)
        guard cal.date(byAdding: .minute, value: baseMinutes, to: now) != nil else {
            return etaText
        }
        return "in \(baseMinutes) min"
    }
}

struct ProductCategory: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let displayOrder: Int
}

struct Product: Identifiable, Codable, Hashable {
    let id: String
    let storeID: String
    let productName: String
    let brand: String
    let categoryID: String
    let packageSize: String
    let price: Double
    let unitPrice: String
    let inStock: Bool
    let saleLabel: String?
    let dietaryTags: [String]
    let isOrganic: Bool
    let description: String
    let isRecommended: Bool
    let isBuyAgain: Bool

    var isOnSale: Bool {
        saleLabel != nil
    }

    var averageRating: Double {
        let seed = abs(id.hashValue)
        // Most products cluster 3.8-4.8, with a few outliers
        let base = Double(seed % 100)
        if base < 5 { return 2.8 + Double(seed % 8) / 10.0 }   // 5% low-rated
        if base < 15 { return 3.3 + Double(seed % 5) / 10.0 }  // 10% mediocre
        if base < 85 { return 3.9 + Double(seed % 10) / 10.0 }  // 70% good
        return 4.6 + Double(seed % 5) / 10.0                     // 15% excellent
    }

    var reviewCount: Int {
        let seed = abs(id.hashValue)
        // More varied: some new products have few reviews, popular ones have thousands
        let tier = seed % 100
        if tier < 20 { return 8 + (seed % 42) }        // newer products
        if tier < 60 { return 50 + (seed % 350) }      // typical
        if tier < 90 { return 200 + (seed % 1800) }    // well-known
        return 1500 + (seed % 8500)                      // bestsellers
    }
}

struct CartItem: Identifiable, Codable, Hashable {
    let productID: String
    var quantity: Int
    var substitutionPreference: SubstitutionPreference
    var note: String
    var addedAt: Date

    var id: String {
        productID
    }
}

struct DeliverySlot: Identifiable, Codable, Hashable {
    let id: String
    let mode: DeliveryMode
    let dayLabel: String
    let timeLabel: String
    let fee: Double
    let isAvailable: Bool

    var displayLabel: String {
        "\(dayLabel) • \(timeLabel)"
    }
}

struct Address: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let streetLine1: String
    let streetLine2: String
    let instructions: String
}

struct PaymentMethod: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let detail: String
    let isDefault: Bool
}

struct Promotion: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let badgeText: String
    let callToAction: String
}

struct MembershipStatus: Codable, Hashable {
    let tierName: String
    let savingsToDate: Double
    let nextBillingDate: Date
    let benefits: [String]
}

struct UserProfile: Codable, Hashable {
    let firstName: String
    let lastName: String
    let emailAddress: String
    let phoneNumber: String
    let addresses: [Address]
    let paymentMethods: [PaymentMethod]
    let savedStoreIDs: [String]
    var notificationsEnabled: Bool
}

struct CatalogSnapshotMetadata: Codable, Hashable {
    let providerLabel: String
    let sourceType: CatalogSourceType
    let snapshotTimestamp: Date
    let lastUpdated: Date
}

struct OrderStatusEvent: Identifiable, Codable, Hashable {
    let id: String
    let status: OrderStatus
    let timestamp: Date
    let message: String
}

struct PricingSummary: Codable, Hashable {
    let itemSubtotal: Double
    let deliveryFee: Double
    let priorityFee: Double
    let serviceFee: Double
    let taxEstimate: Double
    let tip: Double
    let promoDiscount: Double
    let estimatedTotal: Double
}

struct OrderItem: Identifiable, Codable, Hashable {
    let id: String
    let productID: String
    let productName: String
    let brand: String
    let packageSize: String
    let unitPrice: String
    let quantity: Int
    let price: Double
    let substitutionPreference: SubstitutionPreference
}

struct Order: Identifiable, Codable, Hashable {
    let id: String
    let orderNumber: String
    let storeID: String
    let items: [OrderItem]
    let deliveryMode: DeliveryMode
    let deliverySlot: DeliverySlot
    let address: Address
    let paymentMethod: PaymentMethod
    var orderStatus: OrderStatus
    var statusEvents: [OrderStatusEvent]
    let pricingSummary: PricingSummary
    var orderNotes: String
    var deliveryInstructions: String
    let createdAt: Date
    var updatedAt: Date
    var shopperRating: ShopperRating?

    // Checkout slots are relative to today; historical orders must use their own timeline.
    var scheduleDisplayLabel: String {
        guard orderStatus.isPast else { return deliverySlot.displayLabel }
        let finalDate = statusEvents
            .filter { $0.status == orderStatus }
            .map(\.timestamp)
            .max()
        let date = finalDate ?? createdAt
        let prefix = finalDate == nil ? "Placed" : orderStatus.label
        return "\(prefix) • \(AppFormatters.historicalOrderDate.string(from: date))"
    }

    var isActive: Bool {
        !orderStatus.isPast && !orderStatus.isScheduled
    }
}

struct ShopperRating: Codable, Hashable {
    var stars: Int
    var comment: String
    var tipAdjustment: Double?
}

struct CatalogData: Codable, Hashable {
    let metadata: CatalogSnapshotMetadata
    let stores: [Store]
    let categories: [ProductCategory]
    let products: [Product]
}

struct FreshCartState: Codable, Hashable {
    var selectedTab: AppTab
    var catalogSource: CatalogSourceType
    var selectedStoreID: String
    var deliveryMode: DeliveryMode
    var selectedAddressID: String
    var selectedPaymentMethodID: String
    var selectedDeliverySlotID: String
    var selectedPickupSlotID: String
    var recentSearches: [String]
    var savedProductIDs: [String]
    var cartItems: [CartItem]
    var storeCarts: [String: [CartItem]]
    var orders: [Order]
    var promotions: [Promotion]
    var membershipStatus: MembershipStatus
    var userProfile: UserProfile
    var tipAmount: Double
    var contactlessHandoff: Bool
    var orderNotes: String
    var specialInstructions: String
    var priorityDelivery: Bool
    var promoCode: String
    var promoApplied: Bool
    var orderSequence: Int
    var lastUpdated: Date
    var seedVersion: Int?
}
