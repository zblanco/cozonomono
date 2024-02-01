// use cozo::*;

#[rustler::nif]
fn add(a: i64, b: i64) -> i64 {
    a + b
}

// specify all imported functions from modules we want exposed over NIF
rustler::init!("Elixir.Cozonomono.Native", [add]);
