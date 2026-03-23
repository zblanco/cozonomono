mod datatypes;
mod error;

pub use datatypes::{
    ExDataValue, ExDbInstance, ExDbInstanceRef, ExMultiTransaction, ExMultiTransactionRef,
    ExNamedRows,
};
pub use error::ExError;
use rustler::{Env, Term};
use std::collections::{BTreeMap, HashMap};

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ExDbInstanceRef, env);
    rustler::resource!(ExDbInstance, env);
    rustler::resource!(ExMultiTransactionRef, env);
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

#[rustler::nif(schedule = "DirtyCpu")]
fn export_relations(
    instance: ExDbInstance,
    relations: Vec<String>,
) -> Result<HashMap<String, ExNamedRows>, ExError> {
    let result = instance.export_relations(relations.iter().map(|s| s.as_str()))?;
    Ok(result
        .into_iter()
        .map(|(k, v)| (k, ExNamedRows(v)))
        .collect())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn import_relations(
    instance: ExDbInstance,
    data: HashMap<String, ExNamedRows>,
) -> Result<rustler::Atom, ExError> {
    let data: BTreeMap<String, cozo::NamedRows> = data.into_iter().map(|(k, v)| (k, v.0)).collect();
    instance.import_relations(data)?;
    Ok(rustler::types::atom::ok())
}

// --- Backup / Restore ---

#[rustler::nif(schedule = "DirtyCpu")]
fn backup_db(instance: ExDbInstance, path: String) -> Result<rustler::Atom, ExError> {
    instance.backup_db(&path)?;
    Ok(rustler::types::atom::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn restore_backup(instance: ExDbInstance, path: String) -> Result<rustler::Atom, ExError> {
    instance.restore_backup(&path)?;
    Ok(rustler::types::atom::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn import_from_backup(
    instance: ExDbInstance,
    path: String,
    relations: Vec<String>,
) -> Result<rustler::Atom, ExError> {
    instance.import_from_backup(&path, &relations)?;
    Ok(rustler::types::atom::ok())
}

// --- Multi-Statement Transactions ---

#[rustler::nif(schedule = "DirtyCpu")]
fn multi_transaction(instance: ExDbInstance, write: bool) -> ExMultiTransaction {
    let tx = instance.multi_transaction(write);
    ExMultiTransaction::new(tx, write)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn tx_run_script(
    tx: ExMultiTransaction,
    payload: String,
    params: HashMap<String, ExDataValue>,
) -> Result<ExNamedRows, ExError> {
    let params = params
        .into_iter()
        .map(|(k, v)| (k, v.0))
        .collect::<BTreeMap<String, cozo::DataValue>>();
    Ok(ExNamedRows(tx.run_script(&payload, params)?))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn tx_commit(tx: ExMultiTransaction) -> Result<rustler::Atom, ExError> {
    tx.commit()?;
    Ok(rustler::types::atom::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn tx_abort(tx: ExMultiTransaction) -> Result<rustler::Atom, ExError> {
    tx.abort()?;
    Ok(rustler::types::atom::ok())
}

#[rustler::nif]
fn close_instance(instance: ExDbInstance) -> Result<rustler::Atom, ExError> {
    // Dropping the ExDbInstance causes the ResourceArc reference count to decrement.
    // If this is the last reference, the inner DbInstance is dropped, releasing
    // all resources (file handles, locks, memory).
    drop(instance);
    Ok(rustler::types::atom::ok())
}

rustler::init!(
    "Elixir.Cozonomono.Native",
    [
        create_instance,
        run_default,
        run_script,
        export_relations,
        import_relations,
        backup_db,
        restore_backup,
        import_from_backup,
        multi_transaction,
        tx_run_script,
        tx_commit,
        tx_abort,
        close_instance
    ],
    load = on_load
);
