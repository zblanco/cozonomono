mod datatypes;
mod error;

pub use datatypes::{ExDbInstance, ExDbInstanceRef};
pub use error::ExError;
use rustler::{Env, Term};

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ExDbInstanceRef, env);
    rustler::resource!(ExDbInstance, env);
    true
}

// specify all imported functions from modules we want exposed over NIF
rustler::init!("Elixir.Cozonomono.Native", [add]);
