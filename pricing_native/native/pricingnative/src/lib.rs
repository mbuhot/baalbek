//! Rustler NIF wrapper around the `pricing` crate.
//!
//! This crate has exactly one job: adapt `pricing`'s plain-struct API to
//! primitive types Rustler can pass across the NIF boundary natively (f64,
//! i64, u32, tuples), so `pricing` itself never needs to depend on Rustler
//! or implement `rustler::Encoder` / `Decoder`.

#[rustler::nif]
fn quote(
    distance_km: f64,
    rate_per_km_cents: i64,
    labour_hours: f64,
    hourly_rate_cents: i64,
    minimum_charge_cents: i64,
    parts: Vec<(u32, i64)>,
) -> (i64, i64, i64, i64) {
    let travel = pricing::TravelParams {
        distance_km,
        rate_per_km_cents,
    };
    let labour = pricing::LabourParams {
        hours: labour_hours,
        hourly_rate_cents,
        minimum_charge_cents,
    };
    let parts: Vec<pricing::PartLineItem> = parts
        .into_iter()
        .map(|(quantity, unit_price_cents)| pricing::PartLineItem {
            quantity,
            unit_price_cents,
        })
        .collect();

    let result = pricing::quote(travel, labour, &parts);

    (
        result.travel_cents,
        result.labour_cents,
        result.parts_cents,
        result.total_cents,
    )
}

rustler::init!("Elixir.PricingNative.Native");
// Exercise: a Rust NIF change, to measure what CI rebuilds.
