mod datatypes;
mod error;

use datatypes::atoms;
use datatypes::{encode_data_value, encode_named_rows, flatten_named_rows};
pub use datatypes::{
    ExDataValue, ExDbInstance, ExDbInstanceRef, ExFixedRuleBridge, ExFixedRuleBridgeRef,
    ExLazyRows, ExLazyRowsRef, ExMultiTransaction, ExMultiTransactionRef, ExNamedRows,
};
pub use error::ExError;
use rustler::types::LocalPid;
use rustler::{Encoder, Env, ResourceArc, Term};
use std::collections::{BTreeMap, HashMap};

fn on_load(env: Env, _info: Term) -> bool {
    rustler::resource!(ExDbInstanceRef, env);
    rustler::resource!(ExDbInstance, env);
    rustler::resource!(ExMultiTransactionRef, env);
    rustler::resource!(ExLazyRowsRef, env);
    rustler::resource!(ExFixedRuleBridgeRef, env);
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

// --- Change Callbacks ---

#[rustler::nif(schedule = "DirtyCpu")]
fn register_callback(
    instance: ExDbInstance,
    relation: String,
    pid: LocalPid,
    capacity: Option<usize>,
) -> u32 {
    let (id, receiver) = instance.register_callback(&relation, capacity);

    std::thread::spawn(move || {
        let mut msg_env = rustler::env::OwnedEnv::new();

        while let Ok((op, new_rows, old_rows)) = receiver.recv() {
            let op_atom = match op {
                cozo::CallbackOp::Put => atoms::put(),
                cozo::CallbackOp::Rm => atoms::rm(),
            };

            let result = msg_env.send_and_clear(&pid, |env| {
                (
                    atoms::cozo_callback(),
                    op_atom,
                    ExNamedRows(new_rows).encode(env),
                    ExNamedRows(old_rows).encode(env),
                )
                    .encode(env)
            });

            if result.is_err() {
                break;
            }
        }
    });

    id
}

#[rustler::nif]
fn unregister_callback(instance: ExDbInstance, id: u32) -> bool {
    instance.unregister_callback(id)
}

// --- Custom Fixed Rules ---

#[rustler::nif(schedule = "DirtyCpu")]
fn register_fixed_rule(
    instance: ExDbInstance,
    name: String,
    return_arity: usize,
    pid: LocalPid,
) -> Result<ExFixedRuleBridge, ExError> {
    let (rule, receiver) = cozo::SimpleFixedRule::rule_with_channel(return_arity);

    instance.register_fixed_rule(name.clone(), rule)?;

    let bridge = ExFixedRuleBridge::new(ExFixedRuleBridgeRef::new(pid, name));
    let bridge_resource = bridge.resource.clone();

    std::thread::spawn(move || {
        let mut msg_env = rustler::env::OwnedEnv::new();

        for (inputs, options, response_sender) in receiver {
            let request_id = bridge_resource
                .next_request_id
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);

            bridge_resource
                .pending
                .lock()
                .unwrap()
                .insert(request_id, response_sender);

            let bridge_pid = bridge_resource.pid;
            let bridge_arc = bridge_resource.clone();

            let result = msg_env.send_and_clear(&bridge_pid, |env| {
                let inputs_term: Vec<rustler::Term> = inputs
                    .into_iter()
                    .map(|nr| ExNamedRows(nr).encode(env))
                    .collect();

                let options_term = {
                    let mut map = rustler::Term::map_new(env);
                    for (k, v) in options {
                        map = map
                            .map_put(k.as_str().encode(env), ExDataValue(v).encode(env))
                            .expect("Failed to encode option");
                    }
                    map
                };

                (
                    atoms::cozo_fixed_rule(),
                    request_id,
                    inputs_term,
                    options_term,
                )
                    .encode(env)
            });

            if result.is_err() {
                if let Some(sender) = bridge_arc.pending.lock().unwrap().remove(&request_id) {
                    let _ = sender.send(Err(miette::miette!("fixed rule handler process is down")));
                }
                break;
            }
        }

        bridge_resource.fail_all_pending("fixed rule channel closed");
    });

    Ok(bridge)
}

