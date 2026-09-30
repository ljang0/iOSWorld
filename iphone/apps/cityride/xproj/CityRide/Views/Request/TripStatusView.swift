import SwiftUI

struct TripStatusView: View {
    @ObservedObject var store: CityRideStore
    let tripID: String
    @State private var showReceipt = false
    @State private var showCallOverlay = false
    @State private var showChat = false
    @State private var etaCountdown: Int?
    @State private var etaTimer: Timer?

    var body: some View {
        ScrollView {
            if let trip = trip {
                VStack(alignment: .leading, spacing: 14) {
                    mapSurface
                    statusHeader(for: trip)
                    stageChips(current: trip.tripStatus)
                    routeCard(for: trip)
                    driverCard(for: trip)
                    actions(for: trip)
                }
                .padding(16)
                .onChange(of: trip.tripStatus) { _, newStatus in
                    if newStatus == .tripCompleted {
                        showReceipt = true
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Text("Trip not found")
                    Text("Open Activity to review existing trips.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                .padding(24)
                .accessibilityIdentifier("trip_status_trip_not_found")
            }
        }
        .background(CityRideTheme.background)
        .navigationTitle("Trip Status")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReceipt) {
            if let trip = trip, let receipt = store.receipt(for: trip.id) {
                RideReceiptSheet(store: store, trip: trip, receipt: receipt) {
                    showReceipt = false
                }
            }
        }
        .fullScreenCover(isPresented: $showCallOverlay) {
            if let driver = trip?.driver {
                DriverCallOverlay(driverName: driver.driverName) {
                    showCallOverlay = false
                }
            }
        }
        .sheet(isPresented: $showChat) {
            if let driver = trip?.driver {
                DriverChatSheet(driverName: driver.driverName)
            }
        }
        // Presentation and trip creation can arrive in separate SwiftUI updates.
        // Initialize when the actual trip becomes available, including on entry.
        .onChange(of: trip?.id, initial: true) { _, _ in
            if let trip = trip {
                etaCountdown = trip.etaMinutes
                startETATimer()
            }
        }
        .onDisappear {
            etaTimer?.invalidate()
            etaTimer = nil
        }
    }

    private func startETATimer() {
        etaTimer?.invalidate()
        etaTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            if let remaining = etaCountdown, remaining > 1 {
                etaCountdown = remaining - 1
            } else {
                etaTimer?.invalidate()
                etaTimer = nil
            }
        }
    }

    private func etaDisplayText(for trip: Trip) -> String {
        switch trip.tripStatus {
        case .tripCompleted:
            return "Arrived"
        case .canceled:
            return "Canceled"
        case .tripInProgress:
            return "\(max(1, etaCountdown ?? trip.etaMinutes)) min"
        default:
            return "ETA \(max(1, etaCountdown ?? trip.etaMinutes)) min"
        }
    }

    private var trip: Trip? {
        store.state.trips.first(where: { $0.id == tripID })
    }

    private var mapSurface: some View {
        RouteMapView(
            pickupName: trip?.pickupName ?? "",
            destinationName: trip?.destinationName ?? "",
            places: store.state.places,
            driverProgress: showsDriverMarker ? driverProgress : nil,
            lineWidth: 6
        )
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CityRideTheme.cardBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("trip_status_map_surface")
    }

    private func stageChips(current: TripStatus) -> some View {
        let stages = stagesForDisplay(current: current)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stages, id: \.self) { stage in
                    Text(stage.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(chipBackground(stage: stage, current: current), in: Capsule())
                        .foregroundStyle(stage == current ? Color.black : Color.white)
                        .accessibilityIdentifier("trip_stage_chip_\(stage.rawValue)")
                }
            }
        }
    }

    private func statusHeader(for trip: Trip) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.tripStatus.label)
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier(trip.tripStatus.chipIdentifier)
                Text("\(trip.pickupName) to \(trip.destinationName)")
                    .font(.subheadline)
                    .foregroundStyle(CityRideTheme.muted)
                    .accessibilityIdentifier("trip_status_route_label")
            }
            Spacer()
            Text(etaDisplayText(for: trip))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(statusColor(for: trip.tripStatus).opacity(0.25), in: Capsule())
                .overlay(Capsule().stroke(statusColor(for: trip.tripStatus).opacity(0.45), lineWidth: 1))
                .accessibilityIdentifier("trip_status_eta_label")
        }
        .padding(12)
        .uberCard(radius: 14)
    }

    private func routeCard(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trip")
                .font(.headline)
                .accessibilityIdentifier("trip_status_trip_title")
            detailRow(label: "Ride", value: trip.rideType)
            detailRow(label: "Price", value: AppFormatters.price(trip.estimatedPrice, currencyCode: trip.currency), id: "trip_status_price_label")
            detailRow(label: "Route", value: trip.routeLabel)
        }
        .padding(12)
        .uberCard(radius: 14)
    }

    private func driverCard(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let driver = trip.driver, let vehicle = trip.vehicle {
                HStack {
                    Text("Driver")
                        .font(.headline)
                        .accessibilityIdentifier("trip_status_driver_title")
                    Spacer()
                    HStack(spacing: 12) {
                        Button {
                            showCallOverlay = true
                        } label: {
                            Image(systemName: "phone.fill")
                                .font(.subheadline)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.10), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trip_status_call_driver")

                        Button {
                            showChat = true
                        } label: {
                            Image(systemName: "message.fill")
                                .font(.subheadline)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.10), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trip_status_message_driver")
                    }
                }
                detailRow(label: "Name", value: driver.driverName, id: "trip_status_driver_name")
                detailRow(label: "Vehicle", value: "\(vehicle.color) \(vehicle.make) \(vehicle.model)", id: "trip_status_vehicle_label")
                detailRow(label: "Plate", value: vehicle.licensePlate, id: "trip_status_plate_label")
                detailRow(label: "Rating", value: String(format: "%.2f", driver.rating), id: "trip_status_driver_rating")
            } else {
                Text("Matching with a nearby driver...")
                    .font(.subheadline)
                    .foregroundStyle(CityRideTheme.muted)
                    .accessibilityIdentifier("trip_status_matching_state")
            }
        }
        .padding(12)
        .uberCard(radius: 14)
    }

    private func actions(for trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if trip.isActive {
                Button {
                    store.postStatusMessage("Trip status shared.")
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline)
                        Text("Share trip status")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip_status_share_button")
            }

            let canMarkCompleted = trip.tripStatus == .driverArriving || trip.tripStatus == .driverAtPickup || trip.tripStatus == .tripInProgress
            if trip.tripStatus == .reserved {
                Button("Start Reserved Ride") {
                    store.startReservedTrip(trip.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .accessibilityIdentifier("trip_start_reserved_button")
            } else {
                Button("Advance Trip Stage") {
                    store.advanceTrip(tripID: trip.id)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .disabled(!trip.tripStatus.canAdvance)
                .accessibilityIdentifier("trip_advance_stage_button")
            }

            Button("Mark Completed") {
                store.completeTrip(tripID: trip.id)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!canMarkCompleted)
            .accessibilityIdentifier("trip_complete_button")

            if !canMarkCompleted && trip.tripStatus != .tripCompleted && trip.tripStatus != .canceled {
                Text("Advance the trip until pickup to mark it completed.")
                    .font(.caption)
                    .foregroundStyle(CityRideTheme.muted)
                    .accessibilityIdentifier("trip_complete_unavailable_hint")
            }

            Button("Cancel Ride") {
                store.cancelTrip(tripID: trip.id)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(!trip.isCancelable)
            .accessibilityIdentifier("trip_cancel_button")

            if let message = store.inlineStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(CityRideTheme.muted)
                    .accessibilityIdentifier("trip_status_message")
            }
        }
    }

    private func detailRow(label: String, value: String, id: String? = nil) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(CityRideTheme.muted)
            Spacer()
            if let id {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(id)
            } else {
                Text(value)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.subheadline)
    }

    private var showsDriverMarker: Bool {
        guard let trip else { return false }
        return trip.tripStatus != .reserved && trip.tripStatus != .tripCompleted && trip.tripStatus != .canceled
    }

    private var driverProgress: CGFloat {
        guard let trip else { return 0.10 }
        switch trip.tripStatus {
        case .requesting:
            return 0.10
        case .driverAssigned:
            return 0.18
        case .driverArriving:
            return 0.30
        case .driverAtPickup:
            return 0.42
        case .tripInProgress:
            return 0.72
        case .tripCompleted:
            return 1.0
        case .canceled:
            return 0.20
        case .reserved:
            return 0.0
        }
    }

    private func chipBackground(stage: TripStatus, current: TripStatus) -> Color {
        if stage == current {
            return .white
        }

        let stages = stagesForDisplay(current: current)
        if stages.firstIndex(of: stage) ?? 0 < stages.firstIndex(of: current) ?? 0 {
            return Color.white.opacity(0.30)
        }

        return Color.white.opacity(0.08)
    }

    private func stagesForDisplay(current: TripStatus) -> [TripStatus] {
        var base: [TripStatus] = [.requesting, .driverAssigned, .driverArriving, .driverAtPickup, .tripInProgress, .tripCompleted]
        if current == .reserved {
            base.insert(.reserved, at: 0)
        }
        if current == .canceled {
            base.append(.canceled)
        }
        return base
    }

    private func statusColor(for status: TripStatus) -> Color {
        switch status {
        case .requesting, .driverAssigned, .driverArriving, .driverAtPickup:
            return CityRideTheme.accent
        case .tripInProgress:
            return .orange
        case .tripCompleted:
            return .green
        case .canceled:
            return .red
        case .reserved:
            return .indigo
        }
    }
}

