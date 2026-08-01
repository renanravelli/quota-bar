public extension QuotaSnapshot {
    var unavailableFields: Set<UnavailableField> {
        var absent: Set<UnavailableField> = []

        if bindingWindow == nil { absent.insert(.bindingWindow) }
        if overage.status == nil, overage.disabledReason == nil { absent.insert(.overage) }
        if fallbackPercentage == nil { absent.insert(.fallbackPercentage) }

        for window in [QuotaWindow.fiveHour, .sevenDay] {
            let value = reading(for: window)
            if value.utilization == nil { absent.insert(.utilization(window)) }
            if value.resetsAt == nil { absent.insert(.resetAt(window)) }
        }

        return absent
    }
}
