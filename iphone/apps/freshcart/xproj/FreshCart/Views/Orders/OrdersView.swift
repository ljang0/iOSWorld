import SwiftUI

struct OrdersView: View {
    @ObservedObject var viewModel: OrdersViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ordersHeader

                VStack(alignment: .leading, spacing: 20) {
                    if viewModel.activeOrders.isEmpty && viewModel.scheduledOrders.isEmpty {
                        EmptyStateCard(
                            title: "No active orders",
                            subtitle: "Place an order from the cart to start tracking it.",
                            accessibilityIdentifier: "no_active_orders_state"
                        )
                    } else {
                        if viewModel.activeOrders.isEmpty == false {
                            orderSection(title: "Active", orders: viewModel.activeOrders)
                        }
                        if viewModel.scheduledOrders.isEmpty == false {
                            orderSection(title: "Scheduled", orders: viewModel.scheduledOrders)
                        }
                    }

                    if viewModel.pastOrders.isEmpty {
                        EmptyStateCard(
                            title: "No past orders",
                            subtitle: "Completed and canceled orders appear here.",
                            accessibilityIdentifier: "no_past_orders_state"
                        )
                    } else {
                        orderSection(title: "Past orders", orders: viewModel.pastOrders)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.instacartBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var ordersHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your orders")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(Color.instacartGreenDark)
    }

    private func orderSection(title: String, orders: [Order]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 20, weight: .heavy))

            ForEach(orders) { order in
                NavigationLink {
                    OrderDetailView(viewModel: viewModel, orderID: order.id)
                } label: {
                    OrderRowCard(order: order, storeName: viewModel.storeName(for: order), store: viewModel.store.store(with: order.storeID))
                }
                .buttonStyle(.plain)
                // Per-order accessibility id so callers can target a row by
                // its order id directly. The previous chip-only tap path
                // (`order_status_chip_<status>`) was ambiguous when two
                // orders shared a status (e.g. both `order_scheduled_002`
                // and `order_scheduled_008` are `.scheduled`).
                .accessibilityIdentifier("order_row_\(AccessibilityID.slug(order.id))")
            }
        }
    }
}

