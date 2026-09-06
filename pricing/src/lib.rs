//! Field-service job quote computation: travel + labour + parts.
//!
//! Per PLAN.md's Component inventory ("`pricing` — Rust crate — Quote
//! computation: travel + labour + parts. `cargo test`.") and seed.md §3
//! ("Rust: NIF behind a facade app"), this crate is the performance-critical
//! computation living behind the `pricing_native` Elixir facade. Every
//! public type here is a plain struct of primitives (`f64`, `i64`, `u32`)
//! Rustler can pass across the NIF boundary without a custom `Encoder` /
//! `Decoder` impl — the facade's native crate destructures/builds these
//! directly from NIF argument primitives.
//!
//! All monetary amounts are integer cents (`i64`), never floating point —
//! floats are only used for physically continuous inputs (distance,
//! duration), and every place a float feeds into money is rounded exactly
//! once, at the point of conversion.

/// Inputs to the travel-cost component of a quote: distance driven times a
/// flat per-kilometre rate.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TravelParams {
    pub distance_km: f64,
    pub rate_per_km_cents: i64,
}

/// Inputs to the labour-cost component of a quote: estimated hours times an
/// hourly rate, floored at a minimum callout charge (a technician dispatched
/// for a 15-minute fix still costs a truck roll).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LabourParams {
    pub hours: f64,
    pub hourly_rate_cents: i64,
    pub minimum_charge_cents: i64,
}

/// A single parts line item: some quantity of a part at a unit price.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PartLineItem {
    pub quantity: u32,
    pub unit_price_cents: i64,
}

/// The computed breakdown of a job quote. All amounts are integer cents.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Quote {
    pub travel_cents: i64,
    pub labour_cents: i64,
    pub parts_cents: i64,
    pub total_cents: i64,
}

/// Travel cost: `distance_km * rate_per_km_cents`, rounded to the nearest
/// cent. Rounding happens exactly once, here, at the float-to-money
/// boundary.
pub fn travel_cost_cents(params: TravelParams) -> i64 {
    (params.distance_km * params.rate_per_km_cents as f64).round() as i64
}

/// Labour cost: `hours * hourly_rate_cents`, rounded to the nearest cent,
/// then floored at `minimum_charge_cents` — a callout that computes below
/// the minimum still bills the minimum.
pub fn labour_cost_cents(params: LabourParams) -> i64 {
    let computed = (params.hours * params.hourly_rate_cents as f64).round() as i64;
    computed.max(params.minimum_charge_cents)
}

/// Parts cost: the sum of `quantity * unit_price_cents` over every line
/// item. An empty parts list costs nothing.
pub fn parts_cost_cents(items: &[PartLineItem]) -> i64 {
    items
        .iter()
        .map(|item| item.unit_price_cents * i64::from(item.quantity))
        .sum()
}

/// Applies a whole-percentage discount to an already-computed total,
/// rounded to the nearest cent. Used, e.g., for loyalty-customer quotes.
/// A `percent_off` of 0 returns the amount unchanged; 100 returns 0.
pub fn apply_percent_discount_cents(total_cents: i64, percent_off: u8) -> i64 {
    let percent_off = percent_off.min(100);
    let retained = 100 - i64::from(percent_off);
    ((total_cents as f64) * (retained as f64) / 100.0).round() as i64
}

/// Whether a percentage discount is even meaningful to apply (a 0% discount
/// is a no-op the caller can skip).
pub fn is_discount_applicable(percent_off: u8) -> bool {
    percent_off > 0
}

/// Rounds a cents amount up to the nearest whole dollar (e.g. for
/// display on a receipt that doesn't show cents). 12345 -> 12400.
pub fn round_up_to_dollar_cents(cents: i64) -> i64 {
    let remainder = cents.rem_euclid(100);
    if remainder == 0 {
        cents
    } else {
        cents + (100 - remainder)
    }
}