#[rustler::nif(schedule = "DirtyCpu")]
fn respond_fixed_rule(
    bridge: ExFixedRuleBridge,
    request_id: u64,
    result: ExNamedRows,
) -> Result<rustler::Atom, ExError> {
    let sender = bridge
        .pending
        .lock()
        .unwrap()
        .remove(&request_id)
        .ok_or_else(|| ExError::FixedRule("unknown or expired request_id".to_string()))?;

    sender
        .send(Ok(result.0))
        .map_err(|_| ExError::FixedRule("cozo query was cancelled".to_string()))?;

    Ok(rustler::types::atom::ok())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn unregister_fixed_rule(instance: ExDbInstance, name: String) -> Result<bool, ExError> {
    let result = instance.unregister_fixed_rule(&name)?;
    Ok(result)
}

// --- Lazy Rows (zero-copy query results) ---

#[rustler::nif(schedule = "DirtyCpu")]
fn run_default_lazy(instance: ExDbInstance, payload: String) -> Result<ExLazyRows, ExError> {
    let named_rows = instance.run_default(&payload)?;
    let chain = ResourceArc::new(ExLazyRowsRef(flatten_named_rows(named_rows)));
    Ok(ExLazyRows::from_chain(chain, 0))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn run_script_lazy(
    instance: ExDbInstance,
    payload: String,
    params: HashMap<String, ExDataValue>,
    immutable: bool,
) -> Result<ExLazyRows, ExError> {
    let mutability = if immutable {
        cozo::ScriptMutability::Immutable
    } else {
        cozo::ScriptMutability::Mutable
    };
    let params = params
        .into_iter()
        .map(|(k, v)| (k, v.0))
        .collect::<BTreeMap<String, cozo::DataValue>>();
    let named_rows = instance.run_script(&payload, params, mutability)?;
    let chain = ResourceArc::new(ExLazyRowsRef(flatten_named_rows(named_rows)));
    Ok(ExLazyRows::from_chain(chain, 0))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn tx_run_script_lazy(
    tx: ExMultiTransaction,
    payload: String,
    params: HashMap<String, ExDataValue>,
) -> Result<ExLazyRows, ExError> {
    let params = params
        .into_iter()
        .map(|(k, v)| (k, v.0))
        .collect::<BTreeMap<String, cozo::DataValue>>();
    let named_rows = tx.run_script(&payload, params)?;
    let chain = ResourceArc::new(ExLazyRowsRef(flatten_named_rows(named_rows)));
    Ok(ExLazyRows::from_chain(chain, 0))
}

#[rustler::nif]
fn lazy_rows_next(lazy: ExLazyRows) -> Result<ExLazyRows, rustler::Atom> {
    let next_idx = lazy.statement_index + 1;
    if next_idx >= lazy.resource.0.len() {
        Err(atoms::out_of_bounds())
    } else {
        Ok(ExLazyRows::from_chain(lazy.resource, next_idx))
    }
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lazy_rows_row_at(env: Env, lazy: ExLazyRows, index: usize) -> Result<Term, rustler::Atom> {
    let nr = &lazy.resource.0[lazy.statement_index];
    let row = nr.rows.get(index).ok_or(atoms::out_of_bounds())?;
    Ok(row
        .iter()
        .map(|dv| encode_data_value(dv, env))
        .collect::<Vec<Term>>()
        .encode(env))
}

#[rustler::nif]
fn lazy_rows_cell_at(
    env: Env,
    lazy: ExLazyRows,
    row_index: usize,
    col_index: usize,
) -> Result<Term, rustler::Atom> {
    let nr = &lazy.resource.0[lazy.statement_index];
    let row = nr.rows.get(row_index).ok_or(atoms::out_of_bounds())?;
    let cell = row.get(col_index).ok_or(atoms::out_of_bounds())?;
    Ok(encode_data_value(cell, env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lazy_rows_column_at(
    env: Env,
    lazy: ExLazyRows,
    col_index: usize,
) -> Result<Term, rustler::Atom> {
    let nr = &lazy.resource.0[lazy.statement_index];
    if col_index >= nr.headers.len() {
        return Err(atoms::out_of_bounds());
    }
    Ok(nr
        .rows
        .iter()
        .map(|row| encode_data_value(&row[col_index], env))
        .collect::<Vec<Term>>()
        .encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lazy_rows_slice(
    env: Env,
    lazy: ExLazyRows,
    offset: usize,
    length: usize,
) -> Result<Term, rustler::Atom> {
    let nr = &lazy.resource.0[lazy.statement_index];
    if offset > nr.rows.len() {
        return Err(atoms::out_of_bounds());
    }
    let end = std::cmp::min(offset + length, nr.rows.len());
    Ok(nr.rows[offset..end]
        .iter()
        .map(|row| {
            row.iter()
                .map(|dv| encode_data_value(dv, env))
                .collect::<Vec<Term>>()
                .encode(env)
        })
        .collect::<Vec<Term>>()
        .encode(env))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn lazy_rows_to_named_rows(env: Env, lazy: ExLazyRows) -> Term {
    let nr = &lazy.resource.0[lazy.statement_index];
    encode_named_rows(nr, env)
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
        register_callback,
        unregister_callback,
        register_fixed_rule,
        respond_fixed_rule,
        unregister_fixed_rule,
        run_default_lazy,
        run_script_lazy,
        tx_run_script_lazy,
        lazy_rows_next,
        lazy_rows_row_at,
        lazy_rows_cell_at,
        lazy_rows_column_at,
        lazy_rows_slice,
        lazy_rows_to_named_rows,
        close_instance
    ],
    load = on_load
);