// MARK: - Ride Receipt Sheet

private struct RideReceiptSheet: View {
    let store: CityRideStore
    let trip: Trip
    let receipt: RideReceipt
    let onDismiss: () -> Void

    private var paymentMethod: PaymentMethod? {
        store.walletPaymentMethods.first(where: { $0.id == trip.paymentMethodId })
    }

    private var myBankAccount: CheckoutPaymentAccount? {
        guard let method = paymentMethod else { return nil }
        return store.myBankAccountForPaymentMethod(method)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    completionHeader
                    routeSection
                    rideInfoSection
                    driverSection
                    fareBreakdown
                    paymentSection
                    receiptMeta
                    doneButton
                }
                .padding(20)
            }
            .background(CityRideTheme.background)
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var completionHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
                .accessibilityIdentifier("receipt_checkmark_icon")
            Text("Trip Complete")
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("receipt_title")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route")
                .font(.headline)
                .accessibilityIdentifier("receipt_route_title")
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1.5, height: 20)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 8, height: 8)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text(trip.pickupName)
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("receipt_pickup_name")
                    Text(trip.destinationName)
                        .font(.subheadline.weight(.medium))
                        .accessibilityIdentifier("receipt_destination_name")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var rideInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ride Details")
                .font(.headline)
                .accessibilityIdentifier("receipt_ride_details_title")
            receiptDetailRow(label: "Ride type", value: trip.rideType, id: "receipt_ride_type")
            receiptDetailRow(label: "Route", value: trip.routeLabel, id: "receipt_route_label")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var driverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Driver")
                .font(.headline)
                .accessibilityIdentifier("receipt_driver_title")
            if let driver = trip.driver, let vehicle = trip.vehicle {
                receiptDetailRow(label: "Name", value: driver.driverName, id: "receipt_driver_name")
                receiptDetailRow(label: "Vehicle", value: "\(vehicle.color) \(vehicle.make) \(vehicle.model)", id: "receipt_vehicle")
                receiptDetailRow(label: "Rating", value: String(format: "%.2f", driver.rating), id: "receipt_driver_rating")
            } else {
                Text("Driver info unavailable")
                    .font(.subheadline)
                    .foregroundStyle(CityRideTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var fareBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fare Breakdown")
                .font(.headline)
                .accessibilityIdentifier("receipt_fare_title")
            receiptDetailRow(label: "Base fare", value: AppFormatters.price(receipt.baseFare, currencyCode: receipt.currency), id: "receipt_base_fare")
            receiptDetailRow(label: "Fees", value: AppFormatters.price(receipt.fees, currencyCode: receipt.currency), id: "receipt_fees")
            receiptDetailRow(label: "Taxes", value: AppFormatters.price(receipt.taxes, currencyCode: receipt.currency), id: "receipt_taxes")
            if receipt.tip > 0 {
                receiptDetailRow(label: "Tip", value: AppFormatters.price(receipt.tip, currencyCode: receipt.currency), id: "receipt_tip")
            }
            Divider().overlay(CityRideTheme.cardBorder)
            receiptDetailRow(label: "Total", value: AppFormatters.price(receipt.receiptTotal, currencyCode: receipt.currency), id: "receipt_total")
                .font(.subheadline.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var paymentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment")
                .font(.headline)
                .accessibilityIdentifier("receipt_payment_title")
            if let method = paymentMethod {
                HStack(spacing: 8) {
                    Image(systemName: "creditcard.fill")
                        .font(.subheadline)
                        .foregroundStyle(CityRideTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(method.cardLabel)
                            .font(.subheadline)
                            .accessibilityIdentifier("receipt_payment_card_label")
                        if let account = myBankAccount {
                            Text("\(account.network) \u{00B7} \(account.name) (MyBank)")
                                .font(.caption)
                                .foregroundStyle(CityRideTheme.muted)
                                .accessibilityIdentifier("receipt_payment_mybank_label")
                        }
                    }
                    Spacer()
                }
            } else {
                Text("Payment method")
                    .font(.subheadline)
                    .foregroundStyle(CityRideTheme.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var receiptMeta: some View {
        VStack(alignment: .leading, spacing: 8) {
            receiptDetailRow(label: "Receipt number", value: receipt.id, id: "receipt_number")
            receiptDetailRow(label: "Date", value: AppFormatters.shortDateTime.string(from: receipt.generatedAt), id: "receipt_date")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .uberCard(radius: 14)
    }

    private var doneButton: some View {
        Button {
            onDismiss()
        } label: {
            Text("Done")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("receipt_done_button")
    }

    private func receiptDetailRow(label: String, value: String, id: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(CityRideTheme.muted)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
        .font(.subheadline)
    }
}

private struct DriverCallOverlay: View {
    let driverName: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "phone.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                Text("Calling \(driverName)...")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Connecting")
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(.red, in: Circle())
                }
                .padding(.bottom, 48)
            }
        }
    }
}

private struct DriverChatSheet: View {
    let driverName: String
    @Environment(\.dismiss) private var dismiss
    @State private var messageText: String = ""
    @State private var messages: [(id: UUID, text: String, isOutgoing: Bool)] = [
        (id: UUID(), text: "I'm on my way!", isOutgoing: false),
        (id: UUID(), text: "Almost at your pickup location.", isOutgoing: false)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages, id: \.id) { message in
                            HStack {
                                if message.isOutgoing { Spacer() }
                                Text(message.text)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        message.isOutgoing
                                            ? Color.white.opacity(0.20)
                                            : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .accessibilityIdentifier(message.isOutgoing ? "chat_outgoing_bubble" : "chat_incoming_bubble")
                                if !message.isOutgoing { Spacer() }
                            }
                        }
                    }
                    .padding(16)
                }

                Divider().overlay(CityRideTheme.cardBorder)

                HStack(spacing: 10) {
                    TextField("Message \(driverName)…", text: $messageText)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityIdentifier("chat_message_input")

                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.headline)
                            .frame(width: 40, height: 40)
                            .background(messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? Color.white.opacity(0.15)
                                        : Color.white.opacity(0.85),
                                        in: Circle())
                            .foregroundStyle(messageText.trimmingCharacters(in: .whitespaces).isEmpty ? CityRideTheme.muted : .black)
                    }
                    .buttonStyle(.plain)
                    .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("chat_send_button")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(CityRideTheme.panel)
            }
            .background(CityRideTheme.background)
            .navigationTitle(driverName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("chat_done_button")
                }
            }
        }
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        messages.append((id: UUID(), text: trimmed, isOutgoing: true))
        messageText = ""
    }
}