/// Computes a full job quote from its three components.
pub fn quote(travel: TravelParams, labour: LabourParams, parts: &[PartLineItem]) -> Quote {
    let travel_cents = travel_cost_cents(travel);
    let labour_cents = labour_cost_cents(labour);
    let parts_cents = parts_cost_cents(parts);

    Quote {
        travel_cents,
        labour_cents,
        parts_cents,
        total_cents: travel_cents + labour_cents + parts_cents,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn travel(distance_km: f64, rate_per_km_cents: i64) -> TravelParams {
        TravelParams {
            distance_km,
            rate_per_km_cents,
        }
    }

    fn labour(hours: f64, hourly_rate_cents: i64, minimum_charge_cents: i64) -> LabourParams {
        LabourParams {
            hours,
            hourly_rate_cents,
            minimum_charge_cents,
        }
    }

    fn part(quantity: u32, unit_price_cents: i64) -> PartLineItem {
        PartLineItem {
            quantity,
            unit_price_cents,
        }
    }

    #[test]
    fn travel_cost_is_distance_times_rate() {
        // 42 km at $1.50/km = $63.00
        assert_eq!(travel_cost_cents(travel(42.0, 150)), 6300);
    }

    #[test]
    fn travel_cost_rounds_to_nearest_cent() {
        // 10.005 km at 100 cents/km = 1000.5 cents -> rounds to 1001 (round-half-up
        // for positive values, per f64::round).
        assert_eq!(travel_cost_cents(travel(10.005, 100)), 1001);
    }

    #[test]
    fn travel_cost_rounds_down_below_the_halfway_point() {
        // 10.003 km at 100 cents/km = 1000.3 cents -> rounds down to 1000,
        // covering the round-DOWN direction (the test above only exercises
        // the exact .5 tie-break).
        assert_eq!(travel_cost_cents(travel(10.003, 100)), 1000);
    }

    #[test]
    fn zero_distance_costs_nothing() {
        assert_eq!(travel_cost_cents(travel(0.0, 150)), 0);
    }

    #[test]
    fn labour_cost_is_hours_times_rate_when_above_minimum() {
        // 3 hours at $80/hr = $240.00, above a $100 minimum.
        assert_eq!(labour_cost_cents(labour(3.0, 8000, 10000)), 24000);
    }

    #[test]
    fn labour_cost_floors_at_minimum_charge() {
        // 15 minutes (0.25h) at $80/hr = $20.00, floored to the $100 minimum
        // callout charge.
        assert_eq!(labour_cost_cents(labour(0.25, 8000, 10000)), 10000);
    }

    #[test]
    fn labour_cost_at_exactly_the_minimum_is_not_bumped_further() {
        // 1.25 hours at $80/hr = $100.00 exactly, equal to the minimum.
        assert_eq!(labour_cost_cents(labour(1.25, 8000, 10000)), 10000);
    }

    #[test]
    fn parts_cost_sums_line_items() {
        let items = vec![part(2, 500), part(1, 12000), part(3, 0)];
        // 2*500 + 1*12000 + 3*0 = 13000
        assert_eq!(parts_cost_cents(&items), 13000);
    }

    #[test]
    fn zero_parts_cost_nothing() {
        assert_eq!(parts_cost_cents(&[]), 0);
    }

    #[test]
    fn full_quote_sums_all_three_components() {
        let result = quote(
            travel(42.0, 150),               // 6300
            labour(3.0, 8000, 10000),        // 24000
            &[part(2, 500), part(1, 12000)], // 13000
        );

        assert_eq!(
            result,
            Quote {
                travel_cents: 6300,
                labour_cents: 24000,
                parts_cents: 13000,
                total_cents: 43300,
            }
        );
    }

    #[test]
    fn percent_discount_reduces_total_proportionally() {
        // 10% off $100.00 = $90.00
        assert_eq!(apply_percent_discount_cents(10000, 10), 9000);
    }

    #[test]
    fn zero_percent_discount_is_unchanged() {
        assert_eq!(apply_percent_discount_cents(4300, 0), 4300);
    }

    #[test]
    fn hundred_percent_discount_is_free() {
        assert_eq!(apply_percent_discount_cents(4300, 100), 0);
    }

    #[test]
    fn percent_discount_clamps_above_100() {
        assert_eq!(apply_percent_discount_cents(4300, 250), 0);
    }

    #[test]
    fn zero_percent_is_not_applicable() {
        assert!(!is_discount_applicable(0));
    }

    #[test]
    fn nonzero_percent_is_applicable() {
        assert!(is_discount_applicable(1));
        assert!(is_discount_applicable(100));
    }

    #[test]
    fn round_up_to_dollar_rounds_up_a_partial_amount() {
        assert_eq!(round_up_to_dollar_cents(12345), 12400);
    }

    #[test]
    fn round_up_to_dollar_leaves_an_exact_amount_unchanged() {
        assert_eq!(round_up_to_dollar_cents(12400), 12400);
    }

    #[test]
    fn full_quote_with_no_parts_and_minimum_charge_labour() {
        let result = quote(
            travel(0.0, 150),         // 0
            labour(0.1, 8000, 10000), // floored to 10000
            &[],
        );

        assert_eq!(
            result,
            Quote {
                travel_cents: 0,
                labour_cents: 10000,
                parts_cents: 0,
                total_cents: 10000,
            }
        );
    }
}