private struct OrderRowCard: View {
    let order: Order
    let storeName: String
    let store: Store?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let store {
                    StoreLogoBadge(store: store)
                        .frame(width: 48, height: 48)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.instacartGreenDark)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(storeName.prefix(1)))
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundStyle(.white)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(storeName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(order.scheduleDisplayLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                OrderStatusChipView(status: order.orderStatus)
            }

            Text(order.items.map(\.productName).joined(separator: ", "))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text("\(order.items.count) item\(order.items.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.secondary)

                Text(AppFormatters.currencyString(order.pricingSummary.estimatedTotal))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

private struct OrderDetailView: View {
    @ObservedObject var viewModel: OrdersViewModel
    let orderID: String

    @Environment(\.dismiss) private var dismiss

    @State private var ratingStars: Int = 5
    @State private var ratingComment: String = ""
    @State private var ratingSubmitted: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let order = currentOrder {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard(order)

                    // Feature 9: Map placeholder for active delivery/pickup
                    if order.orderStatus == .outForDelivery || order.orderStatus == .readyForPickup {
                        mapPlaceholderCard(order)
                    }

                    statusTimelineCard(order)
                    itemsCard(order)
                    pricingCard(order)

                    // Feature 8: Rating card for completed orders
                    if order.orderStatus == .delivered || order.orderStatus == .pickedUp {
                        ratingCard(order)
                    }

                    actionsCard(order)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .background(Color.instacartBackground.ignoresSafeArea())
        .navigationTitle("Order details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentOrder: Order? {
        viewModel.store.state.orders.first(where: { $0.id == orderID })
    }

    private func headerCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if let store = viewModel.store.store(with: order.storeID) {
                    StoreLogoBadge(store: store)
                        .frame(width: 52, height: 52)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.storeName(for: order))
                        .font(.system(size: 20, weight: .heavy))
                    Text("Order \(order.orderNumber)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                OrderStatusChipView(status: order.orderStatus)
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: order.deliveryMode == .delivery ? "bag" : "storefront")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.instacartGreen)
                Text(order.deliveryMode.label)
                    .font(.system(size: 14, weight: .semibold))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(order.scheduleDisplayLabel)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(order.address.streetLine1)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            if order.deliveryInstructions.isEmpty == false {
                Text(order.deliveryInstructions)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func statusTimelineCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tracking")
                .font(.system(size: 18, weight: .heavy))

            ForEach(Array(order.statusEvents.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(Color.instacartGreen)
                            .frame(width: 12, height: 12)
                        if index < order.statusEvents.count - 1 {
                            Rectangle()
                                .fill(Color.instacartGreen.opacity(0.3))
                                .frame(width: 2)
                                .frame(minHeight: 30)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.status.label)
                            .font(.system(size: 15, weight: .semibold))
                        Text(event.message)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(AppFormatters.dateTime.string(from: event.timestamp))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func itemsCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Items")
                .font(.system(size: 18, weight: .heavy))

            ForEach(order.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        if let product = viewModel.store.product(with: item.productID) {
                            ProductArtView(product: product, cornerRadius: 8)
                                .frame(width: 48, height: 48)
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.instacartChip)
                                .frame(width: 48, height: 48)
                        }
                        Text("\(item.quantity)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.instacartGreenDark))
                            .offset(x: -6, y: -6)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.productName)
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(item.brand) · \(item.packageSize)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(AppFormatters.currencyString(item.price * Double(item.quantity)))
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityIdentifier(AccessibilityID.priceLabel("order_item_\(item.productID)"))
                }
                .padding(.vertical, 4)

                if item.id != order.items.last?.id {
                    Divider()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func pricingCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Summary")
                .font(.system(size: 18, weight: .heavy))

            priceRow("Item subtotal", order.pricingSummary.itemSubtotal, id: AccessibilityID.priceLabel("order_item_subtotal"))
            priceRow("Delivery fee", order.pricingSummary.deliveryFee, id: AccessibilityID.priceLabel("order_delivery_fee"))
            if order.pricingSummary.priorityFee > 0 {
                priceRow("Priority fee", order.pricingSummary.priorityFee, id: AccessibilityID.priceLabel("order_priority_fee"))
            }
            priceRow("Service fee", order.pricingSummary.serviceFee, id: AccessibilityID.priceLabel("order_service_fee"))
            priceRow("Tax estimate", order.pricingSummary.taxEstimate, id: AccessibilityID.priceLabel("order_tax_estimate"))
            priceRow("Tip", order.pricingSummary.tip, id: AccessibilityID.priceLabel("order_tip"))
            if order.pricingSummary.promoDiscount > 0 {
                priceRow("Promo discount", -order.pricingSummary.promoDiscount, id: AccessibilityID.priceLabel("order_promo_discount"))
            }

            Divider()

            priceRow("Estimated total", order.pricingSummary.estimatedTotal, id: AccessibilityID.priceLabel("order_total"), emphasized: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func mapPlaceholderCard(_ order: Order) -> some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.instacartGreen.opacity(0.08))
                    .frame(height: 140)

                VStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.instacartGreen)
                    Text(order.orderStatus == .outForDelivery ? "Your shopper is on the way" : "Your order is ready for pickup")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.instacartGreenDark)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.instacartGreen)
                Text(order.address.streetLine1)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func ratingCard(_ order: Order) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if order.shopperRating != nil || ratingSubmitted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.instacartGreen)
                    Text("Thanks for rating your shopper!")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.instacartGreenDark)
                }
            } else {
                Text("Rate your shopper")
                    .font(.system(size: 18, weight: .heavy))

                Text("How was your experience?")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Button {
                            ratingStars = star
                        } label: {
                            Image(systemName: star <= ratingStars ? "star.fill" : "star")
                                .font(.system(size: 28))
                                .foregroundStyle(star <= ratingStars ? Color.instacartYellow : Color.gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)

                TextField("Leave a comment (optional)", text: $ratingComment)
                    .font(.system(size: 14))
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.instacartChip))

                Button {
                    let rating = ShopperRating(stars: ratingStars, comment: ratingComment, tipAdjustment: nil)
                    viewModel.rateOrder(order.id, rating: rating)
                    ratingSubmitted = true
                } label: {
                    Text("Submit rating")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.instacartGreen))
                }
                .accessibilityIdentifier("submit_shopper_rating_button")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white)
        )
    }

    private func actionsCard(_ order: Order) -> some View {
        VStack(spacing: 12) {
            Button {
                viewModel.reorder(order.id)
                dismiss()
            } label: {
                Text("Reorder items")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.instacartGreen))
            }
            .accessibilityIdentifier("reorder_order_button_\(AccessibilityID.slug(order.id))")

            if order.orderStatus.isCancellable {
                Button {
                    viewModel.cancelOrder(order.id)
                } label: {
                    Text("Cancel order")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.red.opacity(0.08)))
                }
                .accessibilityIdentifier("cancel_order_button_\(AccessibilityID.slug(order.id))")
            }

            if order.orderStatus.isPast == false {
                Button {
                    viewModel.advanceOrder(order.id)
                } label: {
                    Text("Advance order state")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.instacartGreenDark)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.instacartGreenDark, lineWidth: 1.5))
                }
                .accessibilityIdentifier("advance_order_state_button_\(AccessibilityID.slug(order.id))")
            }
        }
    }

    private func priceRow(_ title: String, _ value: Double, id: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? .system(size: 16, weight: .heavy) : .system(size: 15, weight: .medium))
            Spacer()
            Text(AppFormatters.currencyString(value))
                .font(emphasized ? .system(size: 16, weight: .heavy) : .system(size: 15, weight: .medium))
                .accessibilityIdentifier(id)
        }
    }
}
