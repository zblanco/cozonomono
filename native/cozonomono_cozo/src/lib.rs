mod datatypes;
mod error;

pub use datatypes::{ExDataValue, ExDbInstance, ExDbInstanceRef, ExNamedRows};
pub use error::ExError;
use rustler::{Env, Term};
use std::collections::{BTreeMap, HashMap};

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ExDbInstanceRef, env);
    rustler::resource!(ExDbInstance, env);
    true
}

#[rustler::nif(schedule = "DirtyCpu")]
fn create_instance(engine: String, path: String) -> Result<ExDbInstance, ExError> {
    let instance = cozo::DbInstance::new(&engine, &path, "")?;
    Ok(ExDbInstance::new(instance, engine, path))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_default(instance: ExDbInstance, payload: String) -> Result<ExNamedRows, ExError> {
    Ok(ExNamedRows(instance.run_default(&payload)?))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_script(
    instance: ExDbInstance,
    payload: String,
    params: HashMap<String, ExDataValue>,
    immutable: bool,
) -> Result<ExNamedRows, ExError> {
    let mutability = if immutable {
        cozo::ScriptMutability::Immutable
    } else {
        cozo::ScriptMutability::Mutable
    };

    let params = params
        .into_iter()
        .map(|(k, v)| (k, v.0))
        .collect::<BTreeMap<String, cozo::DataValue>>();

    Ok(ExNamedRows(
        instance.run_script(&payload, params, mutability)?,
    ))
}

rustler::init!(
    "Elixir.Cozonomono.Native",
    [create_instance, run_default, run_script],
    load = on_load
);
