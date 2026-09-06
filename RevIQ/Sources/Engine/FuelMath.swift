import Foundation

/// Fuel-consumption estimation from MAF (mass air flow), per SAE J1979.
/// fuel g/s = air g/s / AFR;  L/h = g/s * 3600 / density(g/L)
enum FuelMath {

    struct FuelConstants {
        let afr: Double        // stoichiometric air-fuel ratio
        let densityGL: Double  // grams per liter
    }

    static func constants(for fuel: FuelType) -> FuelConstants {
        switch fuel {
        case .gasoline: return FuelConstants(afr: 14.7, densityGL: 745)
        case .hybrid: return FuelConstants(afr: 14.7, densityGL: 745)
        case .diesel: return FuelConstants(afr: 14.5, densityGL: 840)
        case .lpg: return FuelConstants(afr: 15.5, densityGL: 540)
        }
    }

    /// Liters per hour at the given MAF reading.
    static func litersPerHour(maf: Double, fuel: FuelType) -> Double {
        let c = constants(for: fuel)
        return (maf / c.afr) * 3600 / c.densityGL
    }

    /// Instant consumption in L/100km. Returns nil while coasting/slow (<3 km/h).
    static func instantL100(maf: Double, speedKmh: Double, fuel: FuelType) -> Double? {
        guard speedKmh >= 3 else { return nil }
        let lph = litersPerHour(maf: maf, fuel: fuel)
        return lph / speedKmh * 100
    }

    /// Ideal reference consumption curve for a typical compact car (L/100km at cruise).
    static func idealL100(speedKmh: Double) -> Double {
        guard speedKmh > 3 else { return 4.5 }
        // sweet spot ~ 75 km/h, rising with aero drag
        return 3.4 + 0.045 * speedKmh + 0.00035 * pow(speedKmh - 75, 2)
    }

    /// Grams of CO2 per liter of burned fuel.
    static func co2Kg(liters: Double, fuel: FuelType) -> Double {
        let factor: Double
        switch fuel {
        case .diesel: factor = 2.68
        case .lpg: factor = 1.51
        default: factor = 2.31
        }
        return liters * factor / 1000  // kg
    }

    /// MAF-based engine power estimate (rough, for Sport dashboard).
    static func powerKW(maf: Double, rpm: Double) -> Double {
        // ~ assumes thermal efficiency ~ 33% and energy 44 MJ/kg gasoline
        let fuelGS = maf / 14.7
        let watts = fuelGS * 44_000_000 * 0.33
        return watts / 1000
    }
}
