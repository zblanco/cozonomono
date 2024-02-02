mod error;

#[rustler::nif]
fn add(a: i64, b: i64) -> i64 {
    a + b
pub use error::ExError;
}

// specify all imported functions from modules we want exposed over NIF
rustler::init!("Elixir.Cozonomono.Native", [add]);
